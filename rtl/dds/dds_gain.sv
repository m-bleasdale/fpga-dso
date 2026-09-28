/*

take input signal (output from LUT) and multiply by gain.

gain --> unsigned 12-bit multiplier
signal_in --> signed 12-bit signal 

Signal-gain product is 25 bits signed.
Scaled down to 12-bits for 12-bit DAC.

xFFF --> 100% amplitude (1x)
x800 --> 50% amplitude (0.5x)
x000 --> 0% amplitude

Max gain is 1x. Supports fractional gain only.

*/

import dso_pkg::*;

module dds_gain (

    input logic clk,
    input logic rst_n,

    //input signal before gain applied (LUT output)
    input logic signed [DDS_SAMPLE_W-1:0] signal_in,

    input logic [GAIN_W-1:0] gain,

    //DDS output rate (not the same as clk)
    input logic sample_en_clk,

    output logic signed [DDS_SAMPLE_W-1:0] signal_out

);

    //25 bit product to support (12+1)x(12) bit operation
    logic signed [DDS_SAMPLE_W + GAIN_W : 0] product;

    //gain as signed 13-bit always positive (extended from unsigned 12-bit)
    //made signed so signal_out is signed
    always_comb begin
        product = $signed(signal_in) * $signed({1'b0, gain});
    end


    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            signal_out <= 0;
        end

        else if (sample_en_clk) begin

            //scale down to 12-bits for DAC
            signal_out <= product >>> GAIN_W;

        end

end


endmodule