`timescale 1ns / 1ps

module i2c_master #(
    parameter int CLK_FREQ = 100_000_000,   // clock sistem
    parameter int I2C_FREQ = 100_000        // 100 kHz standard
)(
    input logic clk,
    input logic reset,
    
    // Comenzi
    input logic enable,
    input logic rw, // 1=Read, 0=Write

    // Date
    input logic [6:0] addr,
    input logic [7:0] data_in,
    output logic [7:0] data_out,
    input logic [3:0] num_bytes,      // câte bytes (1 sau 2 pentru temperatur?)
    
    // Status
    output logic busy,
    output logic done,
    output logic ack_error,
    
    // I2C
    input logic sda,
    output logic scl
    );
    
// generare clock 4× I2C (4 faze pe bit)
localparam integer DIV = CLK_FREQ / (I2C_FREQ * 4);

logic [15:0] clk_cnt;
logic scl_clk; // 4× frecven?a I2C

always @(posedge clk) begin
    if (reset) begin
        clk_cnt <= 16'd0;
        scl_clk <= 1'b0;
    end 
    else if (clk_cnt == DIV-1) begin
        clk_cnt <= 16'd0;
        scl_clk <= ~scl_clk;
    end 
    else begin
        clk_cnt <= clk_cnt + 1;
    end
end 
       
typedef enum logic [3:0] {
    IDLE,        // A?teapt? semnalul start. Magistrala este liber? (SCL ?i SDA high).
    START,       // Genereaz? condi?ia de START: SDA trece din high în low cât timp SCL este high.
    ADDR,        // Trimite pe magistral? adresa slave-ului (7 bi?i) + bitul R/W.
    ACK_ADDR,    // Elibereaz? SDA ?i cite?te ACK-ul de la slave dup? trimiterea adresei.
    WRITE_DATA,  // Trimite un byte de date c?tre slave (bit cu bit).
    ACK_WRITE,   // Elibereaz? SDA ?i cite?te ACK-ul de la slave dup? scrierea unui byte.
    RESTART,     // Genereaz? Repeated START (folosit de obicei la citire dup? scrierea pointerului).
    READ_DATA,   // Cite?te un byte de date de la slave (bit cu bit).
    ACK_READ,    // Masterul trimite ACK (SDA=0) pentru a cere urm?torul byte.
    NACK,        // Masterul trimite NACK (SDA=1) pentru a semnala c? a citit ultimul byte.
    STOP,        // Genereaz? condi?ia de STOP: SDA trece din low în high cât timp SCL este high.
    DONE_ST      // Tranzac?ia s-a terminat. Seteaz? done=1, busy=0 ?i trece în IDLE.
} i2c_state_t;

i2c_state_t i2c_state;

logic [7:0] shift_reg;
logic [2:0] bit_counter;
logic [3:0] byte_counter;
logic [1:0] phase; // 0=high, 1=falling, 2=low, 3=rising
logic [15:0] rdata; // buffer intern unde se adun? cei 2 bytes citi?i, înainte de a-i pune pe portul data_out

// Open-drain control
// oe: output enable
// oe = 1 ? drive 0 pe magistral?
// oe = 0 ? release (high-Z)
logic sda_oe;
logic scl_oe;

assign sda = sda_oe ? 1'b0 : 1'bz;
assign scl = scl_oe ? 1'b0 : 1'bz;
    
always @(posedge clk) begin
    if (reset) begin
        i2c_state <= IDLE;
        bit_counter <= 3'd0;
        byte_counter <= 4'd0;
        phase <= 2'd0;
        shift_reg <= 8'd0;
        rdata <= 16'd0;
        busy <= 1'b0;
        done <= 1'b0;
        ack_error <= 1'b0;
        sda_oe <= 1'b0; 
        scl_oe <= 1'b0; 
        data_out <= 16'd0;
    end else begin
        done <= 1'b0;
        phase <= phase + 1;
        case (phase)
            2'd0: scl_oe <= 1'b0;   // SCL high (release)
            2'd1: scl_oe <= 1'b1;   // falling ? drive low
            2'd2: scl_oe <= 1'b1;   // SCL low
            2'd3: scl_oe <= 1'b0;   // rising ? release
        endcase
        case (i2c_state)
            IDLE: begin
                busy <= 1'b0;
                sda_oe <= 1'b0;
                scl_oe <= 1'b0;
                phase <= 2'd0;
                if (enable) begin
                    busy <= 1'b1;
                    ack_error <= 1'b0;
                    shift_reg <= {addr, rw};
                    bit_counter <= 3'd7;
                    byte_counter <= num_bytes;
                    i2c_state <= START;
                end
            end
            START: begin
                // conditie START: SDA low cat timp SCL high
                if (phase == 2'd0) begin
                    sda_oe <= 1'b1; // SDA = 0
                end
                if (phase == 2'd3) begin
                    i2c_state <= ADDR;
                    phase <= 2'd0;
                end
            end
            ADDR: begin
                // trimitem adresa + R/W
                if (phase == 2'd2) begin  // pe SCL low punem bitul
                    // bit = 0 ? drive low (oe=1)
                    // bit = 1 ? release (oe=0)
                    sda_oe <= ~shift_reg[bit_counter];
                end
                if (phase == 2'd3) begin
                    if (bit_counter == 0) begin
                        i2c_state <= ACK_ADDR;
                        bit_counter <= 3'd7;
                    end else begin
                        bit_counter <= bit_counter - 1;
                    end
                end
             end
             ACK_ADDR: begin
                sda_oe <= 1'b0; // eliberam SDA (citim ACK)
                if (phase == 2'd0) begin // e?antion?m pe SCL high
                    if (sda == 1'b1)
                        ack_error <= 1'b1;
                end
                if (phase == 2'd3) begin
                    if (rw)
                        i2c_state <= READ_DATA;
                    else begin
                        i2c_state <= WRITE_DATA;
                        shift_reg <= data_in;
                        bit_counter <= 3'd7;
                    end
                end
             end
             WRITE_DATA: begin
                    if (phase == 2'd2) begin
                        sda_oe <= ~shift_reg[bit_counter];
                    end
                    if (phase == 2'd3) begin
                        if (bit_counter == 0) begin
                            i2c_state <= ACK_WRITE;
                        end else begin
                            bit_counter <= bit_counter - 1;
                        end
                    end
             end
             ACK_WRITE: begin
                sda_oe <= 1'b0;  // eliberam
                if (phase == 2'd0) begin
                    if (sda == 1'b1)
                        ack_error <= 1'b1;
                end
                if (phase == 2'd3) begin
                    if (byte_counter <= 1) begin
                        i2c_state <= STOP;
                    end else begin
                        byte_counter  <= byte_counter - 1;
                        shift_reg <= data_in;  // urm?torul byte
                        bit_counter <= 3'd7;
                        i2c_state <= WRITE_DATA;
                    end
                end
             end
             // Repeated START (write pointer + read)
             RESTART: begin
                if (phase == 2'd0) begin
                    sda_oe <= 1'b0;   // SDA high
                end
                if (phase == 2'd1) begin
                    sda_oe <= 1'b1;  // SDA low ? repeated start
                end
                if (phase == 2'd3) begin
                    shift_reg <= {addr, 1'b1}; // address + read
                    bit_counter <= 3'd7;
                    i2c_state <= ADDR;
                end
             end
             READ_DATA: begin
                sda_oe <= 1'b0;    // eliberam (slave drive)
                if (phase == 2'd0) begin  // e?antion?m pe SCL high
                    shift_reg <= {shift_reg[6:0], sda};
                end
                if (phase == 2'd3) begin
                    if (bit_counter == 0) begin
                        // salv?m byte-ul
                        if (byte_counter == num_bytes)
                            rdata[15:8] <= shift_reg;
                        else
                            rdata[7:0]  <= shift_reg;
                        if (byte_counter <= 1)
                            i2c_state <= NACK;
                        else
                            i2c_state <= ACK_READ;
                    end else begin
                        bit_counter <= bit_counter - 1;
                    end
                end
             end
             ACK_READ: begin
                // Master ACK (drive low)
                if (phase == 2'd2)
                    sda_oe <= 1'b1;
                if (phase == 2'd3) begin
                    byte_counter <= byte_counter - 1;
                    bit_counter  <= 3'd7;
                    i2c_state    <= READ_DATA;
                end
             end
             NACK: begin
                // Master NACK (release)
                if (phase == 2'd2)
                    sda_oe <= 1'b0;
                if (phase == 2'd3)
                    i2c_state <= STOP;
             end
             STOP: begin
                // STOP: SDA low ? SCL high ? SDA high
                if (phase == 2'd0) begin
                    sda_oe <= 1'b1; // SDA = 0
                end
                if (phase == 2'd1) begin
                    scl_oe <= 1'b0;   // SCL high
                end
                if (phase == 2'd2) begin
                    sda_oe <= 1'b0; // SDA high ? STOP
                end
                if (phase == 2'd3) begin
                    i2c_state <= DONE_ST;
                end
             end
             DONE_ST: begin
                done <= 1'b1;
                busy <= 1'b0;
                data_out <= rdata;
                i2c_state <= IDLE;
             end
             default: i2c_state <= IDLE;    
        endcase
    end
end
endmodule