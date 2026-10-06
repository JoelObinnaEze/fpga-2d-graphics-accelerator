`timescale 1ns/1ps

module framebuffer_bram #(
    parameter int unsigned FRAME_WIDTH  = 64,
    parameter int unsigned FRAME_HEIGHT = 48
) (
    input  logic clk,
    input  logic write_valid,
    input  logic [$clog2(FRAME_WIDTH)-1:0] write_x,
    input  logic [$clog2(FRAME_HEIGHT)-1:0] write_y,
    input  logic [15:0] write_pixel,
    input  logic read_valid,
    input  logic [$clog2(FRAME_WIDTH)-1:0] read_x,
    input  logic [$clog2(FRAME_HEIGHT)-1:0] read_y,
    output logic read_pixel_valid,
    output logic [15:0] read_pixel
);
    logic [15:0] memory [0:FRAME_WIDTH * FRAME_HEIGHT - 1];

    always_ff @(posedge clk) begin
        if (write_valid && int'(write_x) < FRAME_WIDTH &&
                           int'(write_y) < FRAME_HEIGHT) begin
            memory[int'(write_y) * FRAME_WIDTH + int'(write_x)] <= write_pixel;
        end

        read_pixel_valid <= read_valid && int'(read_x) < FRAME_WIDTH &&
                                         int'(read_y) < FRAME_HEIGHT;
        if (read_valid && int'(read_x) < FRAME_WIDTH &&
                          int'(read_y) < FRAME_HEIGHT) begin
            read_pixel <= memory[int'(read_y) * FRAME_WIDTH + int'(read_x)];
        end
    end
endmodule
