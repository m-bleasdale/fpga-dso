#50 MHz system clock, everything else is derived from it (clock enables, no second clock domain)
create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clock_uncertainty

#async inputs (synchronised in logic or sampled at fixed times), not timed
set_false_path -from [get_ports {rst_n uart_rx_in adc_data[*]}]
#outputs to slow external parts (ADC, DAC SPI, UART, LEDs), timing set by counters not by clk edge
set_false_path -to [get_ports {uart_tx_out adc_* dac_* led_*}]
