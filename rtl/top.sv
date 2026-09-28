/*

top level for DSOscilloscope (Cyclone IV EP4CE6E22C8N)

signal generator:
uart_rx --> uart_cmd --> dds_top --> dac_if --> MCP4822 DAC
laptop sets DDS frequency and gain over UART

oscilloscope:
AD7822 ADC --> adc_capture --> adc_decimate --> adc_trigger --> capture_ctrl <--> sample_ram
capture_ctrl --> uart_tx --> laptop
laptop sets trigger level, trigger edge, decimation and can force a trigger over UART

dds_out is signed (-2048 -> 2047), DAC wants unsigned (0 -> 4095) so MSB flipped (adds 2048).

DEPTH and PRETRIG default to dso_pkg values, only made smaller in top_tb so sim is quicker.

dac_if needs a pulse for each new sample. dds_top does not output its sample clk so a second dds_sample_clk is used.
both come out of reset together so they stay in step. DAC gets the dds_out from the previous sample clk (1 sample delay).

*/

import dso_pkg::*;

module top #(
	parameter int DEPTH = CAPTURE_DEPTH,
	parameter int PRETRIG = PRETRIG_DEPTH
) (
	input logic clk,
	input logic rst_n,

	//UART to/from laptop
	input logic uart_rx_in,
	output logic uart_tx_out,

	//AD7822 ADC
	input logic [ADC_SAMPLE_W-1:0] adc_data,
	output logic adc_convst_n,
	output logic adc_cs_n,
	output logic adc_rd_n,

	//MCP4822 DAC
	output logic dac_cs_n,
	output logic dac_sck,
	output logic dac_mosi,
	output logic dac_ldac_n,

	//status LEDs (active LOW on board)
	output logic led_trig_n, //on while frame is being sent
	output logic led_dac_n //on while DAC SPI transfer
);

	//UART commands
	logic [7:0] rx_data;
	logic rx_valid;

	logic [PHASE_W-1:0] phase_increment;
	logic [GAIN_W-1:0] gain;
	logic [ADC_SAMPLE_W-1:0] trig_level;
	logic trig_edge_rising;
	logic [15:0] decimation_factor;
	logic force_trig;

	uart_rx uart_rx_inst (
		.clk(clk),
		.rst_n(rst_n),
		.rx_serial_in(uart_rx_in),
		.rx_data(rx_data),
		.rx_valid(rx_valid)
	);

	uart_cmd uart_cmd_inst (
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

	//signal generator
	logic signed [DDS_SAMPLE_W-1:0] dds_out;
	logic dac_sample_en;
	logic dac_busy;

	dds_top dds_top_inst (
		.clk(clk),
		.rst_n(rst_n),
		.phase_increment(phase_increment),
		.gain(gain),
		.dds_out(dds_out)
	);

	dds_sample_clk dac_sample_clk_inst (
		.clk(clk),
		.rst_n(rst_n),
		.sample_en_clk(dac_sample_en)
	);

	dac_if dac_if_inst (
		.clk(clk),
		.rst_n(rst_n),
		.sample_clk_en(dac_sample_en),
		.dac_data({~dds_out[DDS_SAMPLE_W-1], dds_out[DDS_SAMPLE_W-2:0]}),
		.dac_cs_n(dac_cs_n),
		.dac_sck(dac_sck),
		.dac_mosi(dac_mosi),
		.dac_ldac_n(dac_ldac_n),
		.busy(dac_busy)
	);

	//oscilloscope
	logic [ADC_SAMPLE_W-1:0] sample_data;
	logic sample_valid;
	logic [ADC_SAMPLE_W-1:0] dec_data;
	logic dec_valid;
	logic trig_pulse;

	adc_capture adc_capture_inst (
		.clk(clk),
		.rst_n(rst_n),
		.adc_data(adc_data),
		.adc_convst_n(adc_convst_n),
		.adc_cs_n(adc_cs_n),
		.adc_rd_n(adc_rd_n),
		.sample_data(sample_data),
		.sample_valid(sample_valid)
	);

	adc_decimate adc_decimate_inst (
		.clk(clk),
		.rst_n(rst_n),
		.sample_valid(sample_valid),
		.sample_data(sample_data),
		.decimation_factor(decimation_factor),
		.dec_valid(dec_valid),
		.dec_data(dec_data)
	);

	adc_trigger adc_trigger_inst (
		.clk(clk),
		.rst_n(rst_n),
		.sample_valid(dec_valid),
		.sample_data(dec_data),
		.trig_level(trig_level),
		.trig_edge_rising(trig_edge_rising),
		.force_trig(force_trig),
		.trig_pulse(trig_pulse)
	);

	//capture buffer
	localparam int ADDR_W = $clog2(DEPTH);

	logic ram_we;
	logic [ADDR_W-1:0] ram_waddr;
	logic [ADC_SAMPLE_W-1:0] ram_wdata;
	logic [ADDR_W-1:0] ram_raddr;
	logic [ADC_SAMPLE_W-1:0] ram_rdata;

	logic tx_start;
	logic [7:0] tx_data;
	logic tx_busy;
	logic tx_done;
	logic sending;

	capture_ctrl #(
		.DEPTH(DEPTH),
		.PRETRIG(PRETRIG)
	) capture_ctrl_inst (
		.clk(clk),
		.rst_n(rst_n),
		.sample_valid(dec_valid),
		.sample_data(dec_data),
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
	) sample_ram_inst (
		.clk(clk),
		.we(ram_we),
		.waddr(ram_waddr),
		.wdata(ram_wdata),
		.raddr(ram_raddr),
		.rdata(ram_rdata)
	);

	uart_tx uart_tx_inst (
		.clk(clk),
		.rst_n(rst_n),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_serial_out(uart_tx_out),
		.busy(tx_busy),
		.tx_done(tx_done)
	);

	assign led_trig_n = ~sending;
	assign led_dac_n = ~dac_busy;

endmodule
