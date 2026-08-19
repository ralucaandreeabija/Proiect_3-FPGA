`timescale 1ns / 1ps

module temp_convert (
    input  logic [15:0] temp_raw,
    output logic [15:0] temp
);

    logic signed [12:0] temp_13bit;
    logic signed [23:0] temp_calc;

    always_comb begin

        // ADT7420 este implicit in modul 13-bit
        // Bits [15:3] contin temperatura
        // Bit 15 este bitul de semn
        // 1 LSB = 0.0625°C
        // Temperature = ADC_Code / 16

        temp_13bit = $signed(temp_raw[15:3]);

        // Temperatura * 10
        // temp_x10 = ADC_Code * 10 / 16

        temp_calc = (temp_13bit * 10) / 16;
        temp = temp_calc[15:0];
    end
endmodule