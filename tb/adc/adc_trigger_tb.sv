`timescale 1ns/1ps

import dso_pkg::*;

module adc_trigger_tb;

	logic clk;
	logic rst_n;
	logic sample_valid;
	logic [ADC_SAMPLE_W-1:0] sample_data;
	logic [ADC_SAMPLE_W-1:0] trig_level;
	logic trig_edge_rising;
	logic force_trig;
	logic trig_pulse;

	int pass_count;
	int fail_count;

	adc_trigger dut (
		.clk(clk),
		.rst_n(rst_n),
		.sample_valid(sample_valid),
		.sample_data(sample_data),
		.trig_level(trig_level),
		.trig_edge_rising(trig_edge_rising),
		.force_trig(force_trig),
		.trig_pulse(trig_pulse)
	);

	always #10 clk = ~clk;

	task automatic check(
		input logic [31:0] actual,
		input logic [31:0] expected,
		input string label
	);
		if (actual === expected) begin
			$display("PASS | %-50s | actual = %0d", label, actual);
			pass_count++;
		end else begin
			$display("FAIL | %-50s | actual = %0d (expected %0d)", label, actual, expected);
			fail_count++;
		end
	endtask

	task step(input int cycles);
		repeat (cycles) begin
			@(posedge clk);
			#1;
		end
	endtask

	//send one sample, returns trig_pulse 1 clk after (trigger latency)
	task automatic send_sample(input logic [ADC_SAMPLE_W-1:0] value, output logic trig_out);
		@(negedge clk);
		sample_valid = 1;
		sample_data = value;
		step(1);
		sample_valid = 0;
		trig_out = trig_pulse;
		step(2);
	endtask

	//send first n samples of vals, count triggers and record index of first one
	int trig_count;
	int trig_index;
	logic [ADC_SAMPLE_W-1:0] vals [0:15];

	task automatic send_list(input int n);
		logic t;
		trig_count = 0;
		trig_index = -1;
		for (int i = 0; i < n; i++) begin
			send_sample(vals[i], t);
			if (t) begin
				if (trig_index < 0)
					trig_index = i;
				trig_count++;
			end
		end
	endtask

	task reset_dut();
		@(negedge clk);
		rst_n = 0;
		step(1);
		@(negedge clk);
		rst_n = 1;
	endtask

	logic t;

	initial begin
		clk = 0;
		rst_n = 0;
		sample_valid = 0;
		sample_data = '0;
		trig_level = 8'd128;
		trig_edge_rising = 1;
		force_trig = 0;
		pass_count = 0;
		fail_count = 0;

		//Reset: trig_pulse low
		step(3);
		check(trig_pulse, 1'b0, "Reset: trig_pulse low");

		@(negedge clk);
		rst_n = 1;

		//First sample after reset above level does not trigger
		send_sample(8'd200, t);
		check(t, 1'b0, "First sample above level: no trigger");

		//Rising edge: fires on first sample >= level after going below level - hyst
		reset_dut();
		vals[0] = 8'd100; vals[1] = 8'd110; vals[2] = 8'd120; vals[3] = 8'd127;
		vals[4] = 8'd128; vals[5] = 8'd140; vals[6] = 8'd160; vals[7] = 8'd180;
		send_list(8);
		check(trig_count, 1, "Rising: one trigger on rising ramp");
		check(trig_index, 4, "Rising: fires on sample == level");

		//trig_pulse is single cycle
		reset_dut();
		send_sample(8'd50, t);
		send_sample(8'd200, t);
		check(t, 1'b1, "Rising: step through level triggers");
		step(1);
		check(trig_pulse, 1'b0, "trig_pulse is single cycle wide");

		//Rising: falling ramp does not trigger
		reset_dut();
		vals[0] = 8'd200; vals[1] = 8'd180; vals[2] = 8'd150; vals[3] = 8'd128;
		vals[4] = 8'd100; vals[5] = 8'd80; vals[6] = 8'd60; vals[7] = 8'd40;
		send_list(8);
		check(trig_count, 0, "Rising: falling ramp does not trigger");

		//Hysteresis: noise around level only triggers once
		reset_dut();
		vals[0] = 8'd100; vals[1] = 8'd129; vals[2] = 8'd126; vals[3] = 8'd130;
		vals[4] = 8'd125; vals[5] = 8'd131; vals[6] = 8'd127; vals[7] = 8'd128;
		send_list(8);
		check(trig_count, 1, "Hysteresis: noise near level triggers once");
		check(trig_index, 1, "Hysteresis: first crossing triggers");

		//Hysteresis: dip below level - hyst re-arms
		vals[0] = 8'd123; vals[1] = 8'd129;
		send_list(2);
		check(trig_count, 1, "Hysteresis: dip below level-4 re-arms trigger");

		//Hysteresis: dip not below level - hyst does not re-arm
		vals[0] = 8'd124; vals[1] = 8'd129;
		send_list(2);
		check(trig_count, 0, "Hysteresis: dip to level-4 does not re-arm");

		//Falling edge: fires on first sample <= level after going above level + hyst
		reset_dut();
		trig_edge_rising = 0;
		vals[0] = 8'd200; vals[1] = 8'd180; vals[2] = 8'd150; vals[3] = 8'd129;
		vals[4] = 8'd128; vals[5] = 8'd100; vals[6] = 8'd80; vals[7] = 8'd60;
		send_list(8);
		check(trig_count, 1, "Falling: one trigger on falling ramp");
		check(trig_index, 4, "Falling: fires on sample == level");

		//Falling: rising ramp does not trigger
		reset_dut();
		vals[0] = 8'd40; vals[1] = 8'd60; vals[2] = 8'd100; vals[3] = 8'd128;
		vals[4] = 8'd150; vals[5] = 8'd180; vals[6] = 8'd200; vals[7] = 8'd220;
		send_list(8);
		check(trig_count, 0, "Falling: rising ramp does not trigger");

		//Different trig level
		reset_dut();
		trig_edge_rising = 1;
		trig_level = 8'd50;
		vals[0] = 8'd10; vals[1] = 8'd30; vals[2] = 8'd49; vals[3] = 8'd51;
		vals[4] = 8'd90; vals[5] = 8'd200; vals[6] = 8'd10; vals[7] = 8'd60;
		send_list(8);
		check(trig_count, 2, "Level 50: two rising crossings");
		check(trig_index, 3, "Level 50: first crossing at sample 51");

		//Level near 0 does not underflow (level - hyst clamped to 0)
		reset_dut();
		trig_level = 8'd2;
		vals[0] = 8'd255; vals[1] = 8'd0; vals[2] = 8'd1; vals[3] = 8'd255;
		send_list(4);
		check(trig_count, 0, "Level 2 rising: no false trigger from wrap");

		//Changing edge re-arms
		reset_dut();
		trig_level = 8'd128;
		trig_edge_rising = 1;
		send_sample(8'd50, t);
		@(negedge clk);
		trig_edge_rising = 0;
		step(2);
		send_sample(8'd100, t);
		check(t, 1'b0, "Edge changed: old arm cleared");

		//Samples ignored while sample_valid low
		reset_dut();
		trig_edge_rising = 1;
		send_sample(8'd50, t);
		@(negedge clk);
		sample_data = 8'd250;
		step(5);
		check(trig_pulse, 1'b0, "sample_data ignored when sample_valid low");

		//Force trigger: fires on rising edge of force_trig
		reset_dut();
		@(negedge clk);
		force_trig = 1;
		step(1);
		check(trig_pulse, 1'b1, "Force trigger fires trig_pulse");

		//Force trigger held high only fires once
		step(1);
		check(trig_pulse, 1'b0, "Force trigger held high fires once");
		step(5);
		check(trig_pulse, 1'b0, "Force trigger held high stays quiet");
		@(negedge clk);
		force_trig = 0;
		step(2);

		//Force trigger fires again after release
		@(negedge clk);
		force_trig = 1;
		step(1);
		check(trig_pulse, 1'b1, "Force trigger fires again after release");
		@(negedge clk);
		force_trig = 0;

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

endmodule
