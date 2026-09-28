`timescale 1ns/1ps

import dso_pkg::*;

module uart_cmd_tb;

	//short timeout so tests are quick
	localparam int TIMEOUT = 100;

	logic clk;
	logic rst_n;
	logic [7:0] rx_data;
	logic rx_valid;

	logic [PHASE_W-1:0] phase_increment;
	logic [GAIN_W-1:0] gain;
	logic [ADC_SAMPLE_W-1:0] trig_level;
	logic trig_edge_rising;
	logic [15:0] decimation_factor;
	logic force_trig;

	int pass_count;
	int fail_count;

	uart_cmd #(
		.CMD_TIMEOUT(TIMEOUT)
	) dut (
		.clk(clk),
		.rst_n(rst_n),
		.rx_data(rx_data),
		.rx_valid(rx_valid),
		.phase_increment(phase_increment),
		.gain(gain),
		.trig_level(trig_level),
		.trig_edge_rising(trig_edge_rising),
		.decimation_factor(decimation_factor),
		.force_trig(force_trig)
	);

	always #10 clk = ~clk;

	task automatic check(
		input logic [31:0] actual,
		input logic [31:0] expected,
		input string label
	);
		if (actual === expected) begin
			$display("PASS | %-50s | actual = %0h", label, actual);
			pass_count++;
		end else begin
			$display("FAIL | %-50s | actual = %0h (expected %0h)", label, actual, expected);
			fail_count++;
		end
	endtask

	task step(input int cycles);
		repeat (cycles) begin
			@(posedge clk);
			#1;
		end
	endtask

	//count force_trig pulses
	int force_count;

	always @(posedge clk)
		if (force_trig)
			force_count++;

	//1 clk rx_valid pulse, then gap like a real UART byte
	task send_byte(input logic [7:0] b);
		@(negedge clk);
		rx_valid = 1;
		rx_data = b;
		@(negedge clk);
		rx_valid = 0;
		step(10);
	endtask

	//full command frame: sync, cmd, 4 data bytes little endian
	task send_cmd(input logic [7:0] cmd, input logic [31:0] data);
		send_byte(CMD_SYNC);
		send_byte(cmd);
		send_byte(data[7:0]);
		send_byte(data[15:8]);
		send_byte(data[23:16]);
		send_byte(data[31:24]);
	endtask

	initial begin
		clk = 0;
		rst_n = 0;
		rx_data = '0;
		rx_valid = 0;
		force_count = 0;
		pass_count = 0;
		fail_count = 0;

		//Reset: default settings
		step(3);
		check(phase_increment, DEFAULT_PHASE_INC, "Reset: phase_increment default (1 kHz)");
		check(gain, DEFAULT_GAIN, "Reset: gain default (full)");
		check(trig_level, DEFAULT_TRIG_LEVEL, "Reset: trig_level default (mid)");
		check(trig_edge_rising, 1'b1, "Reset: trig edge rising");
		check(decimation_factor, DEFAULT_DECIMATION, "Reset: decimation default");
		check(force_trig, 1'b0, "Reset: force_trig low");

		@(negedge clk);
		rst_n = 1;

		//Set frequency, 32 bits little endian
		send_cmd(CMD_SET_FREQ, 32'h1234_5678);
		check(phase_increment, 32'h1234_5678, "Set freq: phase_increment");

		//Set gain, low 12 bits only
		send_cmd(CMD_SET_GAIN, 32'hFFFF_F800);
		check(gain, 12'h800, "Set gain: low 12 bits");

		//Set trig level
		send_cmd(CMD_SET_TRIG_LEVEL, 32'h0000_0040);
		check(trig_level, 8'h40, "Set trig level");

		//Set trig edge falling then rising
		send_cmd(CMD_SET_TRIG_EDGE, 32'h0000_0000);
		check(trig_edge_rising, 1'b0, "Set trig edge falling");
		send_cmd(CMD_SET_TRIG_EDGE, 32'h0000_0001);
		check(trig_edge_rising, 1'b1, "Set trig edge rising");

		//Set decimation
		send_cmd(CMD_SET_DECIMATION, 32'h0000_03E8);
		check(decimation_factor, 16'd1000, "Set decimation 1000");

		//Other settings unchanged by previous commands
		check(phase_increment, 32'h1234_5678, "Other commands leave phase_increment");
		check(gain, 12'h800, "Other commands leave gain");

		//Force trigger: single pulse
		force_count = 0;
		send_cmd(CMD_FORCE_TRIG, 32'h0);
		check(force_count, 1, "Force trig: one pulse");
		check(force_trig, 1'b0, "Force trig: pulse is single cycle");

		//Setting only changes once whole frame received
		send_byte(CMD_SYNC);
		send_byte(CMD_SET_FREQ);
		send_byte(8'hEF);
		send_byte(8'hBE);
		send_byte(8'hAD);
		check(phase_increment, 32'h1234_5678, "Freq unchanged before last byte");
		send_byte(8'hDE);
		check(phase_increment, 32'hDEAD_BEEF, "Freq updated after last byte");

		//Bytes before sync ignored
		send_byte(8'h00);
		send_byte(8'h13);
		send_byte(8'hFF);
		send_cmd(CMD_SET_TRIG_LEVEL, 32'h0000_0099);
		check(trig_level, 8'h99, "Junk bytes before sync ignored");

		//Unknown command ignored, nothing changes
		force_count = 0;
		send_cmd(8'h7E, 32'h0000_0011);
		check(phase_increment, 32'hDEAD_BEEF, "Unknown cmd: phase_increment unchanged");
		check(gain, 12'h800, "Unknown cmd: gain unchanged");
		check(trig_level, 8'h99, "Unknown cmd: trig_level unchanged");
		check(decimation_factor, 16'd1000, "Unknown cmd: decimation unchanged");
		check(force_count, 0, "Unknown cmd: no force trig");

		//Decoder back in sync after unknown command
		send_cmd(CMD_SET_GAIN, 32'h0000_0123);
		check(gain, 12'h123, "Next command after unknown cmd works");

		//Frame stops half way, timeout resets decoder
		send_byte(CMD_SYNC);
		send_byte(CMD_SET_GAIN);
		send_byte(8'h55);
		step(TIMEOUT + 10);
		send_cmd(CMD_SET_TRIG_LEVEL, 32'h0000_0021);
		check(trig_level, 8'h21, "Timeout: next frame decoded after lost bytes");
		check(gain, 12'h123, "Timeout: half frame did not change gain");

		//Gaps shorter than timeout do not reset decoder
		send_byte(CMD_SYNC);
		step(TIMEOUT - 20);
		send_byte(CMD_SET_DECIMATION);
		step(TIMEOUT - 20);
		send_byte(8'h08);
		send_byte(8'h00);
		send_byte(8'h00);
		send_byte(8'h00);
		check(decimation_factor, 16'd8, "Slow bytes within timeout still decoded");

		//Reset mid frame goes back to defaults
		send_byte(CMD_SYNC);
		send_byte(CMD_SET_FREQ);
		@(negedge clk);
		rst_n = 0;
		step(1);
		check(phase_increment, DEFAULT_PHASE_INC, "Reset mid frame: phase_increment default");
		check(gain, DEFAULT_GAIN, "Reset mid frame: gain default");
		@(negedge clk);
		rst_n = 1;
		send_cmd(CMD_SET_GAIN, 32'h0000_0456);
		check(gain, 12'h456, "Command after reset works");

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

endmodule
