`timescale 1ns / 1ps

module top_final (
    input logic clk,
    input logic btn_reset,
    input logic btn_inc,
    input logic btn_dec,

    // UART
    input logic rx,
    output logic tx,

    // I2C - open drain / bidirectional
    inout wire sda,
    inout wire scl,

    // 7-segmente
    output logic [6:0] seg,
    output logic [7:0] an,
    output logic dp,

    // LED-uri
    output logic [15:0] leds
);

    // POWER-ON RESET
    logic [7:0] pwr_cnt = 8'd0;
    logic sys_reset;

    always @(posedge clk) begin
        if (pwr_cnt != 8'hFF)
            pwr_cnt <= pwr_cnt + 1'b1;
    end

    assign sys_reset = (pwr_cnt < 8'd32) | btn_reset;

    logic [15:0] binary_counter;

    // LOGGER / UART
    logic temp_command;
    logic [39:0] temp_ascii;

    logger_top u_logger (
        .clock(clk),
        .btn_inc(btn_inc),
        .btn_dec(btn_dec),
        .btn_reset(btn_reset),
        .rx(rx),
        .tx(tx),
        .leds(leds),
        .counter_out(binary_counter),
        .temp_command(temp_command),
        .temp_ascii(temp_ascii)
    );
    
    // Convertor Binary ? BCD
    logic [3:0] bcd0, bcd1, bcd2, bcd3;
    
    binary_to_BCD u_bin2bcd (
        .binary(binary_counter),
        .bcd0(bcd0),   // unit??i
        .bcd1(bcd1),   // zeci
        .bcd2(bcd2),   // sute
        .bcd3(bcd3),   // mii
        .bcd4()
    );
    
    // I2C MASTER
    logic i2c_enable;
    logic i2c_busy;
    logic i2c_done;
    logic i2c_ack_error;
    logic [15:0] i2c_data_out;
    logic [15:0] temp_raw;

    // ADT7420:
    // 7-bit I2C address = 0x4B
    i2c_master_v2 #(
        .CLK_FREQ(100_000_000),
        .I2C_FREQ(100_000)
    ) u_i2c (
        .clk(clk),
        .reset(sys_reset),
        .enable(i2c_enable),
        .addr(7'h4B),
        .reg_addr(8'h00),
        .data_in(16'h0000),
        .data_out(i2c_data_out),
        .rw(1'b1),
        .busy(i2c_busy),
        .done(i2c_done),
        .ack_error(i2c_ack_error),
        .sda(sda),
        .scl(scl)
    );

    // FSM PENTRU CITIRE PERIODICA
    localparam logic [1:0] I2C_IDLE  = 2'd0;
    localparam logic [1:0] I2C_START = 2'd1;
    localparam logic [1:0] I2C_WAIT  = 2'd2;
    
    logic [1:0] i2c_state;
    logic [25:0] refresh_cnt;
    
    // 20 biti sunt suficienti pentru 500_000
    logic [19:0] timeout_cnt;
    
    always @(posedge clk) begin
        if (sys_reset) begin
            i2c_state <= I2C_IDLE;
            i2c_enable <= 1'b0;
            refresh_cnt <= 26'd0;
            timeout_cnt <= 20'd0;
            temp_raw <= 16'd0;
        end
        else begin
            case (i2c_state)
                I2C_IDLE: begin
                    i2c_enable <= 1'b0;
                    timeout_cnt <= 20'd0;
                    if (refresh_cnt >= 26'd50_000_000) begin
                        refresh_cnt <= 26'd0;
                        i2c_state <= I2C_START;
                    end
                    else begin
                        refresh_cnt <= refresh_cnt + 1'b1;
                    end
                end
                I2C_START: begin
                    i2c_enable <= 1'b1;
                    timeout_cnt <= 20'd0;
                    if (i2c_busy) begin
                        i2c_enable <= 1'b0;
                        i2c_state <= I2C_WAIT;
                    end
                    else if (timeout_cnt >= 20'd500_000) begin
                        i2c_enable <= 1'b0;
                        timeout_cnt <= 20'd0;
                        i2c_state <= I2C_IDLE;
                    end
                    else begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                    end
                end
                I2C_WAIT: begin
                    i2c_enable <= 1'b0;
                    if (i2c_done) begin
                        temp_raw <= i2c_data_out;
                        timeout_cnt <= 20'd0;
                        i2c_state <= I2C_IDLE;
                    end
                    else if (timeout_cnt >= 20'd500_000) begin
                        timeout_cnt <= 20'd0;
                        i2c_state <= I2C_IDLE;
                    end
                    else begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                    end
                end
                default: begin
                    i2c_state <= I2C_IDLE;
                    i2c_enable <= 1'b0;
                    refresh_cnt <= 26'd0;
                    timeout_cnt <= 20'd0;
                end
            endcase
        end
    end
        // CONVERSIE TEMPERATUR?
        logic [15:0] temp_x10;
    
        temp_convert u_conv (
            .temp_raw(temp_raw),
            .temp(temp_x10)
        );
    
    // STRING ASCII PENTRU UART   
    always_comb begin
        temp_ascii[39:32] = ((temp_x10 / 100) % 10) + 8'h30;
        temp_ascii[31:24] = ((temp_x10 / 10) % 10) + 8'h30;
        temp_ascii[23:16] = 8'h2E;                 // '.'
        temp_ascii[15:8] = (temp_x10 % 10) + 8'h30;
        temp_ascii[7:0] = 8'h20;                 // space
    end
    
    // DISPLAY TEMPERATURA
    // temp_x10 = temperatura * 10
    // Exemplu:
    // temp_raw = 16'h0D80
    // temp_x10 = 270
    // Afisaj: 27.0 C
        logic [3:0] dig3;
        logic [3:0] dig2;
        logic [3:0] dig1;
        logic [3:0] dig0;
        logic dp_temp;
        
        temp_to_7seg u_temp7seg (
            .temp(temp_x10),
            .dig3(dig3),
            .dig2(dig2),
            .dig1(dig1),
            .dig0(dig0),
            .dp(dp_temp)
        );
        
    // DISPLAY CONTROLLER
    display_controller u_disp (
        .clk(clk),
        // Partea dreapta - contor
        .cnt0(bcd0),
        .cnt1(bcd1),
        .cnt2(bcd2),
        .cnt3(bcd3),
    
        // Partea stanga - temperatura
        // tmp0 = C
        // tmp1 = zecimi
        // tmp2 = unitati
        // tmp3 = zeci
        .tmp0(dig0),
        .tmp1(dig1),
        .tmp2(dig2),
        .tmp3(dig3),
        .dp(dp_temp),
        .seg(seg),
        .an(an),
        .dp_out(dp)
    );
endmodule