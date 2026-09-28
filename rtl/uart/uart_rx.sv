/*

Receive from laptop via UART/USB

UART supports 8 bit data at 2 MHz baud rate. 1 start bit, 8 data bits (LSB first), 1 stop bit.

rx_serial_in is serial (idles HIGH), comes from outside the FPGA so it is synchronised first (2 flip flops).

start bit (falling edge) detected, then each bit is sampled in the middle of its bit period.
rx_valid pulsed for 1 clk when a byte is received. byte dropped if stop bit is not HIGH (framing error).

*/

import dso_pkg::*;

module uart_rx (

	input logic clk,
	input logic rst_n,

	input logic rx_serial_in, //UART serial stream from laptop

	output logic [7:0] rx_data,
	output logic rx_valid //single-cycle pulse when rx_data is new

);

	//number of clock cycles per bit @ 2 MHz baud rate
	localparam int CLKS_PER_BIT = CLK_FREQ / UART_BAUD;

	typedef enum logic [1:0] {
		IDLE,
		START, //check start bit is still low half a bit later
		RECEIVE,
		STOP
	} state_t;

	state_t state;

	logic rx_meta;
	logic rx_sync;

	logic [$clog2(CLKS_PER_BIT+1)-1:0] clk_count;
	logic [2:0] bit_index; //index of bit being received
	logic [7:0] receive_reg;

	//2 flip flop synchroniser
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			rx_meta <= 1'b1;
			rx_sync <= 1'b1;
		end else begin
			rx_meta <= rx_serial_in;
			rx_sync <= rx_meta;
		end
	end

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state <= IDLE;
			rx_data <= '0;
			rx_valid <= 1'b0;
			clk_count <= '0;
			bit_index <= '0;
			receive_reg <= '0;
		end else begin

			rx_valid <= 1'b0;

			case (state)

				IDLE: begin
					clk_count <= '0;
					bit_index <= '0;
					if (!rx_sync)
						state <= START;
				end

				//middle of start bit, still low = real start bit, otherwise noise
				START: begin
					if (clk_count == CLKS_PER_BIT/2 - 1) begin
						clk_count <= '0;
						if (!rx_sync)
							state <= RECEIVE;
						else
							state <= IDLE;
					end else begin
						clk_count <= clk_count + 1'b1;
					end
				end

				//sample each bit in the middle, LSB first
				RECEIVE: begin
					if (clk_count == CLKS_PER_BIT - 1) begin
						clk_count <= '0;
						receive_reg <= {rx_sync, receive_reg[7:1]}; //right shift in
						if (bit_index == 3'd7)
							state <= STOP;
						else
							bit_index <= bit_index + 1'b1;
					end else begin
						clk_count <= clk_count + 1'b1;
					end
				end

				//middle of stop bit, only output byte if stop bit is high
				STOP: begin
					if (clk_count == CLKS_PER_BIT - 1) begin
						clk_count <= '0;
						if (rx_sync) begin
							rx_data <= receive_reg;
							rx_valid <= 1'b1;
						end
						state <= IDLE;
					end else begin
						clk_count <= clk_count + 1'b1;
					end
				end

				default: state <= IDLE;

			endcase

		end
	end

endmodule
