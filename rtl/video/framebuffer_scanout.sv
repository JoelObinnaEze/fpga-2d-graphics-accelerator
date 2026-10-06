`timescale 1ns/1ps

module framebuffer_scanout #(
    parameter int unsigned FRAME_WIDTH  = 640,
    parameter int unsigned FRAME_HEIGHT = 480
) (
    input  logic clk,
    input  logic rst,
    input  logic [$clog2(FRAME_WIDTH)-1:0] timing_x,
    input  logic [$clog2(FRAME_HEIGHT)-1:0] timing_y,
    input  logic timing_active,
    input  logic timing_hsync,
    input  logic timing_vsync,
    output logic read_valid,
    output logic [$clog2(FRAME_WIDTH)-1:0] read_x,
    output logic [$clog2(FRAME_HEIGHT)-1:0] read_y,
    input  logic read_pixel_valid,
    input  logic [15:0] read_pixel,
    output logic out_active,
    output logic out_hsync,
    output logic out_vsync,
    output logic [15:0] out_pixel
);
    always_comb begin
        read_valid = timing_active;
        read_x = timing_x;
        read_y = timing_y;
        out_pixel = out_active && read_pixel_valid ? read_pixel : 16'h0000;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            out_active <= 1'b0;
            out_hsync <= 1'b1;
            out_vsync <= 1'b1;
        end else begin
            out_active <= timing_active;
            out_hsync <= timing_hsync;
            out_vsync <= timing_vsync;
        end
    end
endmodule
