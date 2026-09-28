`timescale 1ns/1ps

import dso_pkg::*;

module sample_ram_tb;

	localparam int ADDR_W = $clog2(CAPTURE_DEPTH);

	logic clk;
	logic we;
	logic [ADDR_W-1:0] waddr;
	logic [ADC_SAMPLE_W-1:0] wdata;
	logic [ADDR_W-1:0] raddr;
	logic [ADC_SAMPLE_W-1:0] rdata;

	int pass_count;
	int fail_count;
	int errors;

	sample_ram dut (
		.clk(clk),
		.we(we),
		.waddr(waddr),
		.wdata(wdata),
		.raddr(raddr),
		.rdata(rdata)
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

	task write_word(input logic [ADDR_W-1:0] addr, input logic [ADC_SAMPLE_W-1:0] data);
		@(negedge clk);
		we = 1;
		waddr = addr;
		wdata = data;
		step(1);
		we = 0;
	endtask

	//set raddr, rdata ready 1 clk later
	task read_word(input logic [ADDR_W-1:0] addr, output logic [ADC_SAMPLE_W-1:0] data);
		@(negedge clk);
		raddr = addr;
		step(1);
		data = rdata;
	endtask

	logic [ADC_SAMPLE_W-1:0] d;

	initial begin
		clk = 0;
		we = 0;
		waddr = '0;
		wdata = '0;
		raddr = '0;
		pass_count = 0;
		fail_count = 0;

		step(2);

		//Write then read back single address
		write_word(13'd5, 8'hA5);
		read_word(13'd5, d);
		check(d, 8'hA5, "Read back address 5");

		//First and last address
		write_word(13'd0, 8'h11);
		write_word(CAPTURE_DEPTH - 1, 8'hEE);
		read_word(13'd0, d);
		check(d, 8'h11, "Read back first address");
		read_word(CAPTURE_DEPTH - 1, d);
		check(d, 8'hEE, "Read back last address");

		//Read has 1 clk latency, rdata still old value before clk edge
		write_word(13'd100, 8'h3C);
		@(negedge clk);
		raddr = 13'd100;
		check(rdata, 8'hEE, "rdata unchanged before clk edge");
		step(1);
		check(rdata, 8'h3C, "rdata updated 1 clk after raddr");

		//we low: no write
		@(negedge clk);
		we = 0;
		waddr = 13'd100;
		wdata = 8'hFF;
		step(1);
		read_word(13'd100, d);
		check(d, 8'h3C, "we low does not write");

		//Overwrite existing value
		write_word(13'd100, 8'h77);
		read_word(13'd100, d);
		check(d, 8'h77, "Overwrite existing value");

		//Write and read different addresses in the same clk
		@(negedge clk);
		we = 1;
		waddr = 13'd200;
		wdata = 8'h99;
		raddr = 13'd5;
		step(1);
		we = 0;
		check(rdata, 8'hA5, "Read port independent of write port");
		read_word(13'd200, d);
		check(d, 8'h99, "Write in same clk as read landed");

		//Fill whole RAM with pattern then read all back
		for (int i = 0; i < CAPTURE_DEPTH; i++)
			write_word(i, (i * 7 + 3) & 8'hFF);
		errors = 0;
		for (int i = 0; i < CAPTURE_DEPTH; i++) begin
			read_word(i, d);
			if (d !== ((i * 7 + 3) & 8'hFF))
				errors++;
		end
		check(errors, 0, "Full 8192 pattern read back (mismatches)");

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

endmodule
