/*

Transmit via UART/USB to laptop

UART supports 8 bit data at 2 MHz baud rate.

tx_output is serial.

when tx_start is pulsed, tx_data is transfered 1 bit at a time @ UART baud rate (2 MHz)

*/

import dso_pkg::*;

module uart_tx (
    
    input logic clk,
    input logic rst_n,

    input logic tx_start,
    input logic [7:0] tx_data,
    
    output logic tx_serial_out, //UART serial stream to laptop (active LOW)
    output logic busy,
    output logic tx_done

);

    //number of clock cycles to transmit 1 bit @ 2 Mhz baud rate
    localparam int CLKS_PER_BIT = CLK_FREQ / UART_BAUD;

    typedef enum logic [1:0] {
        IDLE,
        START, //pulse to start transmission
        TRANSFER,
        STOP //pulse to stop transmission
    } state_t;

    state_t state; 

    logic [$clog2(CLKS_PER_BIT+1)-1:0] clk_count;
    logic [2:0] bit_index; //index of bit being transferred
    logic [7:0] transfer_reg;

    
    always_ff @( posedge clk or negedge rst_n ) begin

        if(!rst_n) begin
            state <= IDLE;

            tx_serial_out <= 1;
            busy <= 0;
            tx_done <= 0;

            clk_count <= 0;
            bit_index <= 0;
            transfer_reg <= 0;

        end else begin
            
            tx_done <= 0;

            case (state)

                IDLE: begin

                    tx_serial_out <= 1;

                    //tx_start pulsed
                    if(tx_start) begin
                        busy <= 1;
                        transfer_reg <= tx_data;
                        clk_count <= 0;
                        state <= START;
                    end

                end

                //transfer 8-bit tx_data 1 bit at a time @ 2 MHz
                START: begin

                    tx_serial_out <= 0;

                    //hold tx_serial_out low for 1 UART cycle before transfer
                    if(clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        bit_index <= 0;
                        state <= TRANSFER;
                    end else begin
                        clk_count <= clk_count + 1;
                    end

                end

                TRANSFER: begin
                    
                    tx_serial_out <= transfer_reg[0];

                    if(clk_count == CLKS_PER_BIT - 1) begin

                        clk_count <= 0;

                        transfer_reg <= {1'b0, transfer_reg[7:1]}; //right shift

                        //final bit reached: stop
                        //otherwise move onto next bit
                        if(bit_index == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end

                    end else begin
                        clk_count <= clk_count + 1;
                    end

                end

                STOP: begin

                    tx_serial_out <= 1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        busy <= 0;
                        tx_done <= 1;
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                    
                end

                default: state <= IDLE;

            endcase

        end 
        
    end



    
endmodule