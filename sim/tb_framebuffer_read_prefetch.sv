`timescale 1ns/1ps

module tb_framebuffer_read_prefetch;
    localparam int unsigned FRAME_PIXELS = 12;
    localparam int unsigned FIFO_DEPTH = 8;
    localparam int unsigned FIFO_LOW_WATER = 4;
    localparam int unsigned BURST_PIXELS = 6;
    localparam int unsigned FIFO_WORD_DEPTH = FIFO_DEPTH / 2;
    localparam int unsigned FIFO_LEVEL_WIDTH =
        $clog2(FIFO_WORD_DEPTH + 1);
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
    logic [31:0] fifo_write_data;
    logic request_valid;
    logic request_ready;
    logic [21:0] request_pixel_address;
    logic [7:0] request_data_len;
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
        .request_data_len,
        .response_valid,
        .response_ready,
        .response_read_data
    );

    task automatic accept_request(
        input logic [21:0] expected_address,
        input logic [7:0] expected_data_len
    );
        @(negedge clk);
        while (!request_valid)
            @(negedge clk);
        if (request_pixel_address != expected_address ||
            request_data_len != expected_data_len)
            $fatal(1,
                   "request mismatch: expected address/len %0d/%0d got %0d/%0d",
                   expected_address, expected_data_len,
                   request_pixel_address, request_data_len);
        request_ready = 1'b1;
        @(posedge clk);
        #1;
        request_ready = 1'b0;
        accepted_requests++;
    endtask

    task automatic return_burst(
        input int unsigned first_pixel,
        input int unsigned pixel_count,
        input bit stall_first_word
    );
        for (int word_index = 0; word_index < pixel_count / 2;
             word_index++) begin
            @(negedge clk);
            response_read_data = {
                16'h8000 + 16'(first_pixel + 2 * word_index + 1),
                16'h8000 + 16'(first_pixel + 2 * word_index)
            };
            response_valid = 1'b1;

            if (stall_first_word && word_index == 0) begin
                fifo_write_ready = 1'b0;
                repeat (3) begin
                    @(posedge clk);
                    #1;
                    if (response_ready || !fifo_write_valid ||
                        fifo_write_data != response_read_data)
                        $fatal(1,
                               "response was not held while the word FIFO stalled");
                end
                @(negedge clk);
                fifo_write_ready = 1'b1;
            end

            #1;
            if (!response_ready || !fifo_write_valid ||
                fifo_write_data != response_read_data)
                $fatal(1, "word FIFO did not accept burst word %0d",
                       word_index);
            @(posedge clk);
            #1;
            accepted_words++;
            fifo_write_level =
                FIFO_LEVEL_WIDTH'(int'(fifo_write_level) + 1);
        end

        @(negedge clk);
        response_valid = 1'b0;
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
        if (request_pixel_address != BASE_ADDRESS || request_data_len != 2)
            $fatal(1, "first request did not describe the six-pixel burst");
        repeat (3) begin
            @(posedge clk);
            #1;
            if (!request_valid || request_pixel_address != BASE_ADDRESS ||
                request_data_len != 2)
                $fatal(1, "request changed while backend was stalled");
        end

        accept_request(BASE_ADDRESS, 8'd2);
        @(negedge clk);
        if (request_valid)
            $fatal(1, "prefetcher issued another command before burst data");
        return_burst(0, 6, 1'b1);

        repeat (3) @(posedge clk);
        if (request_valid)
            $fatal(1, "prefetcher refilled above the low-water mark");

        fifo_write_level = FIFO_LEVEL_WIDTH'(FIFO_LOW_WATER / 2);
        accept_request(BASE_ADDRESS + 22'd6, 8'd1);
        return_burst(6, 4, 1'b0);

        repeat (3) @(posedge clk);
        if (request_valid)
            $fatal(1, "prefetcher refilled before capacity was available");

        fifo_write_level = FIFO_LEVEL_WIDTH'(FIFO_LOW_WATER / 2);
        accept_request(BASE_ADDRESS + 22'd10, 8'd0);
        return_burst(10, 2, 1'b0);

        if (!complete || active || !start_ready)
            $fatal(1, "prefetcher did not complete on the final burst word");
        if (accepted_requests != 3 || accepted_words != FRAME_PIXELS / 2)
            $fatal(1, "prefetch count mismatch: requests=%0d words=%0d",
                   accepted_requests, accepted_words);

        @(posedge clk);
        #1;
        if (complete)
            $fatal(1, "complete must be a one-cycle pulse");

        $display("PASS: bounded SDRAM burst prefetch, stalls, and completion");
        $finish;
    end
endmodule
