`timescale 1ns/1ps

module tb_sprite_renderer;
    localparam int FRAME_WIDTH = 4;
    localparam int FRAME_HEIGHT = 3;

    logic clk;
    logic rst;
    logic start;
    logic [15:0] sprite_id;
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic descriptor_valid;
    logic [31:0] descriptor_base;
    logic [15:0] descriptor_width;
    logic [15:0] descriptor_height;
    logic sprite_read_enable;
    logic [31:0] sprite_address;
    logic sprite_pixel_valid;
    logic [15:0] sprite_pixel_color;
    logic sprite_pixel_opaque;
    logic busy;
    logic done;
    logic write_valid;
    logic write_ready;
    logic [15:0] write_x;
    logic [15:0] write_y;
    logic [15:0] write_color;
    logic stalled;
    logic [15:0] stalled_x;
    logic [15:0] stalled_y;
    logic [15:0] stalled_color;
    int write_count;
    int read_count;
    int observed_x [0:15];
    int observed_y [0:15];
    logic [15:0] observed_color [0:15];

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    sprite_store #(
        .SPRITE_COUNT(2),
        .PIXEL_COUNT(10),
        .DESCRIPTOR_FILE("sim/data/sprite_descriptors.hex"),
        .COLOR_FILE("sim/data/sprite_colors.hex"),
        .OPACITY_FILE("sim/data/sprite_opacity.hex")
    ) store (
        .clk,
        .sprite_id,
        .descriptor_valid,
        .descriptor_base,
        .descriptor_width,
        .descriptor_height,
        .read_enable(sprite_read_enable),
        .read_address(sprite_address),
        .pixel_valid(sprite_pixel_valid),
        .pixel_color(sprite_pixel_color),
        .pixel_opaque(sprite_pixel_opaque)
    );

    sprite_renderer #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) renderer (
        .clk, .rst, .start, .origin_x, .origin_y,
        .sprite_valid(descriptor_valid),
        .sprite_base(descriptor_base),
        .sprite_width(descriptor_width),
        .sprite_height(descriptor_height),
        .sprite_read_enable,
        .sprite_address,
        .sprite_pixel_valid,
        .sprite_pixel_color,
        .sprite_pixel_opaque,
        .busy, .done,
        .write_valid, .write_ready, .write_x, .write_y, .write_color
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            write_count <= 0;
            read_count <= 0;
            stalled <= 1'b0;
        end else begin
            if (sprite_read_enable)
                read_count <= read_count + 1;

            if (stalled && (!write_valid || write_x != stalled_x ||
                            write_y != stalled_y || write_color != stalled_color))
                $fatal(1, "write payload changed during a stall");

            stalled <= write_valid && !write_ready;
            if (write_valid && !write_ready) begin
                stalled_x <= write_x;
                stalled_y <= write_y;
                stalled_color <= write_color;
            end

            if (write_valid && write_ready) begin
                observed_x[write_count] <= int'(write_x);
                observed_y[write_count] <= int'(write_y);
                observed_color[write_count] <= write_color;
                write_count <= write_count + 1;
            end
        end
    end

    task automatic clear_observations;
        @(negedge clk);
        write_count = 0;
        read_count = 0;
        stalled = 1'b0;
    endtask

    task automatic begin_sprite(
        input logic [15:0] id,
        input logic [15:0] x,
        input logic [15:0] y
    );
        @(negedge clk);
        sprite_id = id;
        origin_x = x;
        origin_y = y;
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
    endtask

    task automatic wait_done;
        if (done)
            return;
        for (int cycles = 0; cycles < 100; cycles++) begin
            @(posedge clk);
            #1;
            if (done)
                return;
        end
        $fatal(1, "sprite renderer timed out");
    endtask

    task automatic expect_write(
        input int index,
        input int x,
        input int y,
        input logic [15:0] color
    );
        if (observed_x[index] != x || observed_y[index] != y ||
            observed_color[index] != color)
            $fatal(1, "write %0d mismatch", index);
    endtask

    initial begin
        rst = 1'b1;
        start = 1'b0;
        sprite_id = '0;
        origin_x = '0;
        origin_y = '0;
        write_ready = 1'b1;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        clear_observations();
        begin_sprite(0, 1, 1);
        wait_done();
        if (write_count != 4 || read_count != 6)
            $fatal(1, "sprite mask/source traversal count mismatch");
        expect_write(0, 1, 1, 16'h1111);
        expect_write(1, 3, 1, 16'h3333);
        expect_write(2, 2, 2, 16'h5555);
        expect_write(3, 3, 2, 16'h6666);

        clear_observations();
        begin_sprite(0, 3, 2);
        wait_done();
        if (write_count != 1 || read_count != 1)
            $fatal(1, "clipped sprite read or wrote hidden source pixels");
        expect_write(0, 3, 2, 16'h1111);

        clear_observations();
        begin_sprite(16'hffff, 0, 0);
        wait_done();
        if (write_count != 0 || read_count != 0 || busy)
            $fatal(1, "invalid sprite ID was not a deterministic no-op");

        clear_observations();
        write_ready = 1'b0;
        begin_sprite(1, 0, 0);
        wait (write_valid);
        repeat (3) @(posedge clk);
        write_ready = 1'b1;
        wait_done();
        if (write_count != 3 || read_count != 4)
            $fatal(1, "stalled sprite lost or duplicated pixels");
        expect_write(0, 0, 0, 16'haaaa);
        expect_write(1, 1, 0, 16'hbbbb);
        expect_write(2, 1, 1, 16'hdddd);

        $display("PASS: sprite source indexing, opacity, clipping, invalid IDs, and stalls");
        $finish;
    end
endmodule
