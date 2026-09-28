/*

decodes command bytes from laptop (from uart_rx) and holds the settings for DDS and oscilloscope

command frame is 6 bytes:
byte0 = 0xA5 (CMD_SYNC)
byte1 = command
byte2 --> byte5 = data, 32 bits little endian (d0 is LSB)

commands (see dso_pkg):
0x01 set DDS phase_increment (frequency), 32 bits
0x02 set DDS gain, low 12 bits
0x03 set trigger level, low 8 bits
0x04 set trigger edge, bit 0 (1 = rising)
0x05 set decimation factor (timebase), low 16 bits
0x06 force trigger, data ignored

bytes before a sync byte are ignored. unknown commands are ignored.
if a frame stops half way (byte lost) the decoder resets after CMD_TIMEOUT clks with no new byte.
settings take effect once the whole frame is received.

*/

import dso_pkg::*;

module uart_cmd #(
	parameter int CMD_TIMEOUT = 50_000 //1 ms @ 50 MHz
) (

	input logic clk,
	input logic rst_n,

	//from uart_rx
	input logic [7:0] rx_data,
	input logic rx_valid,

	//DDS settings
	output logic [PHASE_W-1:0] phase_increment,
	output logic [GAIN_W-1:0] gain,

	//oscilloscope settings
	output logic [ADC_SAMPLE_W-1:0] trig_level,
	output logic trig_edge_rising,
	output logic [15:0] decimation_factor,
	output logic force_trig //single-cycle pulse

);

	typedef enum logic [1:0] {
		SYNC, //wait for 0xA5
		CMD, //command byte
		DATA //4 data bytes
	} state_t;

	state_t state;

	logic [7:0] cmd;
	logic [31:0] data_reg;
	logic [1:0] byte_count;
	logic [$clog2(CMD_TIMEOUT+1)-1:0] timeout_count;

	//data_reg with the last byte added (full 32 bit data)
	logic [31:0] data_full;
	assign data_full = {rx_data, data_reg[31:8]};

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state <= SYNC;
			cmd <= '0;
			data_reg <= '0;
			byte_count <= '0;
			timeout_count <= '0;

			phase_increment <= DEFAULT_PHASE_INC;
			gain <= DEFAULT_GAIN;
			trig_level <= DEFAULT_TRIG_LEVEL;
			trig_edge_rising <= 1'b1;
			decimation_factor <= DEFAULT_DECIMATION;
			force_trig <= 1'b0;
		end else begin

			force_trig <= 1'b0;

			//timeout, reset to SYNC if frame stops half way
			if (rx_valid || state == SYNC)
				timeout_count <= '0;
			else if (timeout_count == CMD_TIMEOUT - 1)
				state <= SYNC;
			else
				timeout_count <= timeout_count + 1'b1;

			if (rx_valid) begin
				case (state)

					SYNC: begin
						if (rx_data == CMD_SYNC)
							state <= CMD;
					end

					CMD: begin
						cmd <= rx_data;
						byte_count <= '0;
						state <= DATA;
					end

					DATA: begin
						//shift in from top, little endian
						data_reg <= data_full;

						if (byte_count == 2'd3) begin
							state <= SYNC;

							case (cmd)
								CMD_SET_FREQ: phase_increment <= data_full;
								CMD_SET_GAIN: gain <= data_full[GAIN_W-1:0];
								CMD_SET_TRIG_LEVEL: trig_level <= data_full[ADC_SAMPLE_W-1:0];
								CMD_SET_TRIG_EDGE: trig_edge_rising <= data_full[0];
								CMD_SET_DECIMATION: decimation_factor <= data_full[15:0];
								CMD_FORCE_TRIG: force_trig <= 1'b1;
								default: ; //unknown command
							endcase
						end else begin
							byte_count <= byte_count + 1'b1;
						end
					end

					default: state <= SYNC;

				endcase
			end

		end
	end

endmodule
