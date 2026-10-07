`timescale 1ns/1ps

// Controller-clock-domain framebuffer reader.
//
// A start transfer schedules FRAME_PIXELS sequential RGB565 pixel reads from
// start_pixel_address. Reads are grouped into bounded logical bursts. A new
// burst starts only after the previous burst has drained and FIFO occupancy is
// at or below FIFO_LOW_WATER. When the low-water mark plus a full burst fits,
// that static bound reserves every delayed response slot; smaller FIFOs also
// receive an exact capacity check.
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
    input  logic [15:0] response_read_data
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
    logic [FRAME_COUNT_WIDTH-1:0] responses_received;
    logic [BURST_COUNT_WIDTH-1:0] burst_remaining;
    logic [OUTSTANDING_WIDTH-1:0] outstanding_reads;
    logic outstanding_empty;
    logic request_fire;
    logic response_fire;
    logic level_settling;
    int unsigned reserved_slots;
    int unsigned available_slots;
    int unsigned planned_burst;

    initial begin
        if (FRAME_PIXELS == 0)
            $error("FRAME_PIXELS must be greater than zero");
        if (FIFO_DEPTH < 2)
            $error("FIFO_DEPTH must be at least two");
        if (FIFO_LOW_WATER >= FIFO_DEPTH)
            $error("FIFO_LOW_WATER must be below FIFO_DEPTH");
        if (BURST_PIXELS == 0 || BURST_PIXELS > FIFO_DEPTH)
            $error("BURST_PIXELS must be between one and FIFO_DEPTH");
    end

    always_comb begin
        reserved_slots = int'(fifo_write_level) + int'(outstanding_reads);
        if (reserved_slots >= FIFO_DEPTH)
            available_slots = 0;
        else
            available_slots = FIFO_DEPTH - reserved_slots;

        planned_burst = BURST_PIXELS;
        if (!FULL_BURSTS_ONLY && planned_burst > int'(pixels_remaining))
            planned_burst = int'(pixels_remaining);
        if (CAPACITY_CHECK_REQUIRED && planned_burst > available_slots)
            planned_burst = available_slots;

        start_ready = !active;
        request_valid = active && state == ISSUE_BURST &&
                        burst_remaining != 0 &&
                        (!CAPACITY_CHECK_REQUIRED || available_slots != 0);
        request_pixel_address = next_pixel_address;
        response_ready = active && fifo_write_ready;
        fifo_write_valid = active && response_valid;
        fifo_write_data = response_read_data;
        request_fire = request_valid && request_ready;
        response_fire = response_valid && response_ready;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            active <= 1'b0;
            complete <= 1'b0;
            next_pixel_address <= '0;
            pixels_remaining <= '0;
            responses_received <= '0;
            burst_remaining <= '0;
            outstanding_reads <= '0;
            outstanding_empty <= 1'b1;
            level_settling <= 1'b0;
        end else begin
            complete <= 1'b0;
            level_settling <= response_fire;

            if (start_valid && start_ready) begin
                state <= WAIT_REFILL;
                active <= 1'b1;
                next_pixel_address <= start_pixel_address;
                pixels_remaining <= FRAME_COUNT_WIDTH'(FRAME_PIXELS);
                responses_received <= '0;
                burst_remaining <= '0;
                outstanding_reads <= '0;
                outstanding_empty <= 1'b1;
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
                            // Pixel addresses increment every request, but the
                            // word portion increments only after an odd pixel.
                            // Splitting its carry at bit 11 keeps this counter
                            // off the long 162 MHz carry path.
                            next_pixel_address[0] <=
                                ~next_pixel_address[0];
                            if (next_pixel_address[0]) begin
                                next_pixel_address[11:1] <=
                                    next_pixel_address[11:1] + 1'b1;
                                if (next_pixel_address[11:1] == 11'h7ff)
                                    next_pixel_address[21:12] <=
                                        next_pixel_address[21:12] + 1'b1;
                            end
                            pixels_remaining <= pixels_remaining - 1'b1;
                            burst_remaining <= burst_remaining - 1'b1;
                            if (burst_remaining == 1)
                                state <= WAIT_REFILL;
                        end
                    end

                    default: state <= IDLE;
                endcase

                if (response_fire) begin
                    responses_received <= responses_received + 1'b1;
                    if (responses_received ==
                        FRAME_COUNT_WIDTH'(FRAME_PIXELS - 1)) begin
                        state <= IDLE;
                        active <= 1'b0;
                        complete <= 1'b1;
                    end
                end

                case ({request_fire, response_fire})
                    2'b10: begin
                        outstanding_reads <= outstanding_reads + 1'b1;
                        outstanding_empty <= 1'b0;
                    end
                    2'b01: begin
                        outstanding_reads <= outstanding_reads - 1'b1;
                        if (outstanding_reads == 1)
                            outstanding_empty <= 1'b1;
                    end
                    default: begin
                        outstanding_reads <= outstanding_reads;
                        outstanding_empty <= outstanding_empty;
                    end
                endcase
            end
        end
    end
endmodule
