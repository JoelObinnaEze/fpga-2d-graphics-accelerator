`timescale 1ns/1ps

module tb_framebuffer_read_path;
    localparam int unsigned FRAME_PIXELS = 8;
    localparam int unsigned FIFO_DEPTH = 8;
    localparam int unsigned FIFO_LOW_WATER = 4;
    localparam int unsigned BURST_PIXELS = 4;
    localparam int unsigned WRITE_FIFO_DEPTH = 4;
    localparam int unsigned FIFO_WORD_DEPTH = FIFO_DEPTH / 2;
    localparam int unsigned FIFO_LEVEL_WIDTH =
        $clog2(FIFO_WORD_DEPTH + 1);
    localparam logic [21:0] BASE_ADDRESS = 22'd100;

    logic clk;
    logic rst;
    logic start_valid;
    logic start_ready;
    logic active;
    logic complete;
    logic [FIFO_LEVEL_WIDTH-1:0] fifo_write_level;
    logic fifo_write_valid;
    logic fifo_write_ready;
    logic [31:0] fifo_write_data;
    logic scanout_valid;
    logic scanout_ready;
    logic [21:0] scanout_pixel_address;
    logic [7:0] scanout_data_len;
    logic memory_valid;
    logic memory_ready;
    logic [1:0] memory_operation;
    logic [31:0] memory_address;
    logic [15:0] memory_write_data;
    logic [7:0] memory_data_len;
    logic renderer_write_valid;
    logic renderer_write_ready;
    logic [21:0] renderer_write_address;
    logic [15:0] renderer_write_data;
    logic queued_write_valid;
    logic arbiter_write_ready;
    logic [21:0] queued_write_address;
    logic [15:0] queued_write_data;
    logic writes_committed;
    logic [$clog2(WRITE_FIFO_DEPTH + 1)-1:0] write_queue_count;
    logic [$clog2(2 + 1)-1:0] outstanding_write_count;
    logic write_protocol_error;
    logic refresh_ready;
    logic adapter_response_valid;
    logic adapter_response_ready;
    logic [31:0] adapter_response_data;
    logic write_committed;
    logic read_protocol_error;
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
    int unsigned received_words;
    int unsigned committed_writes;
    int unsigned completion_count;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        #10000;
        $fatal(1, "timed out waiting for integrated framebuffer memory path");
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
        .request_data_len(scanout_data_len),
        .response_valid(adapter_response_valid),
        .response_ready(adapter_response_ready),
        .response_read_data(adapter_response_data)
    );

    framebuffer_write_queue #(
        .FIFO_DEPTH(WRITE_FIFO_DEPTH),
        .MAX_OUTSTANDING_WRITES(2)
    ) write_queue (
        .clk,
        .rst,
        .write_valid(renderer_write_valid),
        .write_ready(renderer_write_ready),
        .write_pixel_address(renderer_write_address),
        .write_data(renderer_write_data),
        .arbiter_valid(queued_write_valid),
        .arbiter_ready(arbiter_write_ready),
        .arbiter_pixel_address(queued_write_address),
        .arbiter_write_data(queued_write_data),
        .backend_write_committed(write_committed),
        .writes_committed,
        .queue_count(write_queue_count),
        .outstanding_count(outstanding_write_count),
        .protocol_error(write_protocol_error)
    );

    framebuffer_arbiter #(
        .READ_FIFO_LOW_WATER(FIFO_LOW_WATER / 2),
        .MAX_CONSECUTIVE_WRITES(2)
    ) arbiter (
        .clk,
        .rst,
        .read_fifo_level(16'(fifo_write_level)),
        .scanout_valid,
        .scanout_ready,
        .scanout_address({10'd0, scanout_pixel_address}),
        .scanout_data_len,
        .write_valid(queued_write_valid),
        .write_ready(arbiter_write_ready),
        .write_address({10'd0, queued_write_address}),
        .write_data(queued_write_data),
        .refresh_valid(1'b0),
        .refresh_ready,
        .memory_valid,
        .memory_ready,
        .memory_operation,
        .memory_address,
        .memory_write_data,
        .memory_data_len
    );

    sdram_pixel_adapter adapter (
        .clk,
        .rst,
        .request_valid(memory_valid),
        .request_ready(memory_ready),
        .request_operation(memory_operation),
        .request_pixel_address(memory_address[21:0]),
        .request_write_data(memory_write_data),
        .request_data_len(memory_data_len),
        .response_valid(adapter_response_valid),
        .response_ready(adapter_response_ready),
        .response_read_data(adapter_response_data),
        .write_committed,
        .read_protocol_error,
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
            received_words <= 0;
            committed_writes <= 0;
            completion_count <= 0;
        end else begin
            if (memory_valid && memory_address[31:22] != 0)
                $fatal(1, "arbiter changed the 22-bit pixel address");

            if (fifo_write_valid && fifo_write_ready) begin
                fifo_write_level <= fifo_write_level + 1'b1;
                if (fifo_write_data !=
                    {16'hA000 + 16'(2 * received_words + 1),
                     16'hA000 + 16'(2 * received_words)})
                    $fatal(1, "read-path data mismatch at word %0d: got %08x",
                           received_words, fifo_write_data);
                received_words <= received_words + 1;
            end
            if (write_committed)
                committed_writes <= committed_writes + 1;
            if (complete)
                completion_count <= completion_count + 1;
        end
    end

    task automatic enqueue_write(input logic [21:0] write_offset);
        @(negedge clk);
        while (!renderer_write_ready)
            @(negedge clk);
        renderer_write_address = 22'd1000 + write_offset;
        renderer_write_data = 16'hB000 + write_offset[15:0];
        renderer_write_valid = 1'b1;
        @(posedge clk);
        #1;
        renderer_write_valid = 1'b0;
    endtask

    task automatic service_read_burst(input int unsigned first_pixel_offset);
        logic [21:0] expected_pixel_address;
        expected_pixel_address = BASE_ADDRESS + 22'(first_pixel_offset);

        @(negedge clk);
        while (controller_read_n)
            @(negedge clk);
        if (!controller_write_n ||
            controller_address != expected_pixel_address[21:1] ||
            controller_data_len != 8'(BURST_PIXELS / 2 - 1) ||
            controller_data_mask != 0)
            $fatal(1, "controller burst mapping mismatch at pixel %0d",
                   expected_pixel_address);

        controller_busy_n = 1'b0;
        controller_ack = 1'b1;
        @(posedge clk);
        #1;
        controller_ack = 1'b0;

        for (int word_index = 0; word_index < BURST_PIXELS / 2;
             word_index++) begin
            @(negedge clk);
            controller_read_data = {
                16'hA000 + 16'(first_pixel_offset + 2 * word_index + 1),
                16'hA000 + 16'(first_pixel_offset + 2 * word_index)
            };
            controller_read_valid = 1'b1;
            @(posedge clk);
            #1;
        end
        controller_read_valid = 1'b0;

        @(negedge clk);
        controller_busy_n = 1'b1;
    endtask

    task automatic service_write(input logic [21:0] write_offset);
        logic [21:0] expected_pixel_address;
        logic [15:0] expected_data;
        logic [3:0] expected_mask;
        logic [31:0] expected_write_data;
        expected_pixel_address = 22'd1000 + write_offset;
        expected_data = 16'hB000 + write_offset[15:0];
        expected_mask = expected_pixel_address[0] ? 4'b0011 : 4'b1100;
        expected_write_data = expected_pixel_address[0]
                            ? {expected_data, 16'd0}
                            : {16'd0, expected_data};

        @(negedge clk);
        while (controller_write_n)
            @(negedge clk);
        if (!controller_read_n ||
            controller_address != expected_pixel_address[21:1] ||
            controller_data_len != 0 ||
            controller_data_mask != expected_mask ||
            controller_write_data != expected_write_data)
            $fatal(1, "controller write mapping mismatch at pixel %0d",
                   expected_pixel_address);

        controller_busy_n = 1'b0;
        controller_ack = 1'b1;
        @(posedge clk);
        #1;
        controller_ack = 1'b0;
        @(negedge clk);
        controller_busy_n = 1'b1;
        @(posedge clk);
        #1;
        if (!write_committed)
            $fatal(1, "adapter did not commit renderer write %0d",
                   write_offset);
    endtask

    initial begin
        rst = 1'b1;
        start_valid = 1'b0;
        renderer_write_valid = 1'b0;
        renderer_write_address = '0;
        renderer_write_data = '0;
        fifo_write_ready = 1'b1;
        controller_init_done = 1'b0;
        controller_busy_n = 1'b1;
        controller_ack = 1'b0;
        controller_read_valid = 1'b0;
        controller_read_data = '0;

        repeat (3) @(posedge clk);
        rst = 1'b0;
        controller_init_done = 1'b1;

        @(negedge clk);
        if (!start_ready || !renderer_write_ready ||
            arbiter_write_ready || refresh_ready || !writes_committed)
            $fatal(1, "integrated path was not idle after reset");
        start_valid = 1'b1;
        @(posedge clk);
        #1;
        start_valid = 1'b0;

        fork
            begin
                enqueue_write(0);
                enqueue_write(1);
                enqueue_write(2);
            end
            begin
                service_read_burst(0);
                service_write(0);
                service_write(1);
                service_read_burst(4);
                service_write(2);
            end
        join

        repeat (2) @(posedge clk);

        if (completion_count != 1 || active ||
            received_words != FRAME_PIXELS / 2 ||
            fifo_write_level != FIFO_LEVEL_WIDTH'(FIFO_WORD_DEPTH))
            $fatal(1, "integrated path did not complete the frame");
        if (!writes_committed || write_queue_count != 0 ||
            outstanding_write_count != 0 || committed_writes != 3 ||
            write_protocol_error || read_protocol_error)
            $fatal(1, "renderer writes or burst reads did not drain cleanly");

        $display("PASS: SDRAM read bursts and queued writes through the arbiter");
        $finish;
    end
endmodule
