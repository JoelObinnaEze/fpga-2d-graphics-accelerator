`timescale 1ns/1ps

module tb_framebuffer_read_path;
    localparam int unsigned FRAME_PIXELS = 6;
    localparam int unsigned FIFO_DEPTH = 4;
    localparam int unsigned FIFO_LOW_WATER = 1;
    localparam int unsigned BURST_PIXELS = 2;
    localparam int unsigned FIFO_LEVEL_WIDTH = $clog2(FIFO_DEPTH + 1);
    localparam logic [21:0] BASE_ADDRESS = 22'd101;

    logic clk;
    logic rst;
    logic start_valid;
    logic start_ready;
    logic active;
    logic complete;
    logic [FIFO_LEVEL_WIDTH-1:0] fifo_write_level;
    logic fifo_write_valid;
    logic fifo_write_ready;
    logic [15:0] fifo_write_data;
    logic consume_pixel;
    logic scanout_valid;
    logic scanout_ready;
    logic [21:0] scanout_pixel_address;
    logic memory_valid;
    logic memory_ready;
    logic [1:0] memory_operation;
    logic [31:0] memory_address;
    logic [15:0] memory_write_data;
    logic write_ready;
    logic refresh_ready;
    logic adapter_response_valid;
    logic adapter_response_ready;
    logic [15:0] adapter_response_data;
    logic write_committed;
    logic controller_init_done;
    logic controller_busy_n;
    logic controller_ack;
    logic controller_read_valid;
    logic [31:0] controller_read_data;
    logic controller_write_n;
    logic controller_read_n;
    logic [20:0] controller_address;
    logic [7:0] controller_data_len;
    logic [3:0] controller_data_mask;
    logic [31:0] controller_write_data;
    int unsigned received_pixels;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        #10000;
        $fatal(1, "timed out waiting for integrated framebuffer read path");
    end

    framebuffer_read_prefetch #(
        .FRAME_PIXELS(FRAME_PIXELS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_LOW_WATER(FIFO_LOW_WATER),
        .BURST_PIXELS(BURST_PIXELS)
    ) prefetch (
        .clk,
        .rst,
        .start_valid,
        .start_ready,
        .start_pixel_address(BASE_ADDRESS),
        .active,
        .complete,
        .fifo_write_level,
        .fifo_write_valid,
        .fifo_write_ready,
        .fifo_write_data,
        .request_valid(scanout_valid),
        .request_ready(scanout_ready),
        .request_pixel_address(scanout_pixel_address),
        .response_valid(adapter_response_valid),
        .response_ready(adapter_response_ready),
        .response_read_data(adapter_response_data)
    );

    framebuffer_arbiter #(
        .READ_FIFO_LOW_WATER(2),
        .MAX_CONSECUTIVE_WRITES(2)
    ) arbiter (
        .clk,
        .rst,
        .read_fifo_level(16'(fifo_write_level)),
        .scanout_valid,
        .scanout_ready,
        .scanout_address({10'd0, scanout_pixel_address}),
        .write_valid(1'b0),
        .write_ready,
        .write_address('0),
        .write_data('0),
        .refresh_valid(1'b0),
        .refresh_ready,
        .memory_valid,
        .memory_ready,
        .memory_operation,
        .memory_address,
        .memory_write_data
    );

    sdram_pixel_adapter adapter (
        .clk,
        .rst,
        .request_valid(memory_valid),
        .request_ready(memory_ready),
        .request_operation(memory_operation),
        .request_pixel_address(memory_address[21:0]),
        .request_write_data(memory_write_data),
        .response_valid(adapter_response_valid),
        .response_ready(adapter_response_ready),
        .response_read_data(adapter_response_data),
        .write_committed,
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

    always_ff @(posedge clk) begin
        if (rst) begin
            fifo_write_level <= '0;
            received_pixels <= 0;
        end else begin
            if (memory_valid && memory_address[31:22] != 0)
                $fatal(1, "arbiter changed the 22-bit pixel address");

            case ({fifo_write_valid && fifo_write_ready, consume_pixel})
                2'b10: fifo_write_level <= fifo_write_level + 1'b1;
                2'b01: fifo_write_level <= fifo_write_level - 1'b1;
                default: fifo_write_level <= fifo_write_level;
            endcase

            if (fifo_write_valid && fifo_write_ready) begin
                if (fifo_write_data != 16'hA000 + 16'(received_pixels))
                    $fatal(1, "read-path data mismatch at pixel %0d: got %04x",
                           received_pixels, fifo_write_data);
                received_pixels <= received_pixels + 1;
            end
        end
    end

    task automatic service_read(input int unsigned pixel_offset);
        logic [21:0] expected_pixel_address;
        logic [15:0] expected_data;
        expected_pixel_address = BASE_ADDRESS + 22'(pixel_offset);
        expected_data = 16'hA000 + 16'(pixel_offset);

        @(negedge clk);
        while (controller_read_n)
            @(negedge clk);
        if (!controller_write_n ||
            controller_address != expected_pixel_address[21:1] ||
            controller_data_len != 0 || controller_data_mask != 0)
            $fatal(1, "controller mapping mismatch for pixel address %0d",
                   expected_pixel_address);

        controller_busy_n = 1'b0;
        controller_ack = 1'b1;
        @(posedge clk);
        #1;
        controller_ack = 1'b0;

        @(negedge clk);
        controller_read_data = expected_pixel_address[0]
                             ? {expected_data, 16'hbeef}
                             : {16'hdead, expected_data};
        controller_read_valid = 1'b1;
        @(posedge clk);
        #1;
        controller_read_valid = 1'b0;

        @(negedge clk);
        controller_busy_n = 1'b1;
        wait (received_pixels == pixel_offset + 1);
    endtask

    task automatic consume_one;
        @(negedge clk);
        consume_pixel = 1'b1;
        @(posedge clk);
        #1;
        consume_pixel = 1'b0;
    endtask

    initial begin
        rst = 1'b1;
        start_valid = 1'b0;
        fifo_write_ready = 1'b1;
        consume_pixel = 1'b0;
        controller_init_done = 1'b0;
        controller_busy_n = 1'b1;
        controller_ack = 1'b0;
        controller_read_valid = 1'b0;
        controller_read_data = '0;

        repeat (3) @(posedge clk);
        rst = 1'b0;
        controller_init_done = 1'b1;

        @(negedge clk);
        if (!start_ready || write_ready || refresh_ready)
            $fatal(1, "integrated path was not idle after reset");
        start_valid = 1'b1;
        @(posedge clk);
        #1;
        start_valid = 1'b0;

        service_read(0);
        service_read(1);
        repeat (4) @(posedge clk);
        if (!active || int'(fifo_write_level) != 2 || !controller_read_n)
            $fatal(1, "prefetch did not pause above its low-water mark");

        consume_one();
        service_read(2);
        service_read(3);
        if (int'(fifo_write_level) != 3)
            $fatal(1, "unexpected FIFO level after second burst");

        consume_one();
        consume_one();
        service_read(4);
        service_read(5);

        if (!complete || active || received_pixels != FRAME_PIXELS)
            $fatal(1, "integrated path did not complete the frame");
        if (!controller_write_n || write_committed || controller_write_data != 0)
            $fatal(1, "read-only path unexpectedly issued a write");

        $display("PASS: prefetch-to-arbiter-to-SDRAM-adapter read path");
        $finish;
    end
endmodule
