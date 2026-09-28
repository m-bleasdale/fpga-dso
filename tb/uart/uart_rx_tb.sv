`timescale 1ns/1ps

import dso_pkg::*;

module uart_rx_tb;

	localparam int CLKS_PER_BIT = CLK_FREQ / UART_BAUD;
	localparam real BIT_NS = 1_000_000_000.0 / UART_BAUD;

	logic clk;
	logic rst_n;
	logic rx_serial_in;
	logic [7:0] rx_data;
	logic rx_valid;

	//uart_tx looped back into a second uart_rx
	logic tx_start;
	logic [7:0] tx_data;
	logic tx_serial;
	logic tx_busy;
	logic tx_done;
	logic [7:0] loop_data;
	logic loop_valid;

	int pass_count;
	int fail_count;

	uart_rx dut (
		.clk(clk),
		.rst_n(rst_n),
		.rx_serial_in(rx_serial_in),
		.rx_data(rx_data),
		.rx_valid(rx_valid)
	);

	uart_tx tx_inst (
		.clk(clk),
		.rst_n(rst_n),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_serial_out(tx_serial),
		.busy(tx_busy),
		.tx_done(tx_done)
	);

	uart_rx loop_rx (
		.clk(clk),
		.rst_n(rst_n),
		.rx_serial_in(tx_serial),
		.rx_data(loop_data),
		.rx_valid(loop_valid)
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

	//count rx_valid pulses and keep last byte
	int rx_count;
	logic [7:0] last_byte;

	always @(posedge clk) begin
		if (rx_valid) begin
			rx_count++;
			last_byte = rx_data;
		end
	end

	//drive a UART frame onto rx_serial_in, bit_ns sets baud (lets baud error be tested)
	task automatic send_byte(input logic [7:0] data, input real bit_ns, input logic stop_bit);
		rx_serial_in = 0;
		#(bit_ns);
		for (int i = 0; i < 8; i++) begin
			rx_serial_in = data[i];
			#(bit_ns);
		end
		rx_serial_in = stop_bit;
		#(bit_ns);
		rx_serial_in = 1;
	endtask

	//send byte and check it arrives
	task automatic send_check(input logic [7:0] data, input real bit_ns, input string label);
		int count_before;
		count_before = rx_count;
		send_byte(data, bit_ns, 1'b1);
		step(5);
		check(rx_count - count_before, 1, {label, ": one byte received"});
		check(last_byte, data, {label, ": data matches"});
	endtask

	initial begin
		clk = 0;
		rst_n = 0;
		rx_serial_in = 1;
		tx_start = 0;
		tx_data = '0;
		rx_count = 0;
		pass_count = 0;
		fail_count = 0;

		//Reset: rx_valid low, rx_data zero
		step(3);
		check(rx_valid, 1'b0, "Reset: rx_valid low");
		check(rx_data, 8'h00, "Reset: rx_data zero");

		@(negedge clk);
		rst_n = 1;
		step(5);

		//Idle line: nothing received
		step(200);
		check(rx_count, 0, "Idle line: no bytes received");

		//Single bytes at exact baud rate
		send_check(8'h00, BIT_NS, "Byte 0x00");
		send_check(8'hFF, BIT_NS, "Byte 0xFF");
		send_check(8'hA5, BIT_NS, "Byte 0xA5");
		send_check(8'h3C, BIT_NS, "Byte 0x3C");
		send_check(8'h01, BIT_NS, "Byte 0x01 (LSB first)");
		send_check(8'h80, BIT_NS, "Byte 0x80 (LSB first)");

		//rx_valid is single cycle
		fork
			send_byte(8'h55, BIT_NS, 1'b1);
			begin
				wait (rx_valid === 1'b1);
				step(1);
				check(rx_valid, 1'b0, "rx_valid is single cycle wide");
			end
		join
		step(5);

		//Framing error: stop bit low, byte dropped
		begin
			int count_before;
			count_before = rx_count;
			send_byte(8'h77, BIT_NS, 1'b0);
			step(CLKS_PER_BIT * 2);
			check(rx_count - count_before, 0, "Framing error: byte dropped");
		end

		//Receiver recovers after framing error
		send_check(8'h42, BIT_NS, "Recovery after framing error");

		//Glitch shorter than half a bit is not a start bit
		begin
			int count_before;
			count_before = rx_count;
			rx_serial_in = 0;
			#(BIT_NS / 4);
			rx_serial_in = 1;
			step(CLKS_PER_BIT * 12);
			check(rx_count - count_before, 0, "Short glitch ignored");
		end

		//Baud rate error +/- 3%
		send_check(8'hC3, BIT_NS * 1.03, "Baud 3% slow");
		send_check(8'h3C, BIT_NS * 0.97, "Baud 3% fast");

		//Back to back bytes with no gap
		begin
			int count_before;
			count_before = rx_count;
			send_byte(8'h12, BIT_NS, 1'b1);
			send_byte(8'h34, BIT_NS, 1'b1);
			send_byte(8'h56, BIT_NS, 1'b1);
			step(5);
			check(rx_count - count_before, 3, "Back to back: 3 bytes received");
			check(last_byte, 8'h56, "Back to back: last byte matches");
		end

		//Loopback from uart_tx
		for (int i = 0; i < 4; i++) begin
			logic [7:0] b;
			b = 8'h5A + i * 8'h31;
			@(negedge clk);
			tx_data = b;
			tx_start = 1;
			@(negedge clk);
			tx_start = 0;
			wait (loop_valid === 1'b1);
			#1;
			check(loop_data, b, $sformatf("Loopback uart_tx -> uart_rx 0x%0h", b));
			wait (tx_busy === 1'b0);
		end

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

endmodule
