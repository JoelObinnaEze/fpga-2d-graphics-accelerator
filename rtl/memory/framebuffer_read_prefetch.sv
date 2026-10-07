`timescale 1ns/1ps

// Controller-clock-domain framebuffer reader.
//
// A start transfer schedules FRAME_PIXELS sequential RGB565 pixels from an
// even start_pixel_address. Each SDRAM request fetches one packed 32-bit word;
// its lower and upper RGB565 halves are written to the FIFO on consecutive
// transfers. Reads are grouped into bounded, even-sized logical bursts. A new
// burst starts only after the previous burst has drained and FIFO occupancy is
// at or below FIFO_LOW_WATER. When the low-water mark plus a full burst fits,
// that static bound reserves every delayed pixel slot; smaller FIFOs also
// receive an exact capacity check rounded down to a whole packed word.
//
// All request, response, and FIFO signals use valid/ready transfers. Payloads
// remain stable while stalled. complete pulses only after the final response is
// accepted by the FIFO. Both the scheduler and FIFO write side use clk/rst.
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
    input  logic [$clog2(FIFO_DEPTH + 1)-1:0] fifo_write_level,
    output logic fifo_write_valid,
    input  logic fifo_write_ready,
    output logic [15:0] fifo_write_data,
    output logic request_valid,
    input  logic request_ready,
    output logic [21:0] request_pixel_address,
    input  logic response_valid,
    output logic response_ready,
    input  logic [31:0] response_read_data
);
    localparam int unsigned FRAME_COUNT_WIDTH =
        FRAME_PIXELS < 2 ? 1 : $clog2(FRAME_PIXELS + 1);
    localparam int unsigned BURST_COUNT_WIDTH =
        BURST_PIXELS < 2 ? 1 : $clog2(BURST_PIXELS + 1);
    localparam int unsigned OUTSTANDING_WIDTH =
        FIFO_DEPTH < 2 ? 1 : $clog2(FIFO_DEPTH + 1);
    localparam bit CAPACITY_CHECK_REQUIRED =
        FIFO_LOW_WATER + BURST_PIXELS > FIFO_DEPTH;
    localparam bit FULL_BURSTS_ONLY = FRAME_PIXELS % BURST_PIXELS == 0;

    typedef enum logic [1:0] {
        IDLE,
        WAIT_REFILL,
        ISSUE_BURST
    } state_t;

    state_t state;
    logic [21:0] next_pixel_address;
    logic [FRAME_COUNT_WIDTH-1:0] pixels_remaining;
    logic [FRAME_COUNT_WIDTH-1:0] pixels_written;
    logic [BURST_COUNT_WIDTH-1:0] burst_remaining;
    logic [OUTSTANDING_WIDTH-1:0] outstanding_pixels;
    logic outstanding_empty;
    logic request_fire;
    logic response_fire;
    logic fifo_write_fire;
    logic level_settling;
    logic unpack_valid;
    logic unpack_upper;
    logic [31:0] unpack_word;
    int unsigned reserved_slots;
    int unsigned available_slots;
    int unsigned planned_burst;

    initial begin
        if (FRAME_PIXELS == 0)
            $error("FRAME_PIXELS must be greater than zero");
        if (FRAME_PIXELS % 2 != 0)
            $error("FRAME_PIXELS must be even for packed-word reads");
        if (FIFO_DEPTH < 2)
            $error("FIFO_DEPTH must be at least two");
        if (FIFO_LOW_WATER >= FIFO_DEPTH)
            $error("FIFO_LOW_WATER must be below FIFO_DEPTH");
        if (BURST_PIXELS < 2 || BURST_PIXELS > FIFO_DEPTH ||
            BURST_PIXELS % 2 != 0)
            $error("BURST_PIXELS must be even and between two and FIFO_DEPTH");
    end

    always_comb begin
        reserved_slots = int'(fifo_write_level) + int'(outstanding_pixels);
        if (reserved_slots >= FIFO_DEPTH)
            available_slots = 0;
        else
            available_slots = FIFO_DEPTH - reserved_slots;

        planned_burst = BURST_PIXELS;
        if (!FULL_BURSTS_ONLY && planned_burst > int'(pixels_remaining))
            planned_burst = int'(pixels_remaining);
        if (CAPACITY_CHECK_REQUIRED && planned_burst > available_slots)
            planned_burst = available_slots;
        planned_burst = (planned_burst / 2) * 2;

        start_ready = !active;
        request_valid = active && state == ISSUE_BURST &&
                        burst_remaining != 0 &&
                        (!CAPACITY_CHECK_REQUIRED || available_slots != 0);
        request_pixel_address = next_pixel_address;
        response_ready = active && !unpack_valid &&
                         outstanding_pixels != 0;
        fifo_write_valid = active && unpack_valid;
        fifo_write_data = unpack_upper ? unpack_word[31:16]
                                       : unpack_word[15:0];
        request_fire = request_valid && request_ready;
        response_fire = response_valid && response_ready;
        fifo_write_fire = fifo_write_valid && fifo_write_ready;
        outstanding_empty = outstanding_pixels == 0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            active <= 1'b0;
            complete <= 1'b0;
            next_pixel_address <= '0;
            pixels_remaining <= '0;
            pixels_written <= '0;
            burst_remaining <= '0;
            outstanding_pixels <= '0;
            level_settling <= 1'b0;
            unpack_valid <= 1'b0;
            unpack_upper <= 1'b0;
            unpack_word <= '0;
        end else begin
            complete <= 1'b0;
            level_settling <= fifo_write_fire;

            if (start_valid && start_ready) begin
                state <= WAIT_REFILL;
                active <= 1'b1;
                next_pixel_address <= start_pixel_address;
                pixels_remaining <= FRAME_COUNT_WIDTH'(FRAME_PIXELS);
                pixels_written <= '0;
                burst_remaining <= '0;
                outstanding_pixels <= '0;
                unpack_valid <= 1'b0;
                unpack_upper <= 1'b0;
            end else if (active) begin
                case (state)
                    WAIT_REFILL: begin
                        if (outstanding_empty &&
                            !level_settling &&
                            int'(fifo_write_level) <= FIFO_LOW_WATER &&
                            planned_burst != 0) begin
                            burst_remaining <=
                                BURST_COUNT_WIDTH'(planned_burst);
                            state <= ISSUE_BURST;
                        end
                    end

                    ISSUE_BURST: begin
                        if (request_fire) begin
                            // One request advances one packed SDRAM word, or
                            // two pixels. Splitting the word-address carry at
                            // bit 11 keeps it off the long 162 MHz carry path.
                            next_pixel_address[11:1] <=
                                next_pixel_address[11:1] + 1'b1;
                            if (next_pixel_address[11:1] == 11'h7ff)
                                next_pixel_address[21:12] <=
                                    next_pixel_address[21:12] + 1'b1;
                            pixels_remaining <= pixels_remaining -
                                                FRAME_COUNT_WIDTH'(2);
                            burst_remaining <= burst_remaining -
                                               BURST_COUNT_WIDTH'(2);
                            if (burst_remaining <= BURST_COUNT_WIDTH'(2))
                                state <= WAIT_REFILL;
                        end
                    end

                    default: state <= IDLE;
                endcase

                if (response_fire) begin
                    unpack_valid <= 1'b1;
                    unpack_upper <= 1'b0;
                    unpack_word <= response_read_data;
                end

                if (fifo_write_fire) begin
                    pixels_written <= pixels_written + 1'b1;
                    if (unpack_upper)
                        unpack_valid <= 1'b0;
                    else
                        unpack_upper <= 1'b1;

                    if (pixels_written ==
                        FRAME_COUNT_WIDTH'(FRAME_PIXELS - 1)) begin
                        state <= IDLE;
                        active <= 1'b0;
                        complete <= 1'b1;
                    end
                end

                case ({request_fire, fifo_write_fire})
                    2'b10: begin
                        outstanding_pixels <= outstanding_pixels +
                                              OUTSTANDING_WIDTH'(2);
                    end
                    2'b01: begin
                        outstanding_pixels <= outstanding_pixels - 1'b1;
                    end
                    2'b11: outstanding_pixels <= outstanding_pixels + 1'b1;
                    default: outstanding_pixels <= outstanding_pixels;
                endcase
            end
        end
    end
endmodule
