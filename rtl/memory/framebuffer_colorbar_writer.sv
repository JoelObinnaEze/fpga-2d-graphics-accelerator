`timescale 1ns/1ps

// Emits one complete RGB565 color-bar frame as sequential pixel writes.
// The writer uses controller-domain valid/ready flow control and holds both
// address and data stable while stalled. complete is a one-cycle pulse after
// the final pixel is accepted; backend commitment is tracked separately by the
// framebuffer write queue.
module framebuffer_colorbar_writer #(
    parameter int unsigned FRAME_WIDTH = 640,
    parameter int unsigned FRAME_HEIGHT = 480
) (
    input  logic clk,
    input  logic rst,
    input  logic start_valid,
    output logic start_ready,
    input  logic [21:0] start_pixel_address,
    output logic write_valid,
    input  logic write_ready,
    output logic [21:0] write_pixel_address,
    output logic [15:0] write_data,
    output logic active,
    output logic complete
);
    localparam int unsigned X_WIDTH =
        FRAME_WIDTH < 2 ? 1 : $clog2(FRAME_WIDTH);
    localparam int unsigned Y_WIDTH =
        FRAME_HEIGHT < 2 ? 1 : $clog2(FRAME_HEIGHT);

    logic [X_WIDTH-1:0] x;
    logic [Y_WIDTH-1:0] y;

    initial begin
        if (FRAME_WIDTH == 0 || FRAME_HEIGHT == 0)
            $error("framebuffer dimensions must be greater than zero");
        if (FRAME_WIDTH * FRAME_HEIGHT > 4194304)
            $error("framebuffer exceeds the 22-bit pixel-address space");
    end

    always_comb begin
        start_ready = !active;
        write_valid = active;

        if      (int'(x) < FRAME_WIDTH * 1/8) write_data = 16'hffff;
        else if (int'(x) < FRAME_WIDTH * 2/8) write_data = 16'hffe0;
        else if (int'(x) < FRAME_WIDTH * 3/8) write_data = 16'h07ff;
        else if (int'(x) < FRAME_WIDTH * 4/8) write_data = 16'h07e0;
        else if (int'(x) < FRAME_WIDTH * 5/8) write_data = 16'hf81f;
        else if (int'(x) < FRAME_WIDTH * 6/8) write_data = 16'hf800;
        else if (int'(x) < FRAME_WIDTH * 7/8) write_data = 16'h001f;
        else                                       write_data = 16'h0000;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            x <= '0;
            y <= '0;
            write_pixel_address <= '0;
            active <= 1'b0;
            complete <= 1'b0;
        end else begin
            complete <= 1'b0;

            if (start_valid && start_ready) begin
                x <= '0;
                y <= '0;
                write_pixel_address <= start_pixel_address;
                active <= 1'b1;
            end else if (write_valid && write_ready) begin
                if (int'(x) == FRAME_WIDTH - 1 &&
                    int'(y) == FRAME_HEIGHT - 1) begin
                    active <= 1'b0;
                    complete <= 1'b1;
                end else begin
                    // Split the address carry so a full-width increment is not
                    // placed on the 162 MHz controller-domain critical path.
                    write_pixel_address[10:0] <=
                        write_pixel_address[10:0] + 1'b1;
                    if (write_pixel_address[10:0] == 11'h7ff)
                        write_pixel_address[21:11] <=
                            write_pixel_address[21:11] + 1'b1;
                    if (int'(x) == FRAME_WIDTH - 1) begin
                        x <= '0;
                        y <= y + 1'b1;
                    end else begin
                        x <= x + 1'b1;
                    end
                end
            end
        end
    end
endmodule
