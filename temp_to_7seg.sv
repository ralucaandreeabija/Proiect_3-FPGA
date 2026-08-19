`timescale 1ns / 1ps

module temp_to_7seg (
    input logic [15:0] temp,

    output logic [3:0] dig3,  // zeci
    output logic [3:0] dig2,  // unitati
    output logic [3:0] dig1,  // zecimi
    output logic [3:0] dig0,  // C
    output logic dp           // punct dupa unitati
);

    always_comb begin

        dig3 = (temp / 100) % 10;
        dig2 = (temp / 10)  % 10;
        dig1 = temp % 10;

        dig0 = 4'hC;

        // DP active-low
        dp = 1'b0;

    end

endmodule