`timescale 1ns / 1ps

module debouncer #(
    parameter MAX_COUNT = 1_000_000
)(
    input  logic clk,
    input  logic debouncer_input,
    output logic debouncer_output = 0
);

    localparam COUNTER_BITS = $clog2(MAX_COUNT);

    logic [COUNTER_BITS-1:0] counter = 0;

    always_ff @(posedge clk) begin
        if (debouncer_input != debouncer_output) begin
            if (counter < (MAX_COUNT - 1)) begin
                counter <= counter + 1'b1;
            end
            else begin
                debouncer_output <= debouncer_input;
                counter <= 0;
            end
        end
        else begin
            counter <= 0;
        end
    end

endmodule