if {![info exists ::env(FPGA_PROJECT_ROOT)]} {
    error "FPGA_PROJECT_ROOT is not set"
}

set project_root [file normalize $::env(FPGA_PROJECT_ROOT)]

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file [file join $project_root rtl video video_timing.sv]
add_file [file join $project_root rtl video test_pattern.sv]
add_file [file join $project_root rtl video tmds_encoder.sv]
add_file [file join $project_root rtl top gowin_dvi_clock.sv]
add_file [file join $project_root rtl top gowin_tmds_serializer.sv]
add_file [file join $project_root rtl top tang_nano_20k_dvi.sv]
add_file [file join $project_root constraints tang_nano_20k_dvi.cst]
add_file [file join $project_root constraints tang_nano_20k_dvi.sdc]

set_option -synthesis_tool gowinsynthesis
set_option -top_module tang_nano_20k_dvi
set_option -verilog_std sysv2017
set_option -output_base_name tang_nano_20k_dvi

run all
