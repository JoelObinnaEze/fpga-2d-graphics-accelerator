`timescale 1ns/1ps

module tb_rect_renderer;
    localparam int FRAME_WIDTH = 8;
    localparam int FRAME_HEIGHT = 6;
    localparam int COORD_WIDTH = 8;

    logic clk;
    logic rst;
    logic cmd_valid;
    logic cmd_ready;
    logic [COORD_WIDTH-1:0] cmd_x;
    logic [COORD_WIDTH-1:0] cmd_y;
    logic [COORD_WIDTH-1:0] cmd_width;
    logic [COORD_WIDTH-1:0] cmd_height;
    logic [15:0] cmd_color;
    logic write_valid;
    logic write_ready;
    logic [$clog2(FRAME_WIDTH)-1:0] write_x;
    logic [$clog2(FRAME_HEIGHT)-1:0] write_y;
    logic [15:0] write_pixel;
    logic busy;
    logic done;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    rect_renderer #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .COORD_WIDTH(COORD_WIDTH)
    ) dut (.*);

    task automatic run_rect(
        input int x,
        input int y,
        input int width,
        input int height,
        input logic [15:0] color
    );
        int clip_end_x;
        int clip_end_y;
        int expected_x;
        int expected_y;
        int expected_count;
        int actual_count;
        int cycles;
        bit held;
        int held_x;
        int held_y;
        logic [15:0] held_pixel;

        clip_end_x = x + width > FRAME_WIDTH ? FRAME_WIDTH : x + width;
        clip_end_y = y + height > FRAME_HEIGHT ? FRAME_HEIGHT : y + height;
        expected_count = width == 0 || height == 0 || x >= FRAME_WIDTH || y >= FRAME_HEIGHT
                       ? 0 : (clip_end_x - x) * (clip_end_y - y);
        expected_x = x;
        expected_y = y;
        actual_count = 0;
        cycles = 0;
        held = 0;

        @(negedge clk);
        if (!cmd_ready)
            $fatal(1, "renderer was not ready for a command");
        cmd_x = COORD_WIDTH'(x);
        cmd_y = COORD_WIDTH'(y);
        cmd_width = COORD_WIDTH'(width);
        cmd_height = COORD_WIDTH'(height);
        cmd_color = color;
        cmd_valid = 1'b1;

        @(posedge clk);
        #1;
        cmd_valid = 1'b0;

        while (!done) begin
            bit transfer;
            int transfer_x;
            int transfer_y;
            logic [15:0] transfer_pixel;

            @(negedge clk);
            if (held && (int'(write_x) != held_x || int'(write_y) != held_y ||
                         write_pixel != held_pixel))
                $fatal(1, "write payload changed while stalled");

            write_ready = cycles % 3 != 0;
            transfer = write_valid && write_ready;
            transfer_x = int'(write_x);
            transfer_y = int'(write_y);
            transfer_pixel = write_pixel;
            held = write_valid && !write_ready;
            held_x = int'(write_x);
            held_y = int'(write_y);
            held_pixel = write_pixel;

            @(posedge clk);
            #1;
            if (transfer) begin
                if (transfer_x != expected_x || transfer_y != expected_y)
                    $fatal(1, "write %0d was (%0d,%0d), expected (%0d,%0d)",
                           actual_count, transfer_x, transfer_y, expected_x, expected_y);
                if (transfer_pixel != color)
                    $fatal(1, "write color was %04x, expected %04x", transfer_pixel, color);
                if (transfer_x >= FRAME_WIDTH || transfer_y >= FRAME_HEIGHT)
                    $fatal(1, "out-of-range write (%0d,%0d)", transfer_x, transfer_y);

                actual_count++;
                if (expected_x + 1 == clip_end_x) begin
                    expected_x = x;
                    expected_y++;
                end else begin
                    expected_x++;
                end
            end

            cycles++;
            if (cycles > FRAME_WIDTH * FRAME_HEIGHT * 3 + 10)
                $fatal(1, "renderer timed out");
        end

        if (actual_count != expected_count)
            $fatal(1, "rectangle wrote %0d pixels, expected %0d", actual_count, expected_count);
        if (busy)
            $fatal(1, "busy remained high after completion");
        write_ready = 1'b0;
    endtask

    initial begin
        rst = 1'b1;
        cmd_valid = 1'b0;
        cmd_x = '0;
        cmd_y = '0;
        cmd_width = '0;
        cmd_height = '0;
        cmd_color = '0;
        write_ready = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;

        run_rect(2, 1, 3, 2, 16'hf800);
        run_rect(6, 4, 4, 4, 16'h07e0);
        run_rect(1, 1, 0, 2, 16'h001f);
        run_rect(9, 0, 3, 2, 16'hffff);
        run_rect(7, 2, 255, 1, 16'hf81f);
        run_rect(0, 0, 255, 255, 16'h07ff);

        $display("PASS: clipped rectangle renderer with backpressure");
        $finish;
    end
endmodule
