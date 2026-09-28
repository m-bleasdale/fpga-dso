/*

fires a single-cycle pulse when the sample stream crosses trig_level in selected direction

hysteresis (TRIG_HYST) stops noise near trig_level causing false triggers:
rising: signal must first drop below trig_level - TRIG_HYST, then fires when it reaches trig_level
falling: signal must first go above trig_level + TRIG_HYST, then fires when it drops to trig_level

manual force-trigger input (e.g. a UART command from laptop) also supported

1 clk latency from sample_valid to trig_pulse.

*/

import dso_pkg::*;

module adc_trigger (
	input logic clk,
	input logic rst_n,
	input logic sample_valid,
	input logic [ADC_SAMPLE_W-1:0] sample_data,
	input logic [ADC_SAMPLE_W-1:0] trig_level,
	input logic trig_edge_rising, 
	input logic force_trig, //force trigger input, from laptop
	output logic trig_pulse //single-cycle pulse on trigger event
);

	//set when signal has moved far enough past trig_level to allow the next trigger
	logic armed;
	logic force_trig_d;
	logic edge_rising_d;

	//1 extra bit so level +/- hysteresis cant wrap around
	logic [ADC_SAMPLE_W:0] level_lo;
	logic [ADC_SAMPLE_W:0] level_hi;

	assign level_lo = (trig_level < TRIG_HYST) ? '0 : trig_level - TRIG_HYST;
	assign level_hi = trig_level + TRIG_HYST;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			armed <= 1'b0;
			trig_pulse <= 1'b0;
			force_trig_d <= 1'b0;
			edge_rising_d <= 1'b1;
		end else begin
			trig_pulse <= 1'b0;
			force_trig_d <= force_trig;
			edge_rising_d <= trig_edge_rising;

			//edge changed, must re-arm
			if (trig_edge_rising != edge_rising_d) begin
				armed <= 1'b0;
			end else if (sample_valid) begin
				if (trig_edge_rising) begin
					if (!armed && sample_data < level_lo)
						armed <= 1'b1;
					else if (armed && sample_data >= trig_level) begin
						trig_pulse <= 1'b1;
						armed <= 1'b0;
					end
				end else begin
					if (!armed && sample_data > level_hi)
						armed <= 1'b1;
					else if (armed && sample_data <= trig_level) begin
						trig_pulse <= 1'b1;
						armed <= 1'b0;
					end
				end
			end

			//manual force trigger, rising-edge sensitive on the button/command
			if (force_trig && !force_trig_d)
				trig_pulse <= 1'b1;
		end
	end

endmodule
