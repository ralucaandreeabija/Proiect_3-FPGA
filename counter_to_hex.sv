`timescale 1ns / 1ps

module counter_to_hex(
    input logic [15:0] counter,
    output logic [47:0] ascii_hex
);

    logic [7:0] hex0;
    logic [7:0] hex1;
    logic [7:0] hex2;
    logic [7:0] hex3;

    always @(*) begin
        // cifra 15:12
        if(counter[15:12] < 10)
            hex0 = counter[15:12] + 8'h30;
        else
            hex0 = counter[15:12] + 8'h37;
        // cifra 11:8
        if(counter[11:8] < 10)
            hex1 = counter[11:8] + 8'h30;
        else
            hex1 = counter[11:8] + 8'h37;
        // cifra 7:4
        if(counter[7:4] < 10)
            hex2 = counter[7:4] + 8'h30;
        else
            hex2 = counter[7:4] + 8'h37;
        // cifra 3:0
        if(counter[3:0] < 10)
            hex3 = counter[3:0] + 8'h30;
        else
            hex3 = counter[3:0] + 8'h37;
        ascii_hex = {"0","x",hex0,hex1,hex2,hex3};
    end
endmodule