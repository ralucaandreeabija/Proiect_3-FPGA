`timescale 1ns / 1ps

module contor_binar(
    input  logic clk,
    input  logic inc,
    input  logic dec,
    input  logic reset,
    output logic [15:0] leds,
    output logic overflow,
    output logic underflow
);
    always @(posedge clk) begin
        overflow  <= 1'b0;
        underflow <= 1'b0;

        if (reset) begin
            leds <= 16'd0;
        end
        else if (inc) begin
            if (leds >= 16'd9999) begin
                leds <= 16'd0;
                overflow <= 1'b1;
            end else begin
                leds <= leds + 16'd1;
            end
        end
        else if (dec) begin
            if (leds == 16'd0) begin
                leds <= 16'd9999;
                underflow <= 1'b1;
            end else begin
                leds <= leds - 16'd1;
            end
        end
    end
endmodule
