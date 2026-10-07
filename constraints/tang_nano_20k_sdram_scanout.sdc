create_clock -name clk_27mhz -period 37.037 -waveform {0 18.5185} [get_ports {clk_27mhz}]
create_clock -name pixel_clk -period 39.683 -waveform {0 19.8415} [get_pins {video_clock_generator/pixel_clock_divider/CLKOUT}]
create_clock -name controller_clk -period 6.173 -waveform {0 3.0865} [get_pins {memory_clock_generator/sdram_pll/CLKOUT}]
create_clock -name sdram_clk -period 6.173 -waveform {4.244 7.3305} [get_pins {memory_clock_generator/sdram_pll/CLKOUTP}]

set_clock_groups -asynchronous -group [get_clocks {pixel_clk}] -group [get_clocks {controller_clk sdram_clk}]
