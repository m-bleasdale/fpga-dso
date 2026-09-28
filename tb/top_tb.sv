`timescale 1ns/1ps

import dso_pkg::*;

module top_tb;

	localparam real BIT_NS = 1_000_000_000.0 / UART_BAUD;

	//smaller buffer than real design (8192) so sim is quicker, 1 frame is 5 ms instead of 41 ms
	localparam int FRAME_LEN = 1024;
	localparam int PRETRIG = 256;
	localparam int RX_BUF = 1 << 17;

	logic clk;
	logic rst_n;
	logic uart_rx_in;
	logic uart_tx_out;
	wire [ADC_SAMPLE_W-1:0] adc_data;
	logic adc_convst_n;
	logic adc_cs_n;
	logic adc_rd_n;
	logic dac_cs_n;
	logic dac_sck;
	logic dac_mosi;
	logic dac_ldac_n;
	logic led_trig_n;
	logic led_dac_n;

	int pass_count;
	int fail_count;

	top #(
		.DEPTH(FRAME_LEN),
		.PRETRIG(PRETRIG)
	) dut (
		.clk(clk),
		.rst_n(rst_n),
		.uart_rx_in(uart_rx_in),
		.uart_tx_out(uart_tx_out),
		.adc_data(adc_data),
		.adc_convst_n(adc_convst_n),
		.adc_cs_n(adc_cs_n),
		.adc_rd_n(adc_rd_n),
		.dac_cs_n(dac_cs_n),
		.dac_sck(dac_sck),
		.dac_mosi(dac_mosi),
		.dac_ldac_n(dac_ldac_n),
		.led_trig_n(led_trig_n),
		.led_dac_n(led_dac_n)
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

	//check value is in range, for analog values
	task automatic check_range(
		input int actual,
		input int lo,
		input int hi,
		input string label
	);
		if (actual >= lo && actual <= hi) begin
			$display("PASS | %-50s | actual = %0d", label, actual);
			pass_count++;
		end else begin
			$display("FAIL | %-50s | actual = %0d (expected %0d -> %0d)", label, actual, lo, hi);
			fail_count++;
		end
	endtask

	task step(input int cycles);
		repeat (cycles) begin
			@(posedge clk);
			#1;
		end
	endtask

	//MCP4822 model: shift in 16 bits on SCK rising while CS low, output updates on LDAC low
	logic [15:0] dac_shift;
	logic [15:0] dac_word;
	logic [11:0] dac_value;
	int dac_updates;

	always @(posedge dac_sck)
		if (!dac_cs_n)
			dac_shift = {dac_shift[14:0], dac_mosi};

	always @(negedge dac_ldac_n) begin
		dac_word = dac_shift;
		dac_value = dac_shift[11:0];
		dac_updates++;
	end

	//AD7822 model, input is DAC output (analog loopback), 12 bit -> 8 bit
	//held on CONVST falling, ready 420 ns later, bus driven 10 ns after CS and RD low
	logic [ADC_SAMPLE_W-1:0] held;
	realtime conv_done_t;

	always @(negedge adc_convst_n) begin
		held = dac_value[11:4];
		conv_done_t = $realtime + 420;
	end

	assign #10 adc_data = (!adc_cs_n && !adc_rd_n) ? (($realtime >= conv_done_t) ? held : 'x) : 'z;

	//laptop UART receive, stores every byte from uart_tx_out
	logic [7:0] rx_bytes [0:RX_BUF-1];
	int rx_count;

	always begin
		@(negedge uart_tx_out);
		#(BIT_NS * 1.5);
		for (int i = 0; i < 8; i++) begin
			rx_bytes[rx_count % RX_BUF][i] = uart_tx_out;
			#(BIT_NS);
		end
		rx_count++;
	end

	//laptop UART send
	task automatic send_byte(input logic [7:0] data);
		uart_rx_in = 0;
		#(BIT_NS);
		for (int i = 0; i < 8; i++) begin
			uart_rx_in = data[i];
			#(BIT_NS);
		end
		uart_rx_in = 1;
		#(BIT_NS);
	endtask

	realtime cmd_t;

	task automatic send_cmd(input logic [7:0] cmd, input logic [31:0] data);
		send_byte(CMD_SYNC);
		send_byte(cmd);
		send_byte(data[7:0]);
		send_byte(data[15:8]);
		send_byte(data[23:16]);
		send_byte(data[31:24]);
		//force trigger does not change settings, frames after it still clean
		if (cmd != CMD_FORCE_TRIG)
			cmd_t = $realtime;
	endtask

	//track frames: capture starts when previous frame finishes sending
	realtime fill_start_t;
	int frame_start_pos;

	always @(negedge led_trig_n)
		frame_start_pos = rx_count;

	always @(posedge led_trig_n)
		fill_start_t = $realtime;

	//receive a frame whose capture started after the last command
	//(DDS -> DAC -> ADC latency is a few us, 50 us margin)
	//use_force sends a force trigger every 1 ms while waiting
	logic [7:0] frame [0:FRAME_LEN-1];
	logic [7:0] hdr [0:3];

	task automatic get_frame(input logic use_force);
		logic clean;
		int pos;
		int wait_cnt;
		clean = 0;
		while (!clean) begin
			wait_cnt = 0;
			while (led_trig_n) begin
				step(50);
				wait_cnt++;
				if (use_force && wait_cnt % 1000 == 0 && led_trig_n)
					send_cmd(CMD_FORCE_TRIG, 32'h0);
			end
			clean = (fill_start_t > cmd_t + 50_000);
			pos = frame_start_pos;
			wait (rx_count >= pos + 4 + FRAME_LEN);
			for (int i = 0; i < 4; i++)
				hdr[i] = rx_bytes[(pos + i) % RX_BUF];
			for (int i = 0; i < FRAME_LEN; i++)
				frame[i] = rx_bytes[(pos + 4 + i) % RX_BUF];
			wait (led_trig_n === 1'b1);
		end
	endtask

	//waveform measurements on frame
	int f_max;
	int f_min;
	int n_cross;
	int first_cross;
	int last_cross;
	logic cross_at_trig;

	//rising crossings of 128 with same hysteresis as trigger
	task automatic measure();
		logic armed;
		f_max = 0;
		f_min = 255;
		n_cross = 0;
		first_cross = -1;
		last_cross = -1;
		cross_at_trig = 0;
		armed = 0;
		for (int i = 0; i < FRAME_LEN; i++) begin
			if (frame[i] > f_max)
				f_max = frame[i];
			if (frame[i] < f_min)
				f_min = frame[i];
			if (!armed && frame[i] < 128 - TRIG_HYST)
				armed = 1;
			else if (armed && frame[i] >= 128) begin
				armed = 0;
				if (first_cross < 0)
					first_cross = i;
				last_cross = i;
				n_cross++;
				if (i == PRETRIG)
					cross_at_trig = 1;
			end
		end
	endtask

	//average period in samples between first and last crossing
	function automatic int period();
		if (n_cross < 2)
			return 0;
		return (last_cross - first_cross + (n_cross - 1) / 2) / (n_cross - 1);
	endfunction

	function automatic int flat_errors(input logic [7:0] value);
		int e;
		e = 0;
		for (int i = 0; i < FRAME_LEN; i++)
			if (frame[i] !== value)
				e++;
		return e;
	endfunction

	initial begin
		clk = 0;
		rst_n = 0;
		uart_rx_in = 1;
		dac_shift = '0;
		dac_word = '0;
		dac_value = 12'd2048;
		dac_updates = 0;
		conv_done_t = 0;
		rx_count = 0;
		cmd_t = 0;
		fill_start_t = 0;
		frame_start_pos = 0;
		pass_count = 0;
		fail_count = 0;

		//Reset: outputs idle
		step(3);
		check(uart_tx_out, 1'b1, "Reset: UART tx idles high");
		check(dac_cs_n, 1'b1, "Reset: DAC CS high");
		check(dac_ldac_n, 1'b1, "Reset: DAC LDAC high");
		check(adc_convst_n, 1'b1, "Reset: ADC CONVST high");
		check(adc_rd_n, 1'b1, "Reset: ADC RD high");
		check(led_trig_n, 1'b1, "Reset: trig LED off");

		@(negedge clk);
		rst_n = 1;
		fill_start_t = $realtime;

		//DAC updated at 200 kHz with correct MCP4822 control bits
		step(250 * 20);
		check_range(dac_updates, 19, 20, "DAC updates in 100 us (200 kHz)");
		check(dac_word[15:12], 4'b0111, "DAC control bits: ch A, buffered, 1x, on");

		//ADC sampling at 2 MHz
		begin
			int n;
			n = 0;
			repeat (1000) begin
				@(negedge adc_convst_n);
				n++;
			end
			check(n, 1000, "ADC conversions running");
		end

		//Frame 1: defaults (1 kHz, full gain, rising trigger at 128, no decimation)
		//1 kHz period (2000 samples) longer than frame so only trigger and max checked
		cmd_t = -1_000_000;
		get_frame(0);
		measure();
		check(hdr[0], 8'hAA, "Frame 1: header 0xAA");
		check(hdr[1], 8'h55, "Frame 1: header 0x55");
		check({hdr[3], hdr[2]}, FRAME_LEN, "Frame 1: LEN = 1024");
		check(frame[PRETRIG] >= 128, 1'b1, "Frame 1: trigger sample >= level");
		check(frame[PRETRIG - 1] < 128, 1'b1, "Frame 1: sample before trigger < level");
		check_range(f_max, 250, 255, "Frame 1: max (full gain)");
		check(cross_at_trig, 1'b1, "Frame 1: rising crossing at trigger index");

		//Frame 2: 10 kHz, full gain (commands over UART)
		send_cmd(CMD_SET_FREQ, 32'd214748365);
		get_frame(0);
		measure();
		check(hdr[0], 8'hAA, "Frame 2: header 0xAA");
		check(cross_at_trig, 1'b1, "Frame 2: rising crossing at trigger index");
		check_range(f_max, 250, 255, "Frame 2: max (full gain)");
		check_range(f_min, 0, 5, "Frame 2: min (full gain)");
		check_range(period(), 199, 201, "Frame 2: period samples (10 kHz @ 2 MHz)");

		//Frame 3: half gain, falling trigger
		send_cmd(CMD_SET_GAIN, 32'h800);
		send_cmd(CMD_SET_TRIG_EDGE, 32'd0);
		get_frame(0);
		measure();
		check(frame[PRETRIG] <= 128, 1'b1, "Frame 3: falling trigger sample <= level");
		check(frame[PRETRIG - 1] > 128, 1'b1, "Frame 3: sample before trigger > level");
		check_range(f_max, 188, 193, "Frame 3: max (half gain)");
		check_range(f_min, 62, 67, "Frame 3: min (half gain)");
		check_range(period(), 199, 201, "Frame 3: period samples (10 kHz @ 2 MHz)");

		//Frame 4: 5 kHz, decimation 4, rising trigger at 160
		send_cmd(CMD_SET_FREQ, 32'd107374182);
		send_cmd(CMD_SET_DECIMATION, 32'd4);
		send_cmd(CMD_SET_TRIG_EDGE, 32'd1);
		send_cmd(CMD_SET_TRIG_LEVEL, 32'd160);
		get_frame(0);
		measure();
		check(frame[PRETRIG] >= 160, 1'b1, "Frame 4: trigger sample >= 160");
		check(frame[PRETRIG - 1] < 160, 1'b1, "Frame 4: sample before trigger < 160");
		check_range(period(), 99, 101, "Frame 4: period samples (5 kHz, decimation 4)");

		//Frame 5: zero gain gives flat line, no crossings, force trigger from laptop
		send_cmd(CMD_SET_DECIMATION, 32'd1);
		send_cmd(CMD_SET_TRIG_LEVEL, 32'd128);
		send_cmd(CMD_SET_GAIN, 32'h0);
		get_frame(1);
		check(hdr[0], 8'hAA, "Frame 5: forced frame header 0xAA");
		check(flat_errors(8'd128), 0, "Frame 5: gain 0 flat at mid scale (mismatches)");

		$display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

		if (fail_count != 0)
			$fatal(1, "Testbench failed");
		else
			$finish;
	end

	initial begin
		#200_000_000;
		$display("FAIL | timeout");
		$fatal(1, "Testbench timed out");
	end

endmodule
