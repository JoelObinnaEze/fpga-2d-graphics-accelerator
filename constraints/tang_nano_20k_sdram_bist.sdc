create_clock -name clk_27mhz -period 37.037 [get_ports {clk_27mhz}]
create_clock -name controller_clk -period 6.173 -waveform {0 3.0865} [get_pins {clock_generator/sdram_pll/CLKOUT}]
create_clock -name sdram_clk -period 6.173 -waveform {4.244 7.3305} [get_pins {clock_generator/sdram_pll/CLKOUTP}]
