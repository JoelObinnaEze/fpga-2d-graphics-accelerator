`timescale 1ns/1ps

module tang_nano_20k_sdram_scanout (
    input  wire        clk_27mhz,
    output wire [5:0]  led_n,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    output wire [3:0]  O_sdram_dqm,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    inout  wire [31:0] IO_sdram_dq
);
    wire serial_clk;
    wire pixel_clk;
    wire video_pll_locked;
    wire controller_clk;
    wire sdram_clk;
    wire memory_pll_locked;
    wire clocks_locked = video_pll_locked && memory_pll_locked;

    logic [3:0] controller_reset_pipe = '0;
    logic [3:0] pixel_reset_pipe = '0;
    logic [3:0] serializer_reset_pipe = '0;
    wire controller_reset = !controller_reset_pipe[3];
    wire controller_reset_n = controller_reset_pipe[3];
    wire pixel_reset = !pixel_reset_pipe[3];
    wire serializer_reset = !serializer_reset_pipe[3];

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

    logic framebuffer_ready;
    logic initialization_active;
    logic prefetch_active;
    logic prefetch_complete;
    logic scanout_enabled;
    logic scanout_underflow;
    logic write_protocol_error;
    logic prefetch_seen;

    wire controller_init_done;
    wire controller_busy_n;
    wire controller_ack;
    wire controller_read_valid;
    wire [31:0] controller_read_data;
    logic controller_write_n;
    logic controller_read_n;
    logic [20:0] controller_address;
    logic [7:0] controller_data_len;
    logic [3:0] controller_data_mask;
    logic [31:0] controller_write_data;

    gowin_dvi_clock video_clock_generator (
        .clk_27mhz,
        .serial_clk,
        .pixel_clk,
        .locked(video_pll_locked)
    );

    gowin_sdram_clock memory_clock_generator (
        .clk_27mhz,
        .controller_clk,
        .sdram_clk,
        .locked(memory_pll_locked)
    );

    always_ff @(posedge controller_clk or negedge clocks_locked) begin
        if (!clocks_locked)
            controller_reset_pipe <= '0;
        else
            controller_reset_pipe <= {controller_reset_pipe[2:0], 1'b1};
    end

    always_ff @(posedge pixel_clk or negedge clocks_locked) begin
        if (!clocks_locked)
            pixel_reset_pipe <= '0;
        else
            pixel_reset_pipe <= {pixel_reset_pipe[2:0], 1'b1};
    end

    always_ff @(posedge serial_clk or negedge clocks_locked) begin
        if (!clocks_locked)
            serializer_reset_pipe <= '0;
        else
            serializer_reset_pipe <= {serializer_reset_pipe[2:0], 1'b1};
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

    sdram_framebuffer_core framebuffer (
        .controller_clk,
        .controller_rst(controller_reset),
        .pixel_clk,
        .pixel_rst(pixel_reset),
        .active_video,
        .vblank_start,
        .vblank_active(y >= 10'd480),
        .pixel,
        .framebuffer_ready,
        .initialization_active,
        .prefetch_active,
        .prefetch_complete,
        .scanout_enabled,
        .scanout_underflow,
        .write_protocol_error,
        .renderer_write_valid(1'b0),
        .renderer_write_ready(),
        .renderer_write_pixel_address(22'd0),
        .renderer_write_data(16'd0),
        .present_valid(1'b0),
        .present_ready(),
        .present_sequence(8'd0),
        .present_pending(),
        .present_done(),
        .completed_sequence(),
        .front_buffer_base(),
        .draw_buffer_base(),
        .draw_allowed(),
        .writes_committed(),
        .controller_init_done,
        .controller_busy_n,
        .controller_ack,
        .controller_read_valid,
        .controller_read_data,
        .controller_write_n,
        .controller_read_n,
        .controller_address,
        .controller_data_len,
        .controller_data_mask,
        .controller_write_data
    );

    SDRAM_controller_top_SIP controller (
        .I_sdrc_rst_n(controller_reset_n),
        .I_sdrc_clk(controller_clk),
        .I_sdram_clk(sdram_clk),
        .I_sdrc_selfrefresh(1'b0),
        .I_sdrc_power_down(1'b0),
        .I_sdrc_wr_n(controller_write_n),
        .I_sdrc_rd_n(controller_read_n),
        .I_sdrc_addr(controller_address),
        .I_sdrc_data_len(controller_data_len),
        .I_sdrc_dqm(controller_data_mask),
        .I_sdrc_data(controller_write_data),
        .O_sdrc_data(controller_read_data),
        .O_sdrc_init_done(controller_init_done),
        .O_sdrc_busy_n(controller_busy_n),
        .O_sdrc_rd_valid(controller_read_valid),
        .O_sdrc_wrd_ack(controller_ack),
        .O_sdram_clk,
        .O_sdram_cke,
        .O_sdram_cs_n,
        .O_sdram_cas_n,
        .O_sdram_ras_n,
        .O_sdram_wen_n,
        .O_sdram_dqm,
        .O_sdram_addr,
        .O_sdram_ba,
        .IO_sdram_dq
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
        .rst(serializer_reset),
        .red_symbol,
        .green_symbol,
        .blue_symbol,
        .tmds_clk_p,
        .tmds_clk_n,
        .tmds_data_p,
        .tmds_data_n
    );

    always_ff @(posedge controller_clk) begin
        if (controller_reset)
            prefetch_seen <= 1'b0;
        else if (prefetch_complete)
            prefetch_seen <= 1'b1;
    end

    // Active-low diagnostics, LED0 through LED5: reset released, SDRAM
    // initialized, framebuffer initialized/committed, scanout enabled,
    // underflow/protocol error, and at least one frame prefetched.
    assign led_n[0] = ~controller_reset_n;
    assign led_n[1] = ~controller_init_done;
    assign led_n[2] = ~framebuffer_ready;
    assign led_n[3] = ~scanout_enabled;
    assign led_n[4] = ~(scanout_underflow || write_protocol_error);
    assign led_n[5] = ~prefetch_seen;
endmodule
