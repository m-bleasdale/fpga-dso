/*

ADC is AD7822BNZ
8-bit, 2 MHz, parallel output

CONVST low pulse starts a conversion (on falling edge)
conversion takes 420 ns max, then data read by pulling CS and RD low
data bus (adc_data) only driven while CS and RD are low

Sample rate: 2 MHz --> 25 clk cycles per sample (50 MHz clk)
all ADC control signals come from clk so no CDC or second clock domain needed.

One sample period (clk cycles):
0 -> 1: CONVST low (40 ns, min is 20 ns)
2 -> 20: converting
21 -> 22: CS and RD low (conversion done at 420 ns)
23: data latched, CS and RD high, sample_valid pulsed
24: quiet time before next conversion

adc_eoc_n not needed as fixed timing covers max conversion time.
Synchronising EOC takes 2 extra clks which would not fit in 25 clks.

*/

import dso_pkg::*;

module adc_capture (
	input logic clk,
	input logic rst_n,

	input logic [ADC_SAMPLE_W-1:0] adc_data, //parallel ADC output bus

	//AD7822 control pins (active LOW)
	output logic adc_convst_n, //start conversion
	output logic adc_cs_n, //chip select
	output logic adc_rd_n, //read, ADC drives data bus when LOW

	output logic [ADC_SAMPLE_W-1:0] sample_data, //one sample, valid when sample_valid=1
	output logic sample_valid //single-cycle pulse per new sample
);

	//25 clk cycles / sample
	localparam int SAMPLE_CLKS = SYS_CLK_HZ / ADC_SAMPLE_HZ;

	localparam int CONVST_END = 2;
	localparam int READ_START = 21; //420 ns @ 50 MHz
	localparam int READ_END = 23;

	logic [$clog2(SAMPLE_CLKS)-1:0] cycle_cnt;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cycle_cnt <= SAMPLE_CLKS - 1; //end of cycle so 1st clk after rst starts a conversion
			adc_convst_n <= 1'b1;
			adc_cs_n <= 1'b1;
			adc_rd_n <= 1'b1;
			sample_data <= '0;
			sample_valid <= 1'b0;
		end else begin
			sample_valid <= 1'b0;

			if (cycle_cnt == SAMPLE_CLKS - 1)
				cycle_cnt <= '0;
			else
				cycle_cnt <= cycle_cnt + 1'b1;

			//start conversion
			if (cycle_cnt == SAMPLE_CLKS - 1)
				adc_convst_n <= 1'b0;
			else if (cycle_cnt == CONVST_END - 1)
				adc_convst_n <= 1'b1;

			//read data bus
			if (cycle_cnt == READ_START - 1) begin
				adc_cs_n <= 1'b0;
				adc_rd_n <= 1'b0;
			end else if (cycle_cnt == READ_END - 1) begin
				adc_cs_n <= 1'b1;
				adc_rd_n <= 1'b1;
				sample_data <= adc_data;
				sample_valid <= 1'b1;
			end
		end
	end

endmodule
