`timescale 1ns / 1ps

module i2c_master_v2 #(
    parameter int CLK_FREQ = 100_000_000,
    parameter int I2C_FREQ = 100_000
)(
    input  logic clk,
    input logic reset,

    // Pornire tranzactie
    input logic enable,

    // Adresa slave-ului, 7 biti
    input logic [6:0] addr,

    // Registrul care trebuie citit
    input logic [7:0] reg_addr,

    // Date pentru WRITE
    input logic [15:0] data_in,

    // Date citite
    // ADT7420 -> 2 bytes: MSB + LSB
    output logic [15:0] data_out,

    // 1 = READ
    // 0 = WRITE
    input logic rw,

    // Status
    output logic busy,
    output logic done,
    output logic ack_error,

    // I2C
    inout wire sda,
    inout wire scl
);

    // CLOCK DIVIDER
    // 100 MHz / (100 kHz * 4) = 250
    // Un i2c_tick apare la fiecare 250 cicluri de clk

    localparam integer DIV = CLK_FREQ / (I2C_FREQ * 4);

    logic [15:0] clk_cnt;
    logic i2c_tick;

    always @(posedge clk) begin
        if (reset) begin
            clk_cnt  <= 16'd0;
            i2c_tick <= 1'b0;
        end
        else begin
            if (clk_cnt == DIV - 1) begin
                clk_cnt  <= 16'd0;
                i2c_tick <= 1'b1;
            end
            else begin
                clk_cnt  <= clk_cnt + 1'b1;
                i2c_tick <= 1'b0;
            end
        end
    end

    typedef enum logic [4:0] {
        ST_IDLE,           // asteapta enable
        ST_START,          // genereaza conditia start
        ST_ADDR_WRITE,     // trimite adresa + bitul de write (0)
        ST_ACK_ADDR_WRITE, // asteapta ack de la slave
        ST_REGISTER,       // trimite adresa registrului 
        ST_ACK_REGISTER,   // asteapta ack
        ST_RESTART,        // doar la citire
        ST_ADDR_READ,      // trimite adresa + bitul de read (1)
        ST_ACK_ADDR_READ,  // asteapta ack
        ST_READ_BYTE,      // citeste un byte
        ST_MASTER_ACK,     // master da ack dupa primul byte
        ST_MASTER_NACK,    // master da nach dupa al doilea byte
        ST_STOP,           // genereaza conditia stop
        ST_DONE            // seteaza done si se intoarce in idle
    } state_t;

    state_t state;

    // Registru folosit pentru transmiterea bitilor
    logic [7:0] shift_reg;

    // Registru folosit pentru receptionarea unui byte
    logic [7:0] read_shift;

    // Registrul I2C
    logic [7:0] register_reg;

    // Date pentru eventual WRITE
    logic [15:0] write_data_reg;

    // Buffer pentru cei 2 bytes cititi
    logic [15:0] rdata;

    // Indexul bitului transmis/citit
    logic [2:0] bit_counter;

    // 0 = urmeaza primul byte (MSB)
    // 1 = urmeaza al doilea byte (LSB)
    logic read_second_byte;

    // PHASE
    // phase = 0: SCL LOW / pregatire
    // phase = 1: SDA este stabilit
    // phase = 2: SCL HIGH -> aici citim SDA
    // phase = 3: terminam bitul si trecem la urmatorul

    logic [1:0] phase;

    // OPEN DRAIN

    logic sda_oe;
    logic scl_oe;

    // oe = 1 -> drive LOW
    // oe = 0 -> release

    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign scl = scl_oe ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            phase <= 2'd0;
            shift_reg <= 8'd0;
            read_shift <= 8'd0;
            register_reg <= 8'd0;
            write_data_reg <= 16'd0;
            rdata <= 16'd0;
            bit_counter <= 3'd0;
            read_second_byte <= 1'b0;
            data_out <= 16'd0;
            busy <= 1'b0;
            done <= 1'b0;
            ack_error <= 1'b0;
            sda_oe <= 1'b0;
            scl_oe <= 1'b0;
        end
        else begin
            // done este un puls de un i2c_tick
            done <= 1'b0;
            if (i2c_tick) begin
                case (state)
                    ST_IDLE: begin
                        busy <= 1'b0;
                        sda_oe <= 1'b0;
                        scl_oe <= 1'b0;
                        phase <= 2'd0;
                        if (enable) begin
                            busy <= 1'b1;
                            ack_error <= 1'b0;
                            rdata <= 16'd0;
                            register_reg <= reg_addr;
                            write_data_reg <= data_in;
                            // Vom citi intotdeauna 2 bytes
                            read_second_byte <= 1'b0;
                            // START va fi urmat de: address + WRITE
                            shift_reg <= {addr,1'b0};
                            bit_counter <= 3'd7;
                            state <= ST_START;
                        end
                    end
                    ST_START: begin
                        // SCL trebuie sa fie HIGH
                        scl_oe <= 1'b0;
                        case (phase)
                            // SDA HIGH
                            2'd0: begin
                                sda_oe <= 1'b0;
                            end
                            // SDA HIGH -> LOW
                            // SCL HIGH
                            2'd1: begin
                                sda_oe <= 1'b1;
                            end
                            // Mentin SDA LOW
                            2'd2: begin
                                sda_oe <= 1'b1;
                            end
                            2'd3: begin
                                sda_oe <= 1'b1;
                                state <= ST_ADDR_WRITE;
                                bit_counter <= 3'd7;
                            end
                        endcase
                    end
                    ST_ADDR_WRITE: begin
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // Punem bitul pe SDA
                            2'd1: begin
                                scl_oe <= 1'b1;
                                sda_oe <= ~shift_reg[bit_counter];
                            end
                            // SCL HIGH
                            2'd2: begin
                                scl_oe <= 1'b0;
                            end
                            // Terminarea bitului
                            2'd3: begin
                                scl_oe <= 1'b1;
                                if (bit_counter == 0) begin
                                    bit_counter <= 3'd7;
                                    state <= ST_ACK_ADDR_WRITE;
                                end
                                else begin
                                    bit_counter <= bit_counter - 1'b1;
                                end
                            end
                        endcase
                    end
                    ST_ACK_ADDR_WRITE: begin
                        // Slave-ul conduce SDA
                        sda_oe <= 1'b0;
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // SCL HIGH
                            2'd1: begin
                                scl_oe <= 1'b0;
                            end
                            // Citim ACK
                            2'd2: begin
                                scl_oe <= 1'b0;
                                if (sda == 1'b1) begin
                                    ack_error <= 1'b1;
                                end
                            end
                            // ACK terminat
                            2'd3: begin
                                scl_oe <= 1'b1;
                                shift_reg <= register_reg;
                                bit_counter <= 3'd7;
                                state <= ST_REGISTER;
                            end
                        endcase
                    end
                    ST_REGISTER: begin
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // Punem bitul
                            2'd1: begin
                                scl_oe <= 1'b1;
                                sda_oe <= ~shift_reg[bit_counter];
                            end
                            // SCL HIGH
                            2'd2: begin
                                scl_oe <= 1'b0;
                            end
                            // Terminam bitul
                            2'd3: begin
                                scl_oe <= 1'b1;
                                if (bit_counter == 0) begin
                                    bit_counter <= 3'd7;
                                    state <= ST_ACK_REGISTER;
                                end
                                else begin
                                    bit_counter <= bit_counter - 1'b1;
                                end
                            end
                        endcase
                    end
                    ST_ACK_REGISTER: begin
                        // Eliberam SDA
                        sda_oe <= 1'b0;
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // Pregatim SCL HIGH
                            2'd1: begin
                                scl_oe <= 1'b0;
                            end
                            // Citim ACK
                            2'd2: begin
                                scl_oe <= 1'b0;
                                if (sda == 1'b1) begin
                                    ack_error <= 1'b1;
                                end
                            end
                            // ACK terminat
                            2'd3: begin
                                scl_oe <= 1'b1;
                                if (rw) begin
                                    state <= ST_RESTART;
                                end
                                else begin
                                    state <= ST_STOP;
                                end
                            end
                        endcase
                    end
                    ST_RESTART: begin
                        // SCL HIGH
                        scl_oe <= 1'b0;
                        case (phase)
                            // SDA HIGH
                            2'd0: begin
                                sda_oe <= 1'b0;
                            end
                            // SDA HIGH -> LOW
                            // SCL HIGH
                            2'd1: begin
                                sda_oe <= 1'b1;
                            end
                            // Mentin SDA LOW
                            2'd2: begin
                                sda_oe <= 1'b1;
                            end
                            // Pregatim adresa READ
                            2'd3: begin
                                shift_reg <= {addr,1'b1};
                                bit_counter <= 3'd7;
                                state <= ST_ADDR_READ;
                            end
                        endcase
                    end
                    ST_ADDR_READ: begin
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // Punem bitul
                            2'd1: begin
                                scl_oe <= 1'b1;
                                sda_oe <= ~shift_reg[bit_counter];
                            end
                            // SCL HIGH
                            2'd2: begin
                                scl_oe <= 1'b0;
                            end
                            // Terminam bitul
                            2'd3: begin
                                scl_oe <= 1'b1;
                                if (bit_counter == 0) begin
                                    bit_counter <= 3'd7;
                                    state <= ST_ACK_ADDR_READ;
                                end
                                else begin
                                    bit_counter <= bit_counter - 1'b1;
                                end
                            end
                        endcase
                    end
                    ST_ACK_ADDR_READ: begin
                        // Eliberam SDA
                        sda_oe <= 1'b0;
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // SCL HIGH
                            2'd1: begin
                                scl_oe <= 1'b0;
                            end
                            // Citim ACK
                            2'd2: begin
                                scl_oe <= 1'b0;
                                if (sda == 1'b1) begin
                                    ack_error <= 1'b1;
                                end
                            end
                            // ACK terminat
                            2'd3: begin
                                scl_oe <= 1'b1;
                                read_shift <= 8'd0;
                                bit_counter <= 3'd7;
                                read_second_byte <= 1'b0;
                                state <= ST_READ_BYTE;
                            end
                        endcase
                    end
                    ST_READ_BYTE: begin
                        // Slave-ul conduce SDA
                        sda_oe <= 1'b0;
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // SCL LOW
                            2'd1: begin
                                scl_oe <= 1'b1;
                            end
                            // SCL HIGH
                            2'd2: begin
                                scl_oe <= 1'b0;
                                read_shift[bit_counter] <= sda;
                            end
                            // Terminam bitul
                            2'd3: begin
                                scl_oe <= 1'b1;
                                if (bit_counter == 0) begin
                                    // Byte-ul este complet
                                    // read_shift contine deja toti cei 8 biti
                                    if (!read_second_byte) begin
                                        // Primul byte = MSB
                                        rdata[15:8] <= read_shift;
                                        // Urmeaza al doilea byte
                                        read_second_byte <= 1'b1;
                                        bit_counter <= 3'd7;
                                        state <= ST_MASTER_ACK;
                                    end
                                    else begin
                                        // Al doilea byte = LSB
                                        rdata[7:0] <= read_shift;
                                        state <= ST_MASTER_NACK;
                                    end
                                end
                                else begin
                                    bit_counter <= bit_counter - 1'b1;
                                end
                            end
                        endcase
                    end
                    ST_MASTER_ACK: begin
                        // ACK = SDA LOW
                        sda_oe <= 1'b1;
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // SCL HIGH
                            2'd1: begin
                                scl_oe <= 1'b0;
                            end
                            // Mentinem ACK
                            2'd2: begin
                                scl_oe <= 1'b0;
                            end
                            // Terminam ACK
                            2'd3: begin
                                scl_oe <= 1'b1;
                                read_shift <= 8'd0;
                                bit_counter <= 3'd7;
                                state <= ST_READ_BYTE;
                            end
                        endcase
                    end
                    ST_MASTER_NACK: begin
                        // NACK = SDA HIGH
                        sda_oe <= 1'b0;
                        case (phase)
                            // SCL LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                            end
                            // SCL HIGH
                            2'd1: begin
                                scl_oe <= 1'b0;
                            end
                            // Mentinem NACK
                            2'd2: begin
                                scl_oe <= 1'b0;
                            end
                            // Terminam NACK
                            2'd3: begin
                                scl_oe <= 1'b1;
                                state <= ST_STOP;
                            end
                        endcase
                    end
                    ST_STOP: begin
                        case (phase)
                            // SCL LOW + SDA LOW
                            2'd0: begin
                                scl_oe <= 1'b1;
                                sda_oe <= 1'b1;
                            end
                            // SCL HIGH + SDA LOW
                            2'd1: begin
                                scl_oe <= 1'b0;
                                sda_oe <= 1'b1;
                            end
                            // SDA LOW -> HIGH
                            // SCL HIGH
                            2'd2: begin
                                scl_oe <= 1'b0;
                                sda_oe <= 1'b0;
                            end
                            // Magistrala libera
                            2'd3: begin
                                scl_oe <= 1'b0;
                                sda_oe <= 1'b0;
                                state <= ST_DONE;
                            end
                        endcase
                    end
                    ST_DONE: begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        data_out <= rdata;
                        state <= ST_IDLE;
                    end
                    default: begin
                        state <= ST_IDLE;
                        busy <= 1'b0;
                        sda_oe <= 1'b0;
                        scl_oe <= 1'b0;
                        phase <= 2'd0;
                    end
                endcase
                // AVANSARE PHASE
                if (phase == 2'd3) begin
                    phase <= 2'd0;
                end
                else begin
                    phase <= phase + 1'b1;
                end
            end
        end
    end
endmodule