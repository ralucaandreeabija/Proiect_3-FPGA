`timescale 1ns / 1ps

module command_interpreter(

    input logic clk,
    input logic reset,
    input logic [7:0] received_data,
    input logic rx_fifo_empty,
    output logic rx_fifo_rd_en,
    output logic inc_command,
    output logic dec_command,
    output logic reset_command,
    output logic status_command,
    output logic menu_command,
    output logic error_command,
    output logic [7:0] unknown_command,
    output logic temp_command
);

typedef enum logic [1:0] {
    IDLE,
    PROCESS,
    WAIT_RD // a?teapt? 1 ciclu dup? rd_en ca empty s? se actualizeze (FWFT)
} state_t;

state_t state;

always @(posedge clk) begin
    if(reset) begin
        state <= IDLE;
        rx_fifo_rd_en <= 1'b0;
        inc_command <= 1'b0;
        dec_command <= 1'b0;
        reset_command <= 1'b0;
        status_command <= 1'b0;
        menu_command <= 1'b0;
        error_command <= 1'b0;
        unknown_command <= 8'h00;
        temp_command <= 1'b0;
    end
    else begin
        rx_fifo_rd_en <= 1'b0;
        inc_command <= 1'b0;
        dec_command <= 1'b0;
        reset_command <= 1'b0;
        status_command <= 1'b0;
        menu_command <= 1'b0;
        error_command <= 1'b0;
        temp_command <= 1'b0;
        case(state)
        IDLE: begin
            if(!rx_fifo_empty)
                state <= PROCESS;
        end
        PROCESS: begin
            case(received_data)
                "I","i":
                    inc_command <= 1'b1;
                "D","d":
                    dec_command <= 1'b1;
                "R","r":
                    reset_command <= 1'b1;
                "S","s":
                    status_command <= 1'b1;
                "?":
                    menu_command <= 1'b1;
                "T","t":
                    temp_command <= 1'b1;
                default: begin
                    error_command <= 1'b1;
                    unknown_command <= received_data;
                end
            endcase
            rx_fifo_rd_en <= 1'b1; // scoatem octetul din FIFO
            state <= WAIT_RD;
        end
        WAIT_RD: begin
              state <= IDLE;
        end
        default:
            state <= IDLE;
        endcase
    end
end
endmodule
