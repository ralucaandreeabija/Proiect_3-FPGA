`timescale 1ns / 1ps

module temp_to_7seg (
    input  logic [15:0] temp,
    output logic [3:0] dig3,          // zeci
    output logic [3:0] dig2,          // unit??i
    output logic [3:0] dig1,          // zecimale
    output logic [3:0] dig0,          // 'C'
    output logic dp,            // decimal point (pe digit 2)
    output logic led_neg        // LED aprins la temperatur? negativ?
);

    logic [15:0] abs_temp;

    always @(*) begin
        if (temp[15] == 1'b1) begin
            led_neg  = 1'b1;
            abs_temp = -temp;
        end
        else begin
            led_neg  = 1'b0;
            abs_temp = temp;
        end

        // Extragem digi?ii
        dig3 = (abs_temp / 100) % 10;
        dig2 = (abs_temp / 10)  % 10;
        dig1 =  abs_temp % 10;
        dig0 = 4'hC;                   // litera C

        // Punctul zecimal pe digitul 2
        dp = 1'b1;
    end

endmodule