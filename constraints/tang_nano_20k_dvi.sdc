create_clock -name clk_27mhz -period 37.037 -waveform {0 18.5185} [get_ports {clk_27mhz}]
create_clock -name pixel_clk -period 39.683 -waveform {0 19.8415} [get_pins {clock_generator/pixel_clock_divider/CLKOUT}]
