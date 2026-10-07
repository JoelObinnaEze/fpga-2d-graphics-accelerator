`timescale 1ns/1ps

module tang_nano_20k_dvi (
    input  wire       clk_27mhz,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n
);
    wire serial_clk;
    wire pixel_clk;
    wire pll_locked;
    logic [3:0] reset_pipe;
    wire pixel_reset = !reset_pipe[3];
    logic [9:0] x;
    logic [9:0] y;
    logic active_video;
    logic hsync;
    logic vsync;
    logic line_start;
    logic frame_start;
    logic vblank_start;
    logic [15:0] pixel;
    wire [7:0] red = {pixel[15:11], pixel[15:13]};
    wire [7:0] green = {pixel[10:5], pixel[10:9]};
    wire [7:0] blue = {pixel[4:0], pixel[4:2]};
    logic [9:0] red_symbol;
    logic [9:0] green_symbol;
    logic [9:0] blue_symbol;

    gowin_dvi_clock clock_generator (
        .clk_27mhz,
        .serial_clk,
        .pixel_clk,
        .locked(pll_locked)
    );

    always_ff @(posedge pixel_clk or negedge pll_locked) begin
        if (!pll_locked)
            reset_pipe <= '0;
        else
            reset_pipe <= {reset_pipe[2:0], 1'b1};
    end

    video_timing timing_generator (
        .clk(pixel_clk),
        .rst(pixel_reset),
        .x,
        .y,
        .active_video,
        .hsync,
        .vsync,
        .line_start,
        .frame_start,
        .vblank_start
    );

    test_pattern color_bars (
        .x,
        .active_video,
        .pixel
    );

    tmds_encoder red_encoder (
        .clk(pixel_clk), .rst(pixel_reset), .data(red),
        .control0(1'b0), .control1(1'b0),
        .data_enable(active_video), .symbol(red_symbol)
    );
    tmds_encoder green_encoder (
        .clk(pixel_clk), .rst(pixel_reset), .data(green),
        .control0(1'b0), .control1(1'b0),
        .data_enable(active_video), .symbol(green_symbol)
    );
    tmds_encoder blue_encoder (
        .clk(pixel_clk), .rst(pixel_reset), .data(blue),
        .control0(hsync), .control1(vsync),
        .data_enable(active_video), .symbol(blue_symbol)
    );

    gowin_tmds_serializer serializer (
        .pixel_clk,
        .serial_clk,
        .rst(pixel_reset),
        .red_symbol,
        .green_symbol,
        .blue_symbol,
        .tmds_clk_p,
        .tmds_clk_n,
        .tmds_data_p,
        .tmds_data_n
    );
endmodule
