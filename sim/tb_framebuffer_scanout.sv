`timescale 1ns/1ps

module tb_framebuffer_scanout;
    localparam int H_ACTIVE = 4;
    localparam int H_FRONT  = 1;
    localparam int H_SYNC   = 1;
    localparam int H_BACK   = 1;
    localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam int V_ACTIVE = 3;
    localparam int V_FRONT  = 1;
    localparam int V_SYNC   = 1;
    localparam int V_BACK   = 1;
    localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    localparam int X_WIDTH  = $clog2(H_ACTIVE);
    localparam int Y_WIDTH  = $clog2(V_ACTIVE);

    logic clk;
    logic rst;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [$clog2(H_TOTAL)-1:0] timing_x;
    logic [$clog2(V_TOTAL)-1:0] timing_y;
    /* verilator lint_on UNUSEDSIGNAL */
    logic timing_active;
    logic timing_hsync;
    logic timing_vsync;
    logic write_valid;
    logic [X_WIDTH-1:0] write_x;
    logic [Y_WIDTH-1:0] write_y;
    logic [15:0] write_pixel;
    logic read_valid;
    logic [X_WIDTH-1:0] read_x;
    logic [Y_WIDTH-1:0] read_y;
    logic read_pixel_valid;
    logic [15:0] read_pixel;
    logic out_active;
    logic out_hsync;
    logic out_vsync;
    logic [15:0] out_pixel;
    int active_count;
    int expected_x;
    int expected_y;
    bit expected_active;
    bit expected_hsync;
    bit expected_vsync;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    /* verilator lint_off PINCONNECTEMPTY */
    video_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK)
    ) timing (
        .clk, .rst, .x(timing_x), .y(timing_y), .active_video(timing_active),
        .hsync(timing_hsync), .vsync(timing_vsync),
        .line_start(), .frame_start(), .vblank_start()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    framebuffer_scanout #(
        .FRAME_WIDTH(H_ACTIVE), .FRAME_HEIGHT(V_ACTIVE)
    ) scanout (
        .clk, .rst,
        .timing_x(timing_x[X_WIDTH-1:0]),
        .timing_y(timing_y[Y_WIDTH-1:0]),
        .timing_active, .timing_hsync, .timing_vsync,
        .read_valid, .read_x, .read_y, .read_pixel_valid, .read_pixel,
        .out_active, .out_hsync, .out_vsync, .out_pixel
    );

    framebuffer_bram #(
        .FRAME_WIDTH(H_ACTIVE), .FRAME_HEIGHT(V_ACTIVE)
    ) framebuffer (
        .clk,
        .write_valid, .write_x, .write_y, .write_pixel,
        .read_valid, .read_x, .read_y, .read_pixel_valid, .read_pixel
    );

    function automatic logic [15:0] expected_pixel(input int px, input int py);
        return 16'h1000 + 16'(py * H_ACTIVE + px);
    endfunction

    initial begin
        rst = 1'b1;
        write_valid = 1'b0;
        write_x = '0;
        write_y = '0;
        write_pixel = '0;
        active_count = 0;

        for (int py = 0; py < V_ACTIVE; py++) begin
            for (int px = 0; px < H_ACTIVE; px++) begin
                @(negedge clk);
                write_valid = 1'b1;
                write_x = X_WIDTH'(px);
                write_y = Y_WIDTH'(py);
                write_pixel = expected_pixel(px, py);
            end
        end
        @(negedge clk);
        write_valid = 1'b0;
        rst = 1'b0;

        for (int cycle = 0; cycle < H_TOTAL * V_TOTAL; cycle++) begin
            expected_x = cycle % H_TOTAL;
            expected_y = cycle / H_TOTAL;
            expected_active = expected_x < H_ACTIVE && expected_y < V_ACTIVE;
            expected_hsync = !(expected_x >= H_ACTIVE + H_FRONT &&
                               expected_x < H_ACTIVE + H_FRONT + H_SYNC);
            expected_vsync = !(expected_y >= V_ACTIVE + V_FRONT &&
                               expected_y < V_ACTIVE + V_FRONT + V_SYNC);

            @(posedge clk);
            #1;
            if (out_active != expected_active || out_hsync != expected_hsync || out_vsync != expected_vsync)
                $fatal(1, "scanout control mismatch at source (%0d,%0d)", expected_x, expected_y);
            if (out_pixel != (expected_active ? expected_pixel(expected_x, expected_y) : 16'h0000))
                $fatal(1, "scanout pixel mismatch at source (%0d,%0d): got %04x",
                       expected_x, expected_y, out_pixel);
            active_count += out_active;
        end

        if (active_count != H_ACTIVE * V_ACTIVE)
            $fatal(1, "scanout active count was %0d", active_count);

        $display("PASS: synchronous framebuffer scanout (%0d pixels)", active_count);
        $finish;
    end
endmodule
