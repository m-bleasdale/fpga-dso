/*

next phase = current phase + phase increment

higher phase_increment : higher frequency
lower phase_increment : lower frequency

Phase is 32-bits running from 0 to 2pi rad

*/

import dso_pkg::*;

module phase_accumulator (
    
    input logic clk,
    input logic rst_n,

    //DDS output rate (not the same as clk), phase only calculated if it is enabled
    input logic sample_en_clk,

    //used to set the frequency, added to accumulator next cycle
    input logic [PHASE_W-1:0] phase_increment,

    //phase value
    output logic [PHASE_W-1:0] phase

);

    always_ff @( posedge clk or negedge rst_n ) begin
        if(!rst_n) begin
            phase <= 0;
        end 

        else if (sample_en_clk) begin
            phase <= phase + phase_increment;
        end
        
    end

endmodule