if {![info exists ::env(FPGA_PROJECT_ROOT)]} {
    error "FPGA_PROJECT_ROOT is not set"
}

set project_root [file normalize $::env(FPGA_PROJECT_ROOT)]

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file [file join $project_root vendor gowin SDRAM_controller_top_SIP.v]
add_file [file join $project_root rtl common sync_fifo.sv]
add_file [file join $project_root rtl common async_fifo.sv]
add_file [file join $project_root rtl memory framebuffer_colorbar_writer.sv]
add_file [file join $project_root rtl memory framebuffer_write_queue.sv]
add_file [file join $project_root rtl memory framebuffer_read_prefetch.sv]
add_file [file join $project_root rtl memory framebuffer_arbiter.sv]
add_file [file join $project_root rtl memory sdram_pixel_adapter.sv]
add_file [file join $project_root rtl video frame_presenter.sv]
add_file [file join $project_root rtl memory sdram_framebuffer_core.sv]
add_file [file join $project_root rtl video video_timing.sv]
add_file [file join $project_root rtl video tmds_encoder.sv]
add_file [file join $project_root rtl top gowin_dvi_clock.sv]
add_file [file join $project_root rtl top gowin_sdram_clock.sv]
add_file [file join $project_root rtl top gowin_tmds_serializer.sv]
add_file [file join $project_root rtl top tang_nano_20k_sdram_scanout.sv]
add_file [file join $project_root constraints tang_nano_20k_sdram_scanout.cst]
add_file [file join $project_root constraints tang_nano_20k_sdram_scanout.sdc]

set_option -synthesis_tool gowinsynthesis
set_option -top_module tang_nano_20k_sdram_scanout
set_option -verilog_std sysv2017
set_option -output_base_name tang_nano_20k_sdram_scanout

run all
