`timescale 1ns / 1ps

module edge_detector(
    input logic clk,
    input logic reset,
    input logic button,
    output logic pulse
);

logic button_prev;

always @(posedge clk) begin
    if (reset) begin
        button_prev <= 1'b0;
        pulse <= 1'b0;
    end
    else begin
        pulse <= button & ~button_prev;
        button_prev <= button;
    end
end

endmodule