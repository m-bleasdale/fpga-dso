`timescale 1ns/1ps

import dso_pkg::*;

module adc_capture_tb;

	logic clk;
	logic rst_n;
	wire [ADC_SAMPLE_W-1:0] adc_data;
	logic adc_convst_n;
	logic adc_cs_n;
	logic adc_rd_n;
	logic [ADC_SAMPLE_W-1:0] sample_data;
	logic sample_valid;

	int pass_count;
	int fail_count;

	//AD7822 model
	//analog_in is the input voltage as an 8 bit code, held on CONVST falling edge
	//result ready 420 ns later, bus driven 10 ns after CS and RD low, X if read too early
	logic [ADC_SAMPLE_W-1:0] analog_in;
	logic [ADC_SAMPLE_W-1:0] held;
	realtime conv_done_t;
	realtime convst_fall_t;

	always @(negedge adc_convst_n) begin
		held = analog_in;
		convst_fall_t = $realtime;
		conv_done_t = $realtime + 420;
	end

	assign #10 adc_data = (!adc_cs_n && !adc_rd_n) ? (($realtime >= conv_done_t) ? held : 'x) : 'z;

	adc_capture dut (
		.clk(clk),
		.rst_n(rst_n),
		.adc_data(adc_data),
		.adc_convst_n(adc_convst_n),
		.adc_cs_n(adc_cs_n),
		.adc_rd_n(adc_rd_n),
		.sample_data(sample_data),
		.sample_valid(sample_valid)
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

	//step until sample_valid is high
	task next_sample();
		step(1);
		while (!sample_valid)
			step(1);
	endtask

	logic [ADC_SAMPLE_W-1:0] test_values [0:4];
	realtime t0;
	realtime t1;
	int count;

	initial begin
		clk = 0;
		rst_n = 0;
		analog_in = 8'h5A;
		conv_done_t = 0;
		pass_count = 0;
		fail_count = 0;
		test_values[0] = 8'h00;
		test_values[1] = 8'hFF;
		test_values[2] = 8'hA5;
		test_values[3] = 8'h3C;
		test_values[4] = 8'h80;

		//Reset: control pins inactive and sample_valid low
		step(3);
		check(adc_convst_n, 1'b1, "Reset: CONVST high");
		check(adc_cs_n, 1'b1, "Reset: CS high");
		check(adc_rd_n, 1'b1, "Reset: RD high");
		check(sample_valid, 1'b0, "Reset: sample_valid low");
		check(sample_data, 8'h00, "Reset: sample_data zero");

		//Data bus not driven when ADC is not being read
		check(adc_data === 8'hzz, 1'b1, "Data bus high-z when not read");

		//First conversion starts straight after reset release
		@(negedge clk);
		rst_n = 1;
		step(1);
		check(adc_convst_n, 1'b0, "CONVST low 1 clk after reset release");

		//First sample after reset is a real conversion
		next_sample();
		check(sample_data, 8'h5A, "First sample matches analog input");

		//CONVST pulse width is 40 ns (min 20 ns)
		@(negedge adc_convst_n);
		t0 = $realtime;
		@(posedge adc_convst_n);
		check(int'($realtime - t0), 40, "CONVST low pulse is 40 ns");

		//RD only goes low after the 420 ns conversion time
		@(negedge adc_rd_n);
		check(int'($realtime - t0), 420, "RD low 420 ns after CONVST falls");
		check(adc_cs_n, 1'b0, "CS low with RD");

		//RD low for 40 ns
		t1 = $realtime;
		@(posedge adc_rd_n);
		check(int'($realtime - t1), 40, "RD low pulse is 40 ns");
		check(adc_cs_n, 1'b1, "CS high with RD");

		//Sample period is 500 ns (2 MHz)
		@(negedge adc_convst_n);
		check(int'($realtime - t0), 500, "CONVST period is 500 ns (2 MHz)");

		//Quiet time between RD high and next CONVST
		check(int'($realtime - t1 - 40), 40, "40 ns between RD high and next CONVST");

		//sample_data matches analog input for different values
		foreach (test_values[i]) begin
			next_sample();
			analog_in = test_values[i];
			next_sample();
			check(sample_data, test_values[i], $sformatf("sample_data matches input 0x%0h", test_values[i]));
		end

		//sample_valid is a single clk pulse
		next_sample();
		step(1);
		check(sample_valid, 1'b0, "sample_valid is single cycle wide");

		//sample_data holds between samples
		analog_in = 8'h11;
		step(10);
		check(sample_data, 8'h80, "sample_data holds between samples");

		//20 samples every 10 us
		count = 0;
		repeat (500) begin
			step(1);
			if (sample_valid)
				count++;
		end
		check(count, 20, "20 samples in 10 us");

		//Reset mid conversion puts control pins back high
		step(7);
		@(negedge clk);
		rst_n = 0;
		#1;
		check(adc_convst_n, 1'b1, "Reset mid-sample: CONVST high");
		check(adc_rd_n, 1'b1, "Reset mid-sample: RD high");
		check(sample_valid, 1'b0, "Reset mid-sample: sample_valid low");

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

endmodule
