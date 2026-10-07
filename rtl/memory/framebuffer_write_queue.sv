`timescale 1ns/1ps

// Controller-clock-domain renderer write queue.
//
// Renderer writes enter in pixel-address units and leave in order for the
// framebuffer arbiter. A dequeued write remains outstanding until the SDRAM
// adapter pulses backend_write_committed. writes_committed is therefore a
// frame-presentation fence, not merely a FIFO-empty indication.
module framebuffer_write_queue #(
    parameter int unsigned FIFO_DEPTH = 64,
    parameter int unsigned MAX_OUTSTANDING_WRITES = 2
) (
    input  logic clk,
    input  logic rst,
    input  logic write_valid,
    output logic write_ready,
    input  logic [21:0] write_pixel_address,
    input  logic [15:0] write_data,
    output logic arbiter_valid,
    input  logic arbiter_ready,
    output logic [21:0] arbiter_pixel_address,
    output logic [15:0] arbiter_write_data,
    input  logic backend_write_committed,
    output logic writes_committed,
    output logic [$clog2(FIFO_DEPTH + 1)-1:0] queue_count,
    output logic [$clog2(MAX_OUTSTANDING_WRITES + 1)-1:0]
        outstanding_count,
    output logic protocol_error
);
    localparam int unsigned ENTRY_WIDTH = 22 + 16;

    logic fifo_valid;
    logic fifo_ready;
    logic [ENTRY_WIDTH-1:0] fifo_data;
    logic can_issue;
    logic dequeue_fire;

    initial begin
        if (FIFO_DEPTH < 2)
            $error("framebuffer_write_queue FIFO_DEPTH must be at least two");
        if (MAX_OUTSTANDING_WRITES == 0)
            $error("MAX_OUTSTANDING_WRITES must be greater than zero");
    end

    sync_fifo #(
        .WIDTH(ENTRY_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) queue (
        .clk,
        .rst,
        .in_valid(write_valid),
        .in_ready(write_ready),
        .in_data({write_pixel_address, write_data}),
        .out_valid(fifo_valid),
        .out_ready(fifo_ready),
        .out_data(fifo_data),
        .count(queue_count)
    );

    always_comb begin
        // A completion in this cycle may be replaced by a newly issued write.
        can_issue = int'(outstanding_count) < MAX_OUTSTANDING_WRITES ||
                    backend_write_committed;
        arbiter_valid = fifo_valid && can_issue;
        arbiter_pixel_address = fifo_data[ENTRY_WIDTH-1:16];
        arbiter_write_data = fifo_data[15:0];
        fifo_ready = arbiter_ready && can_issue;
        dequeue_fire = fifo_valid && fifo_ready;
        writes_committed = queue_count == 0 && outstanding_count == 0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            outstanding_count <= '0;
            protocol_error <= 1'b0;
        end else begin
            if (backend_write_committed && outstanding_count == 0 &&
                !dequeue_fire) begin
                protocol_error <= 1'b1;
                outstanding_count <= outstanding_count;
            end else begin
                case ({dequeue_fire, backend_write_committed})
                    2'b10: outstanding_count <= outstanding_count + 1'b1;
                    2'b01: outstanding_count <= outstanding_count - 1'b1;
                    default: outstanding_count <= outstanding_count;
                endcase
            end
        end
    end
endmodule
