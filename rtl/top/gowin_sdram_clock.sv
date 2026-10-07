`timescale 1ns/1ps

module gowin_sdram_clock (
    input  wire clk_27mhz,
    output wire controller_clk,
    output wire sdram_clk,
    output wire locked
);
    wire unused_clkoutd;
    wire unused_clkoutd3;
    wire ground = 1'b0;
    wire power = 1'b1;

    // 27 MHz * 6 = 162 MHz. Hardware characterization selected phase 11
    // (11/16 cycle, or 247.5 degrees) for the embedded SDRAM clock.
    rPLL sdram_pll (
        .CLKOUT(controller_clk),
        .LOCK(locked),
        .CLKOUTP(sdram_clk),
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
        .FDLY({4{power}})
    );
    defparam sdram_pll.FCLKIN = "27";
    defparam sdram_pll.DYN_IDIV_SEL = "false";
    defparam sdram_pll.IDIV_SEL = 0;
    defparam sdram_pll.DYN_FBDIV_SEL = "false";
    defparam sdram_pll.FBDIV_SEL = 5;
    defparam sdram_pll.DYN_ODIV_SEL = "false";
    defparam sdram_pll.ODIV_SEL = 4;
    defparam sdram_pll.PSDA_SEL = "1011";
    defparam sdram_pll.DYN_DA_EN = "false";
    defparam sdram_pll.DUTYDA_SEL = "1000";
    defparam sdram_pll.CLKOUT_FT_DIR = 1'b1;
    defparam sdram_pll.CLKOUTP_FT_DIR = 1'b1;
    defparam sdram_pll.CLKOUT_DLY_STEP = 0;
    defparam sdram_pll.CLKOUTP_DLY_STEP = 0;
    defparam sdram_pll.CLKFB_SEL = "internal";
    defparam sdram_pll.CLKOUT_BYPASS = "false";
    defparam sdram_pll.CLKOUTP_BYPASS = "false";
    defparam sdram_pll.CLKOUTD_BYPASS = "false";
    defparam sdram_pll.DYN_SDIV_SEL = 2;
    defparam sdram_pll.CLKOUTD_SRC = "CLKOUT";
    defparam sdram_pll.CLKOUTD3_SRC = "CLKOUT";
    defparam sdram_pll.DEVICE = "GW2AR-18C";
endmodule
