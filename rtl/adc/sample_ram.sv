/*

this file infers a block RAM (BRAM) in Quartus

interacts with capture_ctrl.sv

dual-port RAM (1 write port, 1 read port)

Depth is 8192 samples, each 8 bits wide (64 kbit, 8 M9K blocks on Cyclone IV)

RAM is used to hold samples as a buffer for the oscilloscope display.
The ADC sample clock is 2 MHz, so 8192 samples is 4.096 ms of data (no decimation).

read is registered, rdata valid 1 clk after raddr set

*/

import dso_pkg::*;

module sample_ram #(
	parameter int DEPTH = CAPTURE_DEPTH,
	parameter int ADDR_W = $clog2(DEPTH)
) (
	input logic clk,
	input logic we,
	input logic [ADDR_W-1:0] waddr,
	input logic [ADC_SAMPLE_W-1:0] wdata,
	input logic [ADDR_W-1:0] raddr,
	output logic [ADC_SAMPLE_W-1:0] rdata
);

	logic [ADC_SAMPLE_W-1:0] mem [0:DEPTH-1];

	always_ff @(posedge clk) begin
		if (we)
			mem[waddr] <= wdata;
		rdata <= mem[raddr]; //registered read -> 1 cycle latency
	end

endmodule
