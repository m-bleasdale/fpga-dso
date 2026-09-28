/*

200 kHz sample clock. 12-bit sample/DAC value is set every 5,000 ns
5 MHz SPI clock. SPI_CLK
Each 200 ns clock transfers 1 bit of the 16-bit DAC output (12-bit data, 4-bit control)
16 SPI cycles = 3,200 ns (under 5,000 ns budget)

DAC interface:
15: channel (A:0, B:1)
14: buffer active (typically 1)
13: gain (1x:1 max: 2.048V, 2x:0 max: 4.096V)
12: shutdown (on:1, off:0)
11:0 data

DAC data is streamed 1 bit at a time, on each SPI clk (dac_sck) pulse.
Data streamed via dac_mosi (master out, slave in)
DAC value updated on each dac_ldac_n (load dac) LOW pulse.


*/

import dso_pkg::*;

module dac_if (

    input logic clk,
    input logic rst_n,

    input logic sample_clk_en,

    //DAC interface
    input logic [11:0] dac_data,

    //MCP4822 SPI interface
    output logic dac_cs_n, //chip select, LOW when FPGA is sending DAC
    output logic dac_sck, //SPI clock
    output logic dac_mosi, //master output, slave in. 16-bit stream, 1 bit at a time
    output logic dac_ldac_n, //load dac, LOW pulse updates output

    output logic busy

);

    typedef enum logic [1:0] {
        IDLE, //waiting for sample
        TRANSFER, //sending 16-bit DAC 
        LDAC_PULSE //pulse LDAC to update DAC output
    } state_t;

    state_t state;

    logic [15:0] transfer_reg; //12-bit DAC data + 4 control bits
    logic [4:0] bit_count;

    logic [$clog2(SPI_CLK_DIVIDER)-1:0] spi_clk_counter;

    logic [15:0] dac_command;

    logic channel = 0; //Channel = A
    logic buffer = 1;
    logic gain = 1; //1x: 0 V -> 2.048 V
    logic shutdown_n = 1; //on
    
    assign dac_command = {channel, buffer, gain, shutdown_n, dac_data};

    always_ff @( posedge clk or negedge rst_n ) begin : blockName
        
        if (!rst_n) begin
            state <= IDLE;

            transfer_reg <= 0;
            bit_count <= 0;

            spi_clk_counter <= 0;

            dac_cs_n <= 1;
            dac_sck <= 0;
            dac_mosi <= 0;
            dac_ldac_n <= 1;

            busy <= 0;

        end else begin
            
            case(state)

                //waiting for sample
                IDLE: begin
                    
                    //no chip select, no LDAC pulse, SPI clock off.
                    dac_cs_n <= 1;
                    dac_sck <= 0;
                    dac_ldac_n <= 1;
                    busy <= 0;
                    spi_clk_counter <= 0;

                    //watch for new sample and build MCP4822 command
                    if(sample_clk_en) begin

                        transfer_reg <= dac_command;

                        dac_mosi <= dac_command[15]; //set first bit to transfer as MSB

                        bit_count <= 5'd15;

                        dac_cs_n <= 0;
                        busy <= 1;
                        state <= TRANSFER;

                    end

                end

                //Sending 16 bit DAC sample
                TRANSFER: begin
                    
                    if(spi_clk_counter == SPI_CLK_DIVIDER-1) begin
                        
                        spi_clk_counter <= 0;

                        //pulse (1 cycle)
                        if(dac_sck == 1'b0) dac_sck <= 1'b1;
                        else begin 

                            dac_sck <= 1'b0;

                            //transfer finished
                            //reset and pulse LDAC
                            if(bit_count == 0) begin

                                dac_cs_n <= 1;
                                busy <= 0;
                                dac_ldac_n <= 0;
                                state <= LDAC_PULSE;

                            end else begin

                                bit_count <= bit_count - 1;

                                transfer_reg <= transfer_reg << 1;

                                dac_mosi <= transfer_reg[14];

                            end

                        end
                            
                    end else begin 

                        spi_clk_counter <= spi_clk_counter + 1;

                    end

                end

                //LDAC pulsed by TRANSFER when final bit sent
                //Reset LDAC
                LDAC_PULSE: begin
                    
                    dac_ldac_n <= 1;
                    state <= IDLE;

                end

            endcase

        end

    end

endmodule