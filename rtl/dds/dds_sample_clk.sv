/*
clk is 50 MHz
DAC SPI is 20 MHz with 4.5 us settle time
Max output is 1/4.5, approx 222 kHz
Setting at 200 kHz for safety (DDS_OUTPUT_RATE)

When sample_en_clk is high, DAC output is computed.

DAC output rate = 200 kHz (1/250 of 50 MHz clock)
divider = 250

*/


import dso_pkg::*;

module dds_sample_clk (
    
    input logic clk,
    input logic rst_n,

    output logic sample_en_clk

);

    //Count from 0 --> 249 (250 points) for 200 kHz signal
    logic [$clog2(DDS_CLK_DIVIDER)-1:0] counter;

    always_ff @( posedge clk or negedge rst_n ) begin 
        if(!rst_n) begin
            sample_en_clk <= 0;
            counter <= 0;
        end
        else if(counter == DDS_CLK_DIVIDER - 1) begin
            sample_en_clk <= 1;
            counter <= 0;
        end
        else begin
            sample_en_clk <= 0;
            counter <= counter + 1;
        end
    end
    
endmodule