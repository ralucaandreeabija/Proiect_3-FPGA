`timescale 1ns / 1ps

module display_controller(
    input logic clk,
    
    // Counter (dreapta - 4 digi?i)
    input logic [3:0] cnt0,
    input logic [3:0] cnt1,
    input logic [3:0] cnt2,
    input logic [3:0] cnt3,
    
    // Temperatur? (stânga - 4 digi?i)
    input logic [3:0] tmp0,   // 'C'
    input logic [3:0] tmp1,   // zecimale
    input logic [3:0] tmp2,   // unit??i
    input logic [3:0] tmp3,   // zeci
    input logic dp,     // punct zecimal
    
    output logic [6:0] seg,
    output logic [7:0] an,
    output logic dp_out
);

    logic [16:0] refresh_counter = 0;
    logic [2:0] digit_select;
    logic [3:0] current_digit;
    logic current_dp;

    // Contor de refresh
    always @(posedge clk) begin
        refresh_counter <= refresh_counter + 1;
    end

    assign digit_select = refresh_counter[15:13];

    // Selectare digi? + anod + punct (tot pe clock)
    always @(posedge clk) begin
        current_dp <= 1'b0;

        case (digit_select)
            // DREAPTA (Counter) 
            3'd0: begin
                an <= 8'b11111110;
                current_digit <= cnt0;
            end
            3'd1: begin
                an <= 8'b11111101;
                current_digit <= cnt1;
            end
            3'd2: begin
                an <= 8'b11111011;
                current_digit <= cnt2;
            end
            3'd3: begin
                an <= 8'b11110111;
                current_digit <= cnt3;
            end

            // STÂNGA (Temperatur?)
            3'd4: begin
                an <= 8'b11101111;
                current_digit <= tmp0;      // C
            end
            3'd5: begin
                an <= 8'b11011111;
                current_digit <= tmp1;      // zecimale
            end
            3'd6: begin
                an <= 8'b10111111;
                current_digit <= tmp2;      // unit??i
                current_dp <= dp;           // punct
            end
            3'd7: begin
                an <= 8'b01111111;
                current_digit <= tmp3;      // zeci
            end

            default: begin
                an <= 8'b11111111;
                current_digit <= 4'd0;
            end
        endcase
    end

    assign dp_out = current_dp;

    transcodor_7seg decoder (
        .bcd(current_digit),
        .seg(seg)
    );

endmodule