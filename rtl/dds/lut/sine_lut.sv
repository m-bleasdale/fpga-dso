/*

phase selects where in one output cycle the signal is.

12 bit LUT addr --> 4096 entries for LUT
Top 12 bits of phase = LUT address 

phase gets truncated. LUT resolution is less fine than phase resolution

Each table addr --> one sine value (12 bits; signed)

sine values are centered at 0. -2048 --> +2047

*/

import dso_pkg::*;

module sine_lut (
    
    input logic clk,
    input logic rst_n,

    //phase output from phase accumulator
    input logic [PHASE_W-1:0] phase,

    //DDS output rate (not the same as clk)
    input logic sample_en_clk,

    //output wave sample in this cycle
    output logic signed [DDS_SAMPLE_W-1:0] sine_out

);

    //select top bits (truncated) from phase, gives coarse position in LUT
    wire [LUT_ADDR_W-1:0] LUT_addr = phase[PHASE_W-1 -: LUT_ADDR_W];


    //LUT for intel quartus / FPGA
    (* ram_init_file = "sine_lut.mif" *)
    logic signed [DDS_SAMPLE_W-1:0] LUT_mem [0:LUT_DEPTH-1];

    //LUT for iverilog
    initial begin
        $readmemh("./rtl/dds/lut/sine_lut.hex", LUT_mem);
    end


    always_ff @( posedge clk or negedge rst_n ) begin 
        if(!rst_n) begin
            sine_out <= 0;
        end 
        else if (sample_en_clk) begin 
            sine_out <= LUT_mem[LUT_addr];
        end
    end

    
endmodule