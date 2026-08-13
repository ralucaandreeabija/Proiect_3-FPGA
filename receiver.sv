`timescale 1ns / 1ps

module receiver #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 9600,
    parameter integer DATA_BITS = 8
)(
    input logic clk,
    input logic reset,
    input logic rx,

    output logic [DATA_BITS-1:0] dataout,
    output logic data_valid
);

localparam integer CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
localparam integer HALF_BIT = CLKS_PER_BIT / 2;
localparam integer COUNTER_WIDTH = $clog2(CLKS_PER_BIT);

typedef enum logic [1:0] {
    IDLE,
    START,
    DATA,
    STOP
} state_t;

state_t state;

logic [COUNTER_WIDTH-1:0] baud_counter;
logic [2:0] bit_index;
logic [7:0] data_reg;

logic rx_sync1;
logic rx_sync2;

always @(posedge clk) begin
    rx_sync1 <= rx;
    rx_sync2 <= rx_sync1;
end

always @(posedge clk) begin
    if(reset) begin
        state <= IDLE;
        baud_counter <= 1'b0;
        bit_index <= 1'b0;
        data_reg <= 1'b0;
        dataout <= 1'b0;
        data_valid <= 1'b0;
    end
    else begin
        data_valid <= 1'b0;
        case(state)
        IDLE: begin
            baud_counter <= 1'b0;
            bit_index <= 1'b0;
            if(rx_sync2 == 1'b0)
                state <= START;
        end
        START: begin
            if(baud_counter == HALF_BIT-1) begin
                baud_counter <= 1'b0;
                if(rx_sync2 == 1'b0)
                    state <= DATA;
                else
                    state <= IDLE;
            end
            else
                baud_counter <= baud_counter + 1;
        end
        DATA: begin
            if(baud_counter == CLKS_PER_BIT-1) begin
                baud_counter <= 1'b0;
                data_reg[bit_index] <= rx_sync2;
                if(bit_index == DATA_BITS-1) begin
                    bit_index <= 1'b0;
                    state <= STOP;
                end
                else
                    bit_index <= bit_index + 1;
            end
            else
                baud_counter <= baud_counter + 1;
        end
        STOP: begin
            if(baud_counter == CLKS_PER_BIT-1) begin
                baud_counter <= 1'b0;
                if(rx_sync2 == 1'b1) begin
                    dataout <= data_reg;
                    data_valid <= 1'b1;
                end
                state <= IDLE;
            end
            else
                baud_counter <= baud_counter + 1;
        end
        default: begin
            state <= IDLE;
            baud_counter <= 1'b0;
            bit_index <= 1'b0;
            data_reg <= 1'b0;
            dataout <= 1'b0;
            data_valid <= 1'b0;
        end
        endcase
    end
end
endmodule