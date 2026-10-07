if {![info exists ::env(FPGA_PROJECT_ROOT)]} {
    error "FPGA_PROJECT_ROOT is not set"
}

set project_root [file normalize $::env(FPGA_PROJECT_ROOT)]

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file [file join $project_root rtl top tang_nano_20k_led.sv]
add_file [file join $project_root constraints tang_nano_20k_led.cst]
add_file [file join $project_root constraints tang_nano_20k_led.sdc]

set_option -synthesis_tool gowinsynthesis
set_option -top_module tang_nano_20k_led
set_option -verilog_std sysv2017
set_option -output_base_name tang_nano_20k_led

run all
