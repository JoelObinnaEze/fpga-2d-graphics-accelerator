`timescale 1ns/1ps

// Portable controller/pixel-domain core for SDRAM-backed RGB565 scanout.
// The controller domain initializes one framebuffer with color bars, tracks
// committed writes, and continuously prefetches sequential pixels. An
// asynchronous FIFO carries pixels into the video domain. Scanout is enabled
// only at VBlank after both initialization and FIFO prefill; underflow outputs
// black and latches a sticky diagnostic.
module sdram_framebuffer_core #(
    parameter int unsigned FRAME_WIDTH = 640,
    parameter int unsigned FRAME_HEIGHT = 480,
    parameter int unsigned READ_FIFO_DEPTH = 512,
    parameter int unsigned READ_FIFO_LOW_WATER = 256,
    parameter int unsigned READ_BURST_PIXELS = 32,
    parameter int unsigned WRITE_FIFO_DEPTH = 64
) (
    input  logic controller_clk,
    input  logic controller_rst,
    input  logic pixel_clk,
    input  logic pixel_rst,
    input  logic active_video,
    input  logic vblank_start,
    output logic [15:0] pixel,
    output logic framebuffer_ready,
    output logic initialization_active,
    output logic prefetch_active,
    output logic prefetch_complete,
    output logic scanout_enabled,
    output logic scanout_underflow,
    output logic write_protocol_error,
    input  logic controller_init_done,
    input  logic controller_busy_n,
    input  logic controller_ack,
    input  logic controller_read_valid,
    input  logic [31:0] controller_read_data,
    output logic controller_write_n,
    output logic controller_read_n,
    output logic [20:0] controller_address,
    output logic [7:0] controller_data_len,
    output logic [3:0] controller_data_mask,
    output logic [31:0] controller_write_data
);
    localparam int unsigned FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int unsigned READ_LEVEL_WIDTH =
        $clog2(READ_FIFO_DEPTH + 1);
    localparam int unsigned WRITE_LEVEL_WIDTH =
        $clog2(WRITE_FIFO_DEPTH + 1);

    logic initializer_start_valid;
    logic initializer_start_ready;
    logic initializer_write_valid;
    logic initializer_write_ready;
    logic [21:0] initializer_write_address;
    logic [15:0] initializer_write_data;
    logic initializer_complete;
    logic initialization_started;
    logic initialization_issued;

    logic queued_write_valid;
    logic queued_write_ready;
    logic [21:0] queued_write_address;
    logic [15:0] queued_write_data;
    logic buffered_write_valid;
    logic buffered_write_ready;
    logic [21:0] buffered_write_address;
    logic [15:0] buffered_write_data;
    logic writes_committed;
    logic [WRITE_LEVEL_WIDTH-1:0] write_queue_count;
    logic [$clog2(2 + 1)-1:0] outstanding_write_count;
    logic adapter_write_committed;

    logic prefetch_start_valid;
    logic prefetch_start_ready;
    logic prefetch_request_valid;
    logic prefetch_request_ready;
    logic [21:0] prefetch_request_address;
    logic buffered_read_valid;
    logic buffered_read_ready;
    logic [21:0] buffered_read_address;

    logic [READ_LEVEL_WIDTH-1:0] read_fifo_write_level;
    logic [READ_LEVEL_WIDTH-1:0] scheduled_fifo_level;
    logic read_fifo_write_valid;
    logic read_fifo_write_ready;
    logic [15:0] read_fifo_write_data;
    logic read_fifo_read_valid;
    logic read_fifo_read_ready;
    logic [15:0] read_fifo_read_data;
    logic [READ_LEVEL_WIDTH-1:0] read_fifo_read_level;

    logic arbiter_memory_valid;
    logic arbiter_memory_ready;
    logic [1:0] arbiter_memory_operation;
    logic [31:0] arbiter_memory_address;
    logic [15:0] arbiter_memory_write_data;
    logic refresh_ready;
    logic address_upper_zero;
    logic adapter_response_valid;
    logic adapter_response_ready;
    logic [31:0] adapter_response_data;

    logic framebuffer_ready_sync1;
    logic framebuffer_ready_sync2;

    initial begin
        if (FRAME_PIXELS == 0 || FRAME_PIXELS > 4194304)
            $error("frame size must fit the 22-bit pixel-address space");
    end

    assign initializer_start_valid = controller_init_done &&
                                     !initialization_started;
    assign prefetch_start_valid = framebuffer_ready && prefetch_start_ready;

    framebuffer_colorbar_writer #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) initializer (
        .clk(controller_clk),
        .rst(controller_rst),
        .start_valid(initializer_start_valid),
        .start_ready(initializer_start_ready),
        .start_pixel_address(22'd0),
        .write_valid(initializer_write_valid),
        .write_ready(initializer_write_ready),
        .write_pixel_address(initializer_write_address),
        .write_data(initializer_write_data),
        .active(initialization_active),
        .complete(initializer_complete)
    );

    framebuffer_write_queue #(
        .FIFO_DEPTH(WRITE_FIFO_DEPTH),
        .MAX_OUTSTANDING_WRITES(2)
    ) write_queue (
        .clk(controller_clk),
        .rst(controller_rst),
        .write_valid(initializer_write_valid),
        .write_ready(initializer_write_ready),
        .write_pixel_address(initializer_write_address),
        .write_data(initializer_write_data),
        .arbiter_valid(queued_write_valid),
        .arbiter_ready(queued_write_ready),
        .arbiter_pixel_address(queued_write_address),
        .arbiter_write_data(queued_write_data),
        .backend_write_committed(adapter_write_committed),
        .writes_committed,
        .queue_count(write_queue_count),
        .outstanding_count(outstanding_write_count),
        .protocol_error(write_protocol_error)
    );

    framebuffer_read_prefetch #(
        .FRAME_PIXELS(FRAME_PIXELS),
        .FIFO_DEPTH(READ_FIFO_DEPTH),
        .FIFO_LOW_WATER(READ_FIFO_LOW_WATER),
        .BURST_PIXELS(READ_BURST_PIXELS)
    ) prefetch (
        .clk(controller_clk),
        .rst(controller_rst),
        .start_valid(prefetch_start_valid),
        .start_ready(prefetch_start_ready),
        .start_pixel_address(22'd0),
        .active(prefetch_active),
        .complete(prefetch_complete),
        .fifo_write_level(scheduled_fifo_level),
        .fifo_write_valid(read_fifo_write_valid),
        .fifo_write_ready(read_fifo_write_ready),
        .fifo_write_data(read_fifo_write_data),
        .request_valid(prefetch_request_valid),
        .request_ready(prefetch_request_ready),
        .request_pixel_address(prefetch_request_address),
        .response_valid(adapter_response_valid),
        .response_ready(adapter_response_ready),
        .response_read_data(adapter_response_data)
    );

    framebuffer_arbiter #(
        .READ_FIFO_LOW_WATER(READ_FIFO_LOW_WATER),
        .MAX_CONSECUTIVE_WRITES(32)
    ) arbiter (
        .clk(controller_clk),
        .rst(controller_rst),
        .read_fifo_level(16'(scheduled_fifo_level)),
        .scanout_valid(buffered_read_valid),
        .scanout_ready(buffered_read_ready),
        .scanout_address({10'd0, buffered_read_address}),
        .write_valid(buffered_write_valid),
        .write_ready(buffered_write_ready),
        .write_address({10'd0, buffered_write_address}),
        .write_data(buffered_write_data),
        .refresh_valid(1'b0),
        .refresh_ready,
        .memory_valid(arbiter_memory_valid),
        .memory_ready(arbiter_memory_ready),
        .memory_operation(arbiter_memory_operation),
        .memory_address(arbiter_memory_address),
        .memory_write_data(arbiter_memory_write_data)
    );

    sdram_pixel_adapter adapter (
        .clk(controller_clk),
        .rst(controller_rst),
        .request_valid(arbiter_memory_valid && address_upper_zero),
        .request_ready(arbiter_memory_ready),
        .request_operation(arbiter_memory_operation),
        .request_pixel_address(arbiter_memory_address[21:0]),
        .request_write_data(arbiter_memory_write_data),
        .response_valid(adapter_response_valid),
        .response_ready(adapter_response_ready),
        .response_read_data(adapter_response_data),
        .write_committed(adapter_write_committed),
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

    async_fifo #(
        .WIDTH(16),
        .DEPTH(READ_FIFO_DEPTH),
        // This module is the only writer, and its scheduler reserves no more
        // than LOW_WATER + BURST slots (288 of 512 in hardware).
        .EXTERNAL_CAPACITY_CONTROL(1'b1)
    ) read_fifo (
        .write_clk(controller_clk),
        .write_rst(controller_rst),
        .write_valid(read_fifo_write_valid),
        .write_ready(read_fifo_write_ready),
        .write_data(read_fifo_write_data),
        .write_level(read_fifo_write_level),
        .read_clk(pixel_clk),
        .read_rst(pixel_rst),
        .read_valid(read_fifo_read_valid),
        .read_ready(read_fifo_read_ready),
        .read_data(read_fifo_read_data),
        .read_level(read_fifo_read_level)
    );

    always_ff @(posedge controller_clk) begin
        if (controller_rst) begin
            scheduled_fifo_level <= '0;
            buffered_read_valid <= 1'b0;
            buffered_read_address <= '0;
            buffered_write_valid <= 1'b0;
            buffered_write_address <= '0;
            buffered_write_data <= '0;
            initialization_started <= 1'b0;
            initialization_issued <= 1'b0;
            framebuffer_ready <= 1'b0;
        end else begin
            // Break the Gray-pointer decode/subtract path before arbitration.
            // framebuffer_read_prefetch waits one settle cycle after every
            // response, so this conservative pipeline cannot over-reserve.
            scheduled_fifo_level <= read_fifo_write_level;
            if (buffered_read_valid) begin
                if (buffered_read_ready)
                    buffered_read_valid <= 1'b0;
            end else if (prefetch_request_valid) begin
                    buffered_read_valid <= 1'b1;
                    buffered_read_address <= prefetch_request_address;
            end
            if (buffered_write_valid) begin
                if (buffered_write_ready)
                    buffered_write_valid <= 1'b0;
            end else if (queued_write_valid) begin
                buffered_write_valid <= 1'b1;
                buffered_write_address <= queued_write_address;
                buffered_write_data <= queued_write_data;
            end
            if (initializer_start_valid && initializer_start_ready)
                initialization_started <= 1'b1;
            if (initializer_complete)
                initialization_issued <= 1'b1;
            if (initialization_issued && !initialization_active &&
                write_queue_count == 0 && outstanding_write_count == 0 &&
                writes_committed && !refresh_ready)
                framebuffer_ready <= 1'b1;
        end
    end

    // The adapter spends multiple cycles on every request, so a deliberately
    // non-fall-through slot costs no useful throughput and completely breaks
    // the arbitration ready path. The prefetcher counts a request as
    // outstanding when this slot accepts it.
    assign prefetch_request_ready = !buffered_read_valid;
    assign queued_write_ready = !buffered_write_valid;

    always_ff @(posedge pixel_clk) begin
        if (pixel_rst) begin
            framebuffer_ready_sync1 <= 1'b0;
            framebuffer_ready_sync2 <= 1'b0;
            scanout_enabled <= 1'b0;
            scanout_underflow <= 1'b0;
        end else begin
            framebuffer_ready_sync1 <= framebuffer_ready;
            framebuffer_ready_sync2 <= framebuffer_ready_sync1;

            if (!scanout_enabled && vblank_start &&
                framebuffer_ready_sync2 && read_fifo_read_level != 0 &&
                read_fifo_read_valid)
                scanout_enabled <= 1'b1;

            if (scanout_enabled && active_video &&
                !read_fifo_read_valid)
                scanout_underflow <= 1'b1;
        end
    end

    always_comb begin
        address_upper_zero = arbiter_memory_address[31:22] == 0;
        read_fifo_read_ready = scanout_enabled && active_video;
        pixel = scanout_enabled && active_video && read_fifo_read_valid
              ? read_fifo_read_data : 16'h0000;
    end
endmodule
