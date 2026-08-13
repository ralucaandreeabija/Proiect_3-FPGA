`timescale 1ns / 1ps

module transmitter #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 9600,
    parameter integer DATA_BITS = 8
)(
    input logic clk,
    input logic reset,
    // Intrare din FIFO
    input logic [DATA_BITS-1:0] fifo_dout,
    input logic fifo_empty,
    output logic fifo_rd_en,

    output logic tx,
    output logic tx_done
);

localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
localparam integer COUNTER_WIDTH = $clog2(CLKS_PER_BIT);
logic [COUNTER_WIDTH-1:0] baud_counter;    

typedef enum logic [1:0] {
    IDLE,
    START,
    DATA,
    STOP
} state_t;

state_t state;

logic [DATA_BITS-1:0] data_reg;
logic [$clog2(DATA_BITS)-1:0] bit_index;
  
always @(posedge clk) begin
    if(reset) begin
        state <= IDLE;
        baud_counter <= 1'b0;
        bit_index <= 1'b0;
        data_reg <= 1'b0;
        fifo_rd_en <= 1'b0;
        tx <= 1'b1;
        tx_done <= 1'b0;
    end
    else begin
        tx_done <= 1'b0;
        fifo_rd_en <= 1'b0;
        case(state)
        IDLE: begin
            tx <= 1'b1;
            baud_counter <= 1'b0;
            bit_index <= 1'b0;
            fifo_rd_en <= 1'b0;
            if(!fifo_empty) begin
                data_reg <= fifo_dout;
                fifo_rd_en <= 1'b1; 
                state <= START;
            end
        end
        START: begin
            tx <= 1'b0;
            if(baud_counter == CLKS_PER_BIT-1) begin
                baud_counter <= 1'b0;
                state <= DATA;
            end
            else
                baud_counter <= baud_counter + 1'b1;
        end
        DATA: begin
            tx <= data_reg[bit_index];
            if(baud_counter == CLKS_PER_BIT-1) begin
                baud_counter <= 1'b0;
                if(bit_index == DATA_BITS-1) begin
                    bit_index <= 1'b0;
                    state <= STOP;
                end
                else
                    bit_index <= bit_index + 1'b1;
            end
            else
                baud_counter <= baud_counter + 1'b1;
        end
        STOP: begin
            tx <= 1'b1;
            if(baud_counter == CLKS_PER_BIT-1) begin
                baud_counter <= 1'b0;
                tx_done <= 1'b1;
                state <= IDLE;
            end
            else
                baud_counter <= baud_counter + 1'b1;
        end
        default: begin
            state <= IDLE;
        end
        endcase
    end
end
endmodule