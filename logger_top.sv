`timescale 1ns / 1ps

module logger_top(
    input logic clock,
    input logic btn_inc,
    input logic btn_dec,
    input logic btn_reset,
    input logic rx,
    output logic tx,
    output logic [15:0] leds,
    output logic [15:0] counter_out,
    // --- porturi noi pentru temperatur? ---
    output logic temp_command,
    input logic [39:0] temp_ascii
);

    logic inc_command, dec_command, reset_command, status_command, menu_command, error_command;
    logic [7:0] unknown_command;

    logic btn_inc_db, btn_dec_db, btn_reset_db;
    logic btn_inc_pulse, btn_dec_pulse, btn_reset_pulse;

    logic overflow, underflow;
    logic [15:0] counter;
    assign leds = counter;
    assign counter_out = counter;

    logic [7:0] received_data;
    logic data_valid;

    logic [7:0] rx_fifo_dout;
    logic rx_fifo_wr_en, rx_fifo_rd_en;
    logic rx_fifo_empty, rx_fifo_full;
    assign rx_fifo_wr_en = data_valid;

    logic [7:0] tx_fifo_din, tx_fifo_dout;
    logic tx_fifo_wr_en, tx_fifo_rd_en;
    logic tx_fifo_full, tx_fifo_empty;

    logic inc, dec;
    logic sys_reset;
    logic msg_reset;
    logic counter_reset;

    // Power-On Reset: primele 255 cicluri dup? configurare
    // Asigur? resetarea FIFO-urilor ?i a UART-ului la pornire, astfel încât mesajul Welcome s? poat? fi transmis corect.
    
    logic [7:0] pwr_cnt = 8'd0;
    logic pwr_active;

    always_ff @(posedge clock) begin
        if (pwr_cnt != 8'hFF)
            pwr_cnt <= pwr_cnt + 1'b1;
    end
    assign pwr_active = (pwr_cnt < 8'd32); // ~32 cicluri de reset la start

    // sys_reset  -> FIFO, UART, command_interpreter (pwr + buton)
    // msg_reset  -> doar pwr (ca Welcome s? se retrimit? la power-up, dar NU la fiecare ap?sare a butonului de reset)
    
    assign sys_reset = pwr_active | btn_reset_pulse;
    assign msg_reset = pwr_active;
    assign counter_reset = pwr_active | btn_reset_pulse | reset_command;

    assign inc = inc_command | btn_inc_pulse;
    assign dec = dec_command | btn_dec_pulse;

    debouncer #(.MAX_COUNT(1_000_000)) db_inc (
        .clk(clock),
        .debouncer_input(btn_inc),
        .debouncer_output(btn_inc_db)
    );

    debouncer #(.MAX_COUNT(1_000_000)) db_dec (
        .clk(clock),
        .debouncer_input(btn_dec),
        .debouncer_output(btn_dec_db)
    );

    debouncer #(.MAX_COUNT(1_000_000)) db_reset (
        .clk(clock),
        .debouncer_input(btn_reset),
        .debouncer_output(btn_reset_db)
    );

    edge_detector ed_inc (
        .clk(clock),
        .reset(pwr_active),
        .button(btn_inc_db),
        .pulse(btn_inc_pulse)
    );

    edge_detector ed_dec (
        .clk(clock),
        .reset(pwr_active),
        .button(btn_dec_db),
        .pulse(btn_dec_pulse)
    );

    edge_detector ed_reset (
        .clk(clock),
        .reset(pwr_active),
        .button(btn_reset_db),
        .pulse(btn_reset_pulse)
    );

    fifo_generator_0 rx_fifo (
        .clk(clock),
        .srst(sys_reset),
        .din(received_data),
        .wr_en(rx_fifo_wr_en),
        .rd_en(rx_fifo_rd_en),
        .dout(rx_fifo_dout),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty)
    );

    receiver #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(9600)
    ) uart_rx (
        .clk(clock),
        .reset(sys_reset),
        .rx(rx),
        .dataout(received_data),
        .data_valid(data_valid)
    );

    command_interpreter command_interpreter_inst (
        .clk(clock),
        .reset(sys_reset),
        .received_data(rx_fifo_dout),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_rd_en(rx_fifo_rd_en),
        .inc_command(inc_command),
        .dec_command(dec_command),
        .reset_command(reset_command),
        .status_command(status_command),
        .menu_command(menu_command),
        .error_command(error_command),
        .unknown_command(unknown_command),
        .temp_command(temp_command)
    );

    contor_binar counter_inst (
        .clk(clock),
        .inc(inc),
        .dec(dec),
        .reset(counter_reset),
        .leds(counter),
        .overflow(overflow),
        .underflow(underflow)
    );

    // msg_reset = doar pwr -> Welcome o dat? la pornire
    // Butonul RESET trimite [BTN] RESET, f?r? a re-trimite Welcome
    
    message message_inst (
        .clock(clock),
        .reset(msg_reset),
        .counter(counter),
        .inc_command(inc_command),
        .dec_command(dec_command),
        .reset_command(reset_command),
        .status_command(status_command),
        .menu_command(menu_command),
        .error_command(error_command),
        .unknown_command(unknown_command),
        .temp_command(temp_command),
        .temp_ascii(temp_ascii),
        .btn_inc_pulse(btn_inc_pulse),
        .btn_dec_pulse(btn_dec_pulse),
        .btn_reset_pulse(btn_reset_pulse),
        .overflow(overflow),
        .underflow(underflow),
        .tx_fifo_din(tx_fifo_din),
        .tx_fifo_wr_en(tx_fifo_wr_en),
        .tx_fifo_full(tx_fifo_full)
    );

    fifo_generator_0 tx_fifo (
        .clk(clock),
        .srst(sys_reset),
        .din(tx_fifo_din),
        .wr_en(tx_fifo_wr_en),
        .rd_en(tx_fifo_rd_en),
        .dout(tx_fifo_dout),
        .full(tx_fifo_full),
        .empty(tx_fifo_empty)
    );

    transmitter #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(9600)
    ) uart_tx (
        .clk(clock),
        .reset(sys_reset),
        .fifo_dout(tx_fifo_dout),
        .fifo_empty(tx_fifo_empty),
        .fifo_rd_en(tx_fifo_rd_en),
        .tx(tx),
        .tx_done()
    );
endmodule
