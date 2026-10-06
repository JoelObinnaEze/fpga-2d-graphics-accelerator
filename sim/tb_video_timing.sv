`timescale 1ns/1ps

module tb_video_timing;
    localparam int H_ACTIVE = 640;
    localparam int H_FRONT  = 16;
    localparam int H_SYNC   = 96;
    localparam int H_BACK   = 48;
    localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam int V_ACTIVE = 480;
    localparam int V_FRONT  = 10;
    localparam int V_SYNC   = 2;
    localparam int V_BACK   = 33;
    localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    logic clk;
    logic rst;
    logic [$clog2(H_TOTAL)-1:0] x;
    logic [$clog2(V_TOTAL)-1:0] y;
    logic active_video;
    logic hsync;
    logic vsync;
    logic line_start;
    logic frame_start;
    logic vblank_start;
    logic [15:0] pixel;
    int active_count;
    int hsync_low_count;
    int vsync_low_count;
    int line_start_count;
    int frame_start_count;
    int vblank_start_count;
    int expected_x;
    int expected_y;
    bit expected_active;
    bit expected_hsync;
    bit expected_vsync;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    video_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK)
    ) dut (
        .clk, .rst, .x, .y, .active_video, .hsync, .vsync,
        .line_start, .frame_start, .vblank_start
    );

    test_pattern #(
        .H_ACTIVE(H_ACTIVE)
    ) pattern (
        .x, .active_video, .pixel
    );

    function automatic logic [15:0] expected_pixel(input int px, input bit active);
        if (!active)             return 16'h0000;
        if (px < H_ACTIVE / 8)   return 16'hffff;
        if (px < H_ACTIVE * 2/8) return 16'hffe0;
        if (px < H_ACTIVE * 3/8) return 16'h07ff;
        if (px < H_ACTIVE * 4/8) return 16'h07e0;
        if (px < H_ACTIVE * 5/8) return 16'hf81f;
        if (px < H_ACTIVE * 6/8) return 16'hf800;
        if (px < H_ACTIVE * 7/8) return 16'h001f;
        return 16'h0000;
    endfunction

    initial begin
        rst = 1'b1;
        active_count = 0;
        hsync_low_count = 0;
        vsync_low_count = 0;
        line_start_count = 0;
        frame_start_count = 0;
        vblank_start_count = 0;

        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;

        for (int cycle = 0; cycle < H_TOTAL * V_TOTAL; cycle++) begin
            expected_x = cycle % H_TOTAL;
            expected_y = cycle / H_TOTAL;
            expected_active = expected_x < H_ACTIVE && expected_y < V_ACTIVE;
            expected_hsync = !(expected_x >= H_ACTIVE + H_FRONT &&
                               expected_x < H_ACTIVE + H_FRONT + H_SYNC);
            expected_vsync = !(expected_y >= V_ACTIVE + V_FRONT &&
                               expected_y < V_ACTIVE + V_FRONT + V_SYNC);

            if (int'(x) != expected_x || int'(y) != expected_y)
                $fatal(1, "coordinate mismatch at cycle %0d: got (%0d,%0d), expected (%0d,%0d)",
                       cycle, x, y, expected_x, expected_y);
            if (active_video != expected_active)
                $fatal(1, "active_video mismatch at (%0d,%0d)", x, y);
            if (hsync != expected_hsync || vsync != expected_vsync)
                $fatal(1, "sync mismatch at (%0d,%0d): h=%0b v=%0b", x, y, hsync, vsync);
            if (line_start != (expected_x == 0))
                $fatal(1, "line_start mismatch at (%0d,%0d)", x, y);
            if (frame_start != (expected_x == 0 && expected_y == 0))
                $fatal(1, "frame_start mismatch at (%0d,%0d)", x, y);
            if (vblank_start != (expected_x == 0 && expected_y == V_ACTIVE))
                $fatal(1, "vblank_start mismatch at (%0d,%0d)", x, y);
            if (pixel != expected_pixel(expected_x, expected_active))
                $fatal(1, "pixel mismatch at (%0d,%0d): got %04x", x, y, pixel);

            active_count += active_video;
            hsync_low_count += !hsync;
            vsync_low_count += !vsync;
            line_start_count += line_start;
            frame_start_count += frame_start;
            vblank_start_count += vblank_start;

            @(posedge clk);
            #1;
        end

        if (x != 0 || y != 0 || !frame_start)
            $fatal(1, "frame did not wrap to (0,0)");
        if (active_count != H_ACTIVE * V_ACTIVE)
            $fatal(1, "active pixel count was %0d", active_count);
        if (hsync_low_count != H_SYNC * V_TOTAL)
            $fatal(1, "hsync low count was %0d", hsync_low_count);
        if (vsync_low_count != V_SYNC * H_TOTAL)
            $fatal(1, "vsync low count was %0d", vsync_low_count);
        if (line_start_count != V_TOTAL || frame_start_count != 1 || vblank_start_count != 1)
            $fatal(1, "event counts line=%0d frame=%0d vblank=%0d",
                   line_start_count, frame_start_count, vblank_start_count);

        $display("PASS: 640x480 timing and RGB565 color bars (%0d cycles)", H_TOTAL * V_TOTAL);
        $finish;
    end
endmodule
