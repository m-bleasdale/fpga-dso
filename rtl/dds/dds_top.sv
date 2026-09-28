/*
On each HIGH pulse of sample_en_clk:
1)phase accumulator adds phase increment
2)sine_lut finds sine value for that phase
3)dds_gain multiplies sine value by gain (0.0x -> 1.0x)

sample_clk_en is used to match output sample rate to DAC output rate

Pipeline latency is 3 sample clk cycles (pipeline registers at phase accumulator, sine_lut, dds_gain).
3 sample_clk pulse delay between phase accumulator and dds output.

Maximum gain is 1x. Supports fractional gain only.

*/

import dso_pkg::*;

module dds_top(
	input logic clk,
	input logic rst_n,

	//sets frequency of output trace
	input logic [PHASE_W-1:0] phase_increment,

	//gain multiplier (0.0x -> 1.0x)
	input logic [GAIN_W-1:0] gain,

	//signal generator output
	output logic signed [DDS_SAMPLE_W-1:0] dds_out

);

	logic sample_en_clk;

	dds_sample_clk sample_clk_inst (
		.clk(clk),
		.rst_n(rst_n),
		.sample_en_clk(sample_en_clk)
	);

	logic [PHASE_W-1:0] phase;

	phase_accumulator phase_accumulator_inst (
		.clk(clk),
		.rst_n(rst_n),
		.sample_en_clk(sample_en_clk),
		.phase_increment(phase_increment),
		.phase(phase)
	);

	logic signed [DDS_SAMPLE_W-1:0] sine_out;

	sine_lut sine_lut_inst (
		.clk(clk),
		.rst_n(rst_n),
		.phase(phase),
		.sample_en_clk(sample_en_clk),
		.sine_out(sine_out)
	);

	dds_gain dds_gain_inst (
		.clk(clk),
		.rst_n(rst_n),
		.signal_in(sine_out),
		.gain(gain),
		.sample_en_clk(sample_en_clk),
		.signal_out(dds_out)
	);

endmodule