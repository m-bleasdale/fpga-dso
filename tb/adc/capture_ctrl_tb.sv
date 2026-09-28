`timescale 1ns/1ps

import dso_pkg::*;

module capture_ctrl_tb;

	//small buffer so tests are quick, same logic as 8192
	localparam int DEPTH = 64;
	localparam int PRETRIG = 16;
	localparam int ADDR_W = $clog2(DEPTH);
	localparam int FRAME_BYTES = DEPTH + 4;

	logic clk;
	logic rst_n;
	logic sample_valid;
	logic [ADC_SAMPLE_W-1:0] sample_data;
	logic trig_pulse;

	logic ram_we;
	logic [ADDR_W-1:0] ram_waddr;
	logic [ADC_SAMPLE_W-1:0] ram_wdata;
	logic [ADDR_W-1:0] ram_raddr;
	logic [ADC_SAMPLE_W-1:0] ram_rdata;

	logic tx_start;
	logic [7:0] tx_data;
	logic tx_done;
	logic sending;

	int pass_count;
	int fail_count;

	capture_ctrl #(
		.DEPTH(DEPTH),
		.PRETRIG(PRETRIG)
	) dut (
		.clk(clk),
		.rst_n(rst_n),
		.sample_valid(sample_valid),
		.sample_data(sample_data),
		.trig_pulse(trig_pulse),
		.ram_we(ram_we),
		.ram_waddr(ram_waddr),
		.ram_wdata(ram_wdata),
		.ram_raddr(ram_raddr),
		.ram_rdata(ram_rdata),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_done(tx_done),
		.sending(sending)
	);

	sample_ram #(
		.DEPTH(DEPTH)
	) ram (
		.clk(clk),
		.we(ram_we),
		.waddr(ram_waddr),
		.wdata(ram_wdata),
		.raddr(ram_raddr),
		.rdata(ram_rdata)
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

	//sample source: 1 sample every 4 clks, sample_data = sample number
	//trig_pulse sent 1 clk after sample trig_at (like adc_trigger)
	//trig_same = 1 sends trig_pulse in same clk as the sample after trig_at instead (force trigger case)
	int sample_idx;
	int trig_at;
	logic trig_same;
	int gen_cnt;
	logic trig_next;

	always @(negedge clk) begin
		sample_valid = 0;
		trig_pulse = 0;
		if (trig_next) begin
			trig_pulse = 1;
			trig_next = 0;
		end
		gen_cnt++;
		if (rst_n && gen_cnt >= 4) begin
			gen_cnt = 0;
			sample_valid = 1;
			sample_data = sample_idx[ADC_SAMPLE_W-1:0];
			if (sample_idx == trig_at && !trig_same)
				trig_next = 1;
			if (sample_idx == trig_at + 1 && trig_same)
				trig_pulse = 1;
			sample_idx++;
		end
	end

	//uart_tx model: busy for 8 clks after tx_start then 1 clk tx_done pulse
	//records bytes sent, counts tx_start while busy (should never happen)
	logic [7:0] rx_bytes [0:FRAME_BYTES-1];
	int rx_count;
	int start_while_busy;
	int busy_cnt;

	always @(posedge clk) begin
		tx_done <= 0;
		if (busy_cnt > 0) begin
			busy_cnt <= busy_cnt - 1;
			if (busy_cnt == 1)
				tx_done <= 1;
		end
		if (tx_start) begin
			if (busy_cnt > 0)
				start_while_busy++;
			if (rx_count < FRAME_BYTES)
				rx_bytes[rx_count] = tx_data;
			rx_count++;
			busy_cnt <= 8;
		end
	end

	//check a received frame against expected samples around trigger sample
	task automatic check_frame(input int trig_sample, input string label);
		int errors;
		errors = 0;
		check(rx_count, FRAME_BYTES, {label, ": frame length (bytes)"});
		check(rx_bytes[0], 8'hAA, {label, ": header byte 0 = 0xAA"});
		check(rx_bytes[1], 8'h55, {label, ": header byte 1 = 0x55"});
		check({rx_bytes[3], rx_bytes[2]}, DEPTH, {label, ": LEN = DEPTH"});
		check(rx_bytes[4 + PRETRIG], trig_sample & 8'hFF, {label, ": trigger sample at index PRETRIG"});
		check(rx_bytes[4], (trig_sample - PRETRIG) & 8'hFF, {label, ": first sample PRETRIG before trigger"});
		check(rx_bytes[FRAME_BYTES-1], (trig_sample - PRETRIG + DEPTH - 1) & 8'hFF, {label, ": last sample"});
		for (int i = 0; i < DEPTH; i++)
			if (rx_bytes[4 + i] !== ((trig_sample - PRETRIG + i) & 8'hFF))
				errors++;
		check(errors, 0, {label, ": all samples in order (mismatches)"});
	endtask

	int rearm_idx;

	initial begin
		clk = 0;
		rst_n = 0;
		sample_valid = 0;
		sample_data = '0;
		trig_pulse = 0;
		trig_next = 0;
		trig_same = 0;
		trig_at = -100;
		sample_idx = 0;
		gen_cnt = 0;
		rx_count = 0;
		start_while_busy = 0;
		busy_cnt = 0;
		tx_done = 0;
		pass_count = 0;
		fail_count = 0;

		//Reset: no writes, no tx, not sending
		step(3);
		check(ram_we, 1'b0, "Reset: ram_we low");
		check(tx_start, 1'b0, "Reset: tx_start low");
		check(sending, 1'b0, "Reset: sending low");

		@(negedge clk);
		rst_n = 1;

		//Samples written to RAM in order
		wait (ram_we === 1'b1);
		#1;
		check(ram_waddr, 0, "First sample written to address 0");
		check(ram_wdata, 0, "First sample data");
		step(1);
		wait (ram_we === 1'b1);
		#1;
		check(ram_waddr, 1, "Second sample written to address 1");

		//Trigger during FILL is ignored (only 5 samples before it)
		trig_at = 5;
		step(4 * 40);
		check(sending, 1'b0, "Trigger during FILL ignored");
		check(rx_count, 0, "Trigger during FILL ignored: no bytes sent");

		//Trigger after FILL: frame sent with trigger sample at PRETRIG
		trig_at = 50;
		wait (sending === 1'b1);
		wait (sending === 1'b0);
		rearm_idx = sample_idx;
		check(start_while_busy, 0, "tx_start never sent while uart busy");
		check_frame(50, "Frame 1");

		//Back to FILL after frame, trigger on sample 15 of FILL ignored
		rx_count = 0;
		trig_at = rearm_idx + PRETRIG - 1;
		step(4 * (PRETRIG + DEPTH + 10));
		check(sending, 1'b0, "Trigger with PRETRIG-1 samples before it ignored");

		//Trigger with exactly PRETRIG samples before it is accepted
		@(negedge clk);
		rst_n = 0;
		step(1);
		@(negedge clk);
		rst_n = 1;
		sample_idx = 1000;
		trig_at = 1000 + PRETRIG;
		rx_count = 0;
		wait (sending === 1'b1);
		wait (sending === 1'b0);
		check_frame(1000 + PRETRIG, "Trigger right at end of FILL");

		//Many frames, RAM pointer wraps around
		rearm_idx = sample_idx;
		rx_count = 0;
		trig_at = rearm_idx + 300;
		wait (sending === 1'b1);
		wait (sending === 1'b0);
		check_frame(rearm_idx + 300, "Frame after pointer wrap");

		//Trigger in same clk as a new sample (force trigger case)
		rearm_idx = sample_idx;
		rx_count = 0;
		trig_same = 1;
		trig_at = rearm_idx + 40;
		wait (sending === 1'b1);
		wait (sending === 1'b0);
		check_frame(rearm_idx + 40, "Trigger in same clk as sample");
		trig_same = 0;

		//No RAM writes while frame is being sent
		trig_at = sample_idx + 30;
		wait (sending === 1'b1);
		begin
			int writes;
			writes = 0;
			while (sending) begin
				@(posedge clk);
				#1;
				if (ram_we && sending)
					writes++;
			end
			check(writes, 0, "No RAM writes while sending");
		end

		//tx_start is single cycle
		wait (tx_start === 1'b0);
		trig_at = sample_idx + 30;
		wait (tx_start === 1'b1);
		step(1);
		check(tx_start, 1'b0, "tx_start is single cycle wide");

		check(start_while_busy, 0, "tx_start never sent while uart busy (all frames)");

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

	initial begin
		#5_000_000;
		$display("FAIL | timeout");
		$fatal(1, "Testbench timed out");
	end

endmodule
