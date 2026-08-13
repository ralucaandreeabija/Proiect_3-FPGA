`timescale 1ns / 1ps

module binary_to_BCD (
    input logic clk,
    input logic [15:0] binary,
    output logic [3:0] bcd0,
    output logic [3:0] bcd1,
    output logic [3:0] bcd2,
    output logic [3:0] bcd3,
    output logic [3:0] bcd4
);

    integer i;
    logic [35:0] shift_reg;

    always @(posedge clk) begin
        shift_reg = 36'd0;
        shift_reg[15:0] = binary;

        for (i = 0; i < 16; i = i + 1) begin
            if (shift_reg[19:16] >= 5) shift_reg[19:16] = shift_reg[19:16] + 3;
            if (shift_reg[23:20] >= 5) shift_reg[23:20] = shift_reg[23:20] + 3;
            if (shift_reg[27:24] >= 5) shift_reg[27:24] = shift_reg[27:24] + 3;
            if (shift_reg[31:28] >= 5) shift_reg[31:28] = shift_reg[31:28] + 3;
            if (shift_reg[35:32] >= 5) shift_reg[35:32] = shift_reg[35:32] + 3;

            shift_reg = shift_reg << 1;
        end

        bcd0 <= shift_reg[19:16];
        bcd1 <= shift_reg[23:20];
        bcd2 <= shift_reg[27:24];
        bcd3 <= shift_reg[31:28];
        bcd4 <= shift_reg[35:32];
    end

endmodule