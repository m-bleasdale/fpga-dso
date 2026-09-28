/*

sets the oscilloscope timebase

keeps every Nth sample from the ADC (N = decimation_factor) and drops the rest.
sits before the trigger and capture buffer so the buffer holds a longer time window.

decimation_factor = 1 (or 0): every sample kept, 2 MHz, 4.096 ms buffer
decimation_factor = 1000: 2 kHz, 4.096 s buffer

1 clk latency.

*/

import dso_pkg::*;

module adc_decimate (
	input logic clk,
	input logic rst_n,

	input logic sample_valid,
	input logic [ADC_SAMPLE_W-1:0] sample_data,
	input logic [15:0] decimation_factor,

	output logic dec_valid, //single-cycle pulse per kept sample
	output logic [ADC_SAMPLE_W-1:0] dec_data
);

	logic [15:0] dec_cnt;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			dec_cnt <= '0;
			dec_valid <= 1'b0;
			dec_data <= '0;
		end else begin
			dec_valid <= 1'b0;

			if (sample_valid) begin
				//keep first sample of every N
				if (dec_cnt == 0) begin
					dec_valid <= 1'b1;
					dec_data <= sample_data;
				end

				//>= so lowering decimation_factor mid-count cant get stuck
				if (dec_cnt + 1 >= decimation_factor)
					dec_cnt <= '0;
				else
					dec_cnt <= dec_cnt + 1'b1;
			end
		end
	end

endmodule
