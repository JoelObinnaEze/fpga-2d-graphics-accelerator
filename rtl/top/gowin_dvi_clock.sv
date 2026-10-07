`timescale 1ns/1ps

module gowin_dvi_clock (
    input  wire clk_27mhz,
    output wire serial_clk,
    output wire pixel_clk,
    output wire locked
);
    wire unused_clkoutp;
    wire unused_clkoutd;
    wire unused_clkoutd3;
    wire ground = 1'b0;

    // 27 MHz * 14 / 3 = 126 MHz. OSER10 emits two bits per serial-clock
    // cycle; CLKDIV produces the 25.2 MHz pixel clock required by 640x480p60.
    rPLL video_pll (
        .CLKOUT(serial_clk),
        .LOCK(locked),
        .CLKOUTP(unused_clkoutp),
        .CLKOUTD(unused_clkoutd),
        .CLKOUTD3(unused_clkoutd3),
        .RESET(ground),
        .RESET_P(ground),
        .CLKIN(clk_27mhz),
        .CLKFB(ground),
        .FBDSEL(6'b0),
        .IDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0)
    );
    defparam video_pll.FCLKIN = "27";
    defparam video_pll.DYN_IDIV_SEL = "false";
    defparam video_pll.IDIV_SEL = 2;
    defparam video_pll.DYN_FBDIV_SEL = "false";
    defparam video_pll.FBDIV_SEL = 13;
    defparam video_pll.DYN_ODIV_SEL = "false";
    defparam video_pll.ODIV_SEL = 8;
    defparam video_pll.PSDA_SEL = "0000";
    defparam video_pll.DYN_DA_EN = "true";
    defparam video_pll.DUTYDA_SEL = "1000";
    defparam video_pll.CLKOUT_FT_DIR = 1'b1;
    defparam video_pll.CLKOUTP_FT_DIR = 1'b1;
    defparam video_pll.CLKOUT_DLY_STEP = 0;
    defparam video_pll.CLKOUTP_DLY_STEP = 0;
    defparam video_pll.CLKFB_SEL = "internal";
    defparam video_pll.CLKOUT_BYPASS = "false";
    defparam video_pll.CLKOUTP_BYPASS = "false";
    defparam video_pll.CLKOUTD_BYPASS = "false";
    defparam video_pll.DYN_SDIV_SEL = 2;
    defparam video_pll.CLKOUTD_SRC = "CLKOUT";
    defparam video_pll.CLKOUTD3_SRC = "CLKOUT";
    defparam video_pll.DEVICE = "GW2AR-18C";

    CLKDIV pixel_clock_divider (
        .RESETN(locked),
        .HCLKIN(serial_clk),
        .CLKOUT(pixel_clk),
        .CALIB(1'b1)
    );
    defparam pixel_clock_divider.DIV_MODE = "5";
    defparam pixel_clock_divider.GSREN = "false";
endmodule
