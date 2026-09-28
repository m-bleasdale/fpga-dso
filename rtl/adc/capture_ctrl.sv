/*

RAM is used to hold samples as a buffer for the oscilloscope display.
this file sets up waveform buffer and sends it to the laptop over UART

States:
FILL - write incoming samples into the RAM (circular), ignore triggers until PRETRIG_DEPTH + 1 samples are stored
ARMED - keep writing samples, wait for trig_pulse
POST - trigger seen: keep writing until DEPTH - PRETRIG_DEPTH - 1 more samples have landed after the trigger sample
TX_START - pulse tx_start with next byte (header or sample)
TX_WAIT - wait for uart_tx to finish the byte (tx_done)

Buffer writing is paused while sending (single buffer).
Triggers during FILL are ignored (incl force trigger), otherwise the pre-trigger part would have old data from last frame.

trig_pulse comes 1 clk after the trigger sample was written (adc_trigger latency), so trigger sample is at wr_ptr - 1

UART frame sent to laptop:
byte0 = 0xAA (sync)
byte1 = 0x55 (sync)
byte2 = LEN[7:0] (number of samples, little endian)
byte3 = LEN[15:8]
byte4 --> byte(4+LEN-1) = raw 8-bit ADC samples, oldest first
trigger sample is at index PRETRIG_DEPTH of the samples

*/

import dso_pkg::*;

module capture_ctrl #(
	parameter int DEPTH = CAPTURE_DEPTH,
	parameter int ADDR_W = $clog2(DEPTH),
	parameter int PRETRIG = PRETRIG_DEPTH
) (
	input logic clk,
	input logic rst_n,

	//incoming sample stream (after decimation)
	input logic sample_valid,
	input logic [ADC_SAMPLE_W-1:0] sample_data,
	input logic trig_pulse,

	//RAM write port
	output logic ram_we,
	output logic [ADDR_W-1:0] ram_waddr,
	output logic [ADC_SAMPLE_W-1:0] ram_wdata,

	//RAM read port
	output logic [ADDR_W-1:0] ram_raddr,
	input logic [ADC_SAMPLE_W-1:0] ram_rdata,

	//uart_tx
	output logic tx_start,
	output logic [7:0] tx_data,
	input logic tx_done,

	output logic sending //high while frame being sent
);

	localparam logic [ADDR_W-1:0] PRETRIG_A = PRETRIG;
	localparam logic [ADDR_W:0] POST_DEPTH = DEPTH - PRETRIG - 1;
	localparam logic [15:0] PAYLOAD_LEN = DEPTH;
	localparam int HDR_BYTES = 4;
	localparam logic [ADDR_W+1:0] LAST_BYTE = HDR_BYTES + DEPTH - 1;

	typedef enum logic [2:0] {
		FILL, //write samples, triggers ignored until pre-trigger part full
		ARMED, //write samples, wait for trigger
		POST, //trigger seen, write samples after trigger
		TX_START, //start sending byte
		TX_WAIT //wait for byte to finish
	} state_t;

	state_t state;

	logic [ADDR_W-1:0] wr_ptr;
	logic [ADDR_W-1:0] rd_ptr;
	logic [ADDR_W:0] fill_cnt;
	logic [ADDR_W:0] post_cnt;
	logic [ADDR_W+1:0] byte_idx;

	//RAM has registered read, rd_ptr set well before byte is needed (1 UART byte = 250 clks)
	assign ram_raddr = rd_ptr;
	assign sending = (state == TX_START) || (state == TX_WAIT);

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state <= FILL;
			wr_ptr <= '0;
			rd_ptr <= '0;
			fill_cnt <= '0;
			post_cnt <= '0;
			byte_idx <= '0;
			ram_we <= 1'b0;
			ram_waddr <= '0;
			ram_wdata <= '0;
			tx_start <= 1'b0;
			tx_data <= '0;
		end else begin
			ram_we <= 1'b0;
			tx_start <= 1'b0;

			//write samples while capturing
			//POST stops at POST_DEPTH, next write would overwrite oldest sample in frame
			if (state == FILL || state == ARMED || (state == POST && post_cnt < POST_DEPTH)) begin
				if (sample_valid) begin
					ram_we <= 1'b1;
					ram_waddr <= wr_ptr;
					ram_wdata <= sample_data;
					wr_ptr <= wr_ptr + 1'b1;
				end
			end

			case (state)

				FILL: begin
					if (sample_valid) begin
						fill_cnt <= fill_cnt + 1'b1;
						//+1 for the trigger sample itself
						if (fill_cnt + 1'b1 > PRETRIG)
							state <= ARMED;
					end
				end

				ARMED: begin
					if (trig_pulse) begin
						//trigger sample at wr_ptr - 1, frame starts PRETRIG samples before it
						rd_ptr <= wr_ptr - 1'b1 - PRETRIG_A;
						//sample arriving in same clk as trigger is already after the trigger
						post_cnt <= sample_valid ? 1 : 0;
						state <= POST;
					end
				end

				POST: begin
					if (post_cnt >= POST_DEPTH) begin
						byte_idx <= '0;
						state <= TX_START;
					end else if (sample_valid) begin
						post_cnt <= post_cnt + 1'b1;
					end
				end

				//send header then samples
				TX_START: begin
					tx_start <= 1'b1;
					case (byte_idx)
						0: tx_data <= 8'hAA;
						1: tx_data <= 8'h55;
						2: tx_data <= PAYLOAD_LEN[7:0];
						3: tx_data <= PAYLOAD_LEN[15:8];
						default: begin
							tx_data <= ram_rdata;
							rd_ptr <= rd_ptr + 1'b1;
						end
					endcase
					state <= TX_WAIT;
				end

				TX_WAIT: begin
					if (tx_done) begin
						if (byte_idx == LAST_BYTE) begin
							fill_cnt <= '0;
							state <= FILL;
						end else begin
							byte_idx <= byte_idx + 1'b1;
							state <= TX_START;
						end
					end
				end

				default: state <= FILL;

			endcase
		end
	end

endmodule
