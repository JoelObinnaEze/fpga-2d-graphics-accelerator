`timescale 1ns/1ps

module tb_framebuffer_read_prefetch;
    localparam int unsigned FRAME_PIXELS = 12;
    localparam int unsigned FIFO_DEPTH = 8;
    localparam int unsigned FIFO_LOW_WATER = 3;
    localparam int unsigned BURST_PIXELS = 6;
    localparam int unsigned CAPACITY_LIMITED_BURST =
        ((FIFO_DEPTH - FIFO_LOW_WATER) / 2) * 2;
    localparam int unsigned FIFO_LEVEL_WIDTH = $clog2(FIFO_DEPTH + 1);
    // Cross the split-counter carry boundary (4095 -> 4096).
    localparam logic [21:0] BASE_ADDRESS = 22'd4090;

    logic clk;
    logic rst;
    logic start_valid;
    logic start_ready;
    logic [21:0] start_pixel_address;
    logic active;
    logic complete;
    logic [FIFO_LEVEL_WIDTH-1:0] fifo_write_level;
    logic fifo_write_valid;
    logic fifo_write_ready;
    logic [15:0] fifo_write_data;
    logic request_valid;
    logic request_ready;
    logic [21:0] request_pixel_address;
    logic response_valid;
    logic response_ready;
    logic [31:0] response_read_data;

    int unsigned accepted_requests;
    int unsigned accepted_words;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    framebuffer_read_prefetch #(
        .FRAME_PIXELS(FRAME_PIXELS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_LOW_WATER(FIFO_LOW_WATER),
        .BURST_PIXELS(BURST_PIXELS)
    ) dut (
        .clk,
        .rst,
        .start_valid,
        .start_ready,
        .start_pixel_address,
        .active,
        .complete,
        .fifo_write_level,
        .fifo_write_valid,
        .fifo_write_ready,
        .fifo_write_data,
        .request_valid,
        .request_ready,
        .request_pixel_address,
        .response_valid,
        .response_ready,
        .response_read_data
    );

    task automatic accept_request(input logic [21:0] expected_address);
        @(negedge clk);
        while (!request_valid)
            @(negedge clk);
        if (request_pixel_address != expected_address)
            $fatal(1, "request address mismatch: expected %0d got %0d",
                   expected_address, request_pixel_address);
        request_ready = 1'b1;
        @(posedge clk);
        #1;
        request_ready = 1'b0;
        accepted_requests++;
    endtask

    task automatic return_word(
        input int unsigned first_pixel,
        input bit stall_fifo
    );
        @(negedge clk);
        if (stall_fifo)
            fifo_write_ready = 1'b0;
        response_read_data = {
            16'h8000 + 16'(first_pixel + 1),
            16'h8000 + 16'(first_pixel)
        };
        response_valid = 1'b1;
        #1;
        if (!response_ready || fifo_write_valid)
            $fatal(1, "packed response was not accepted into an empty unpack buffer");
        @(posedge clk);
        #1;
        response_valid = 1'b0;
        accepted_words++;

        if (stall_fifo) begin
            repeat (3) begin
                @(posedge clk);
                #1;
                if (!fifo_write_valid ||
                    fifo_write_data != 16'h8000 + 16'(first_pixel))
                    $fatal(1, "lower pixel was not held during FIFO stall");
            end
            @(negedge clk);
            fifo_write_ready = 1'b1;
        end else begin
            @(negedge clk);
        end

        for (int half = 0; half < 2; half++) begin
            if (!fifo_write_valid ||
                fifo_write_data != 16'h8000 + 16'(first_pixel + half))
                $fatal(1, "unpacked pixel mismatch at pixel %0d: got %04x",
                       first_pixel + half, fifo_write_data);
            @(posedge clk);
            #1;
            fifo_write_level =
                FIFO_LEVEL_WIDTH'(int'(fifo_write_level) + 1);
            if (half == 0)
                @(negedge clk);
        end
    endtask

    initial begin
        rst = 1'b1;
        start_valid = 1'b0;
        start_pixel_address = BASE_ADDRESS;
        fifo_write_level = '0;
        fifo_write_ready = 1'b1;
        request_ready = 1'b0;
        response_valid = 1'b0;
        response_read_data = '0;
        accepted_requests = 0;
        accepted_words = 0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        @(negedge clk);
        if (!start_ready)
            $fatal(1, "prefetcher was not ready after reset");
        start_valid = 1'b1;
        @(posedge clk);
        #1;
        start_valid = 1'b0;
        if (!active || start_ready)
            $fatal(1, "prefetcher did not become active");

        while (!request_valid)
            @(negedge clk);
        if (request_pixel_address != BASE_ADDRESS)
            $fatal(1, "first request did not use the supplied base address");
        repeat (3) begin
            @(posedge clk);
            #1;
            if (!request_valid || request_pixel_address != BASE_ADDRESS)
                $fatal(1, "request changed while backend was stalled");
        end

        for (int i = 0; i < BURST_PIXELS / 2; i++)
            accept_request(BASE_ADDRESS + 22'(2 * i));

        @(negedge clk);
        if (request_valid)
            $fatal(1, "prefetcher exceeded the configured burst length");

        for (int i = 0; i < BURST_PIXELS; i += 2)
            return_word(i, i == 0);

        repeat (3) @(posedge clk);
        if (request_valid)
            $fatal(1, "prefetcher refilled above the low-water mark");

        fifo_write_level = FIFO_LEVEL_WIDTH'(FIFO_LOW_WATER);
        for (int i = BURST_PIXELS;
             i < BURST_PIXELS + CAPACITY_LIMITED_BURST; i += 2)
            accept_request(BASE_ADDRESS + 22'(i));
        @(negedge clk);
        if (request_valid)
            $fatal(1, "prefetcher overcommitted the available FIFO slots");
        for (int i = BURST_PIXELS;
             i < BURST_PIXELS + CAPACITY_LIMITED_BURST; i += 2)
            return_word(i, 1'b0);

        repeat (3) @(posedge clk);
        if (request_valid)
            $fatal(1, "prefetcher refilled before capacity was available");

        fifo_write_level = FIFO_LEVEL_WIDTH'(FIFO_LOW_WATER);
        for (int i = BURST_PIXELS + CAPACITY_LIMITED_BURST;
             i < FRAME_PIXELS; i += 2)
            accept_request(BASE_ADDRESS + 22'(i));
        for (int i = BURST_PIXELS + CAPACITY_LIMITED_BURST;
             i < FRAME_PIXELS; i += 2) begin
            return_word(i, 1'b0);
            if (i != FRAME_PIXELS - 2 && complete)
                $fatal(1, "prefetcher completed before the final response");
        end

        if (!complete || active || !start_ready)
            $fatal(1, "prefetcher did not complete on the final FIFO transfer");
        if (accepted_requests != FRAME_PIXELS / 2 ||
            accepted_words != FRAME_PIXELS / 2)
            $fatal(1, "prefetch count mismatch: requests=%0d words=%0d",
                   accepted_requests, accepted_words);

        @(posedge clk);
        #1;
        if (complete)
            $fatal(1, "complete must be a one-cycle pulse");

        $display("PASS: bounded packed-word prefetch, unpacking, stalls, and completion");
        $finish;
    end
endmodule
