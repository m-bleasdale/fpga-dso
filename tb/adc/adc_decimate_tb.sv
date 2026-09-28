`timescale 1ns/1ps

import dso_pkg::*;

module adc_decimate_tb;

	logic clk;
	logic rst_n;
	logic sample_valid;
	logic [ADC_SAMPLE_W-1:0] sample_data;
	logic [15:0] decimation_factor;
	logic dec_valid;
	logic [ADC_SAMPLE_W-1:0] dec_data;

	int pass_count;
	int fail_count;

	adc_decimate dut (
		.clk(clk),
		.rst_n(rst_n),
		.sample_valid(sample_valid),
		.sample_data(sample_data),
		.decimation_factor(decimation_factor),
		.dec_valid(dec_valid),
		.dec_data(dec_data)
	);

	always #10 clk = ~clk;

	task automatic check(
		input logic [31:0] actual,
		input logic [31:0] expected,
		input string label
	);
		if (actual === expected) begin
			$display("PASS | %-45s | actual = %0d", label, actual);
			pass_count++;
		end else begin
			$display("FAIL | %-45s | actual = %0d (expected %0d)", label, actual, expected);
			fail_count++;
		end
	endtask

	task step(input int cycles);
		repeat (cycles) begin
			@(posedge clk);
			#1;
		end
	endtask

	//send one sample (1 clk sample_valid pulse), then a gap like the real ADC
	//returns dec_valid and dec_data 1 clk after the sample
	task automatic send_sample(input logic [ADC_SAMPLE_W-1:0] value, output logic valid_out, output logic [ADC_SAMPLE_W-1:0] data_out);
		@(negedge clk);
		sample_valid = 1;
		sample_data = value;
		step(1);
		sample_valid = 0;
		valid_out = dec_valid;
		data_out = dec_data;
		step(3);
	endtask

	//send n samples with values start, start+1, ... and count/record kept ones
	int kept;
	logic [ADC_SAMPLE_W-1:0] kept_data [0:63];

	task automatic send_run(input int n, input logic [ADC_SAMPLE_W-1:0] start);
		logic v;
		logic [ADC_SAMPLE_W-1:0] d;
		kept = 0;
		for (int i = 0; i < n; i++) begin
			send_sample(start + i, v, d);
			if (v) begin
				kept_data[kept] = d;
				kept++;
			end
		end
	endtask

	logic v;
	logic [ADC_SAMPLE_W-1:0] d;

	initial begin
		clk = 0;
		rst_n = 0;
		sample_valid = 0;
		sample_data = '0;
		decimation_factor = 16'd1;
		pass_count = 0;
		fail_count = 0;

		//Reset: outputs zero
		step(3);
		check(dec_valid, 1'b0, "Reset: dec_valid low");
		check(dec_data, 8'h00, "Reset: dec_data zero");

		@(negedge clk);
		rst_n = 1;

		//No sample_valid: no dec_valid
		step(10);
		check(dec_valid, 1'b0, "No input samples: dec_valid stays low");

		//Factor 1: every sample kept with same data
		send_sample(8'h42, v, d);
		check(v, 1'b1, "Factor 1: sample kept");
		check(d, 8'h42, "Factor 1: data matches");
		send_run(10, 8'd0);
		check(kept, 10, "Factor 1: 10 of 10 samples kept");

		//dec_valid is single cycle
		send_sample(8'h10, v, d);
		check(dec_valid, 1'b0, "dec_valid is single cycle wide");

		//Factor 0 treated as 1
		decimation_factor = 16'd0;
		send_run(10, 8'd0);
		check(kept, 10, "Factor 0: 10 of 10 samples kept");

		//Factor 4: 1 in 4 kept, first of each group
		@(negedge clk);
		rst_n = 0;
		step(1);
		@(negedge clk);
		rst_n = 1;
		decimation_factor = 16'd4;
		send_run(20, 8'd100);
		check(kept, 5, "Factor 4: 5 of 20 samples kept");
		check(kept_data[0], 8'd100, "Factor 4: kept sample 0 is input 0");
		check(kept_data[1], 8'd104, "Factor 4: kept sample 1 is input 4");
		check(kept_data[4], 8'd116, "Factor 4: kept sample 4 is input 16");

		//Factor 3: 1 in 3 kept
		@(negedge clk);
		rst_n = 0;
		step(1);
		@(negedge clk);
		rst_n = 1;
		decimation_factor = 16'd3;
		send_run(30, 8'd0);
		check(kept, 10, "Factor 3: 10 of 30 samples kept");
		check(kept_data[9], 8'd27, "Factor 3: kept sample 9 is input 27");

		//dec_data holds between kept samples
		send_sample(8'hEE, v, d);
		send_sample(8'hDD, v, d);
		check(v, 1'b0, "Factor 3: dropped sample has no dec_valid");
		check(dec_data, 8'hEE, "dec_data holds last kept sample");

		//Lowering factor mid-count does not get stuck
		@(negedge clk);
		rst_n = 0;
		step(1);
		@(negedge clk);
		rst_n = 1;
		decimation_factor = 16'd50;
		send_run(20, 8'd0);
		decimation_factor = 16'd2;
		send_run(20, 8'd0);
		check(kept, 10, "Factor 50 -> 2 mid-count: 10 of 20 kept");

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

endmodule
