`timescale 1ns/1ps

// Controller-clock-domain framebuffer burst reader.
//
// A start transfer schedules FRAME_PIXELS sequential RGB565 pixels from an
// even start_pixel_address. Each request covers one bounded burst of packed
// 32-bit words, and every response word is written directly to a 32-bit
// asynchronous FIFO. FIFO_DEPTH, FIFO_LOW_WATER, and BURST_PIXELS remain in
// pixel units; the connected FIFO stores half as many packed words.
//
// The scheduler reserves a whole burst before issuing it. This is required
// because the SDRAM controller cannot be backpressured once its consecutive
// read-valid beats begin. complete pulses after the final response word enters
// the FIFO. All signals in this module use clk/rst.
module framebuffer_read_prefetch #(
    parameter int unsigned FRAME_PIXELS = 640 * 480,
    parameter int unsigned FIFO_DEPTH = 512,
    parameter int unsigned FIFO_LOW_WATER = 256,
    parameter int unsigned BURST_PIXELS = 32
) (
    input  logic clk,
    input  logic rst,
    input  logic start_valid,
    output logic start_ready,
    input  logic [21:0] start_pixel_address,
    output logic active,
    output logic complete,
    input  logic [$clog2(FIFO_DEPTH / 2 + 1)-1:0] fifo_write_level,
    output logic fifo_write_valid,
    input  logic fifo_write_ready,
    output logic [31:0] fifo_write_data,
    output logic request_valid,
    input  logic request_ready,
    output logic [21:0] request_pixel_address,
    output logic [7:0] request_data_len,
    input  logic response_valid,
    output logic response_ready,
    input  logic [31:0] response_read_data
);
    localparam int unsigned FRAME_COUNT_WIDTH =
        FRAME_PIXELS < 2 ? 1 : $clog2(FRAME_PIXELS + 1);
    localparam int unsigned BURST_COUNT_WIDTH =
        BURST_PIXELS < 2 ? 1 : $clog2(BURST_PIXELS + 1);
    localparam int unsigned BURST_WORDS = BURST_PIXELS / 2;
    localparam int unsigned BURST_WORD_COUNT_WIDTH =
        BURST_WORDS < 2 ? 1 : $clog2(BURST_WORDS + 1);
    localparam bit CAPACITY_CHECK_REQUIRED =
        FIFO_LOW_WATER + BURST_PIXELS > FIFO_DEPTH;

    typedef enum logic [2:0] {
        IDLE,
        WAIT_REFILL,
        ISSUE_REQUEST,
        RECEIVE_BURST
    } state_t;

    state_t state;
    logic [20:0] next_word_address;
    logic [FRAME_COUNT_WIDTH-1:0] pixels_remaining;
    logic [FRAME_COUNT_WIDTH-1:0] pixels_written;
    logic [BURST_COUNT_WIDTH-1:0] request_burst_pixels;
    logic [BURST_WORD_COUNT_WIDTH-1:0] request_burst_words;
    logic [BURST_WORD_COUNT_WIDTH-1:0] burst_words_remaining;
    logic [11:0] next_word_low_sum;
    logic request_fire;
    logic response_fire;
    logic level_settling;
    int unsigned fifo_level_pixels;
    int unsigned available_pixels;
    int unsigned planned_burst;

    initial begin
        if (FRAME_PIXELS == 0 || FRAME_PIXELS % 2 != 0)
            $error("FRAME_PIXELS must be nonzero and even");
        if (FIFO_DEPTH < 8 || FIFO_DEPTH % 2 != 0 ||
            (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0)
            $error("FIFO_DEPTH must be an even power of two of at least eight");
        if (FIFO_LOW_WATER >= FIFO_DEPTH || FIFO_LOW_WATER % 2 != 0)
            $error("FIFO_LOW_WATER must be even and below FIFO_DEPTH");
        if (BURST_PIXELS < 2 || BURST_PIXELS > FIFO_DEPTH ||
            BURST_PIXELS > 512 || BURST_PIXELS % 2 != 0)
            $error("BURST_PIXELS must be even and between two and 512");
    end

    always_comb begin
        fifo_level_pixels = int'(fifo_write_level) * 2;
        if (fifo_level_pixels >= FIFO_DEPTH)
            available_pixels = 0;
        else
            available_pixels = FIFO_DEPTH - fifo_level_pixels;

        planned_burst = BURST_PIXELS;
        if (planned_burst > int'(pixels_remaining))
            planned_burst = int'(pixels_remaining);
        if (CAPACITY_CHECK_REQUIRED && planned_burst > available_pixels)
            planned_burst = available_pixels;
        planned_burst = (planned_burst / 2) * 2;

        start_ready = !active && !start_pixel_address[0];
        request_valid = active && state == ISSUE_REQUEST;
        request_pixel_address = {next_word_address, 1'b0};
        if (request_burst_words == 0)
            request_data_len = 8'd0;
        else
            request_data_len = 8'(int'(request_burst_words) - 1);

        response_ready = active && state == RECEIVE_BURST &&
                         fifo_write_ready;
        fifo_write_valid = active && state == RECEIVE_BURST &&
                           response_valid;
        fifo_write_data = response_read_data;

        request_fire = request_valid && request_ready;
        response_fire = response_valid && response_ready;
        next_word_low_sum = {1'b0, next_word_address[10:0]} +
                            12'(request_burst_words);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            active <= 1'b0;
            complete <= 1'b0;
            next_word_address <= '0;
            pixels_remaining <= '0;
            pixels_written <= '0;
            request_burst_pixels <= '0;
            request_burst_words <= '0;
            burst_words_remaining <= '0;
            level_settling <= 1'b0;
        end else begin
            complete <= 1'b0;
            level_settling <= response_fire;

            if (start_valid && start_ready) begin
                state <= WAIT_REFILL;
                active <= 1'b1;
                next_word_address <= start_pixel_address[21:1];
                pixels_remaining <= FRAME_COUNT_WIDTH'(FRAME_PIXELS);
                pixels_written <= '0;
                request_burst_pixels <= '0;
                request_burst_words <= '0;
                burst_words_remaining <= '0;
            end else if (active) begin
                case (state)
                    WAIT_REFILL: begin
                        if (!level_settling &&
                            fifo_level_pixels <= FIFO_LOW_WATER &&
                            planned_burst != 0) begin
                            request_burst_pixels <=
                                BURST_COUNT_WIDTH'(planned_burst);
                            request_burst_words <=
                                BURST_WORD_COUNT_WIDTH'(planned_burst / 2);
                            state <= ISSUE_REQUEST;
                        end
                    end

                    ISSUE_REQUEST: begin
                        if (request_fire) begin
                            next_word_address[10:0] <=
                                next_word_low_sum[10:0];
                            if (next_word_low_sum[11])
                                next_word_address[20:11] <=
                                    next_word_address[20:11] + 1'b1;
                            pixels_remaining <= pixels_remaining -
                                FRAME_COUNT_WIDTH'(request_burst_pixels);
                            burst_words_remaining <= request_burst_words;
                            state <= RECEIVE_BURST;
                        end
                    end

                    RECEIVE_BURST: begin
                        if (response_fire) begin
                            pixels_written <= pixels_written +
                                              FRAME_COUNT_WIDTH'(2);
                            burst_words_remaining <=
                                burst_words_remaining - 1'b1;

                            if (burst_words_remaining == 1) begin
                                if (pixels_written ==
                                    FRAME_COUNT_WIDTH'(FRAME_PIXELS - 2)) begin
                                    state <= IDLE;
                                    active <= 1'b0;
                                    complete <= 1'b1;
                                end else begin
                                    state <= WAIT_REFILL;
                                end
                            end
                        end
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
