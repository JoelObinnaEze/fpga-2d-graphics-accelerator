`timescale 1ns/1ps

module video_timing #(
    parameter int unsigned H_ACTIVE = 640,
    parameter int unsigned H_FRONT  = 16,
    parameter int unsigned H_SYNC   = 96,
    parameter int unsigned H_BACK   = 48,
    parameter int unsigned V_ACTIVE = 480,
    parameter int unsigned V_FRONT  = 10,
    parameter int unsigned V_SYNC   = 2,
    parameter int unsigned V_BACK   = 33
) (
    input  logic clk,
    input  logic rst,
    output logic [$clog2(H_ACTIVE + H_FRONT + H_SYNC + H_BACK)-1:0] x,
    output logic [$clog2(V_ACTIVE + V_FRONT + V_SYNC + V_BACK)-1:0] y,
    output logic active_video,
    output logic hsync,
    output logic vsync,
    output logic line_start,
    output logic frame_start,
    output logic vblank_start
);
    localparam int unsigned H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam int unsigned V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    localparam int unsigned H_WIDTH = $clog2(H_TOTAL);
    localparam int unsigned V_WIDTH = $clog2(V_TOTAL);

    always_ff @(posedge clk) begin
        if (rst) begin
            x <= '0;
            y <= '0;
        end else if (x == H_WIDTH'(H_TOTAL - 1)) begin
            x <= '0;
            y <= (y == V_WIDTH'(V_TOTAL - 1)) ? '0 : y + 1'b1;
        end else begin
            x <= x + 1'b1;
        end
    end

    always_comb begin
        active_video = x < H_WIDTH'(H_ACTIVE) && y < V_WIDTH'(V_ACTIVE);
        hsync = !(x >= H_WIDTH'(H_ACTIVE + H_FRONT) &&
                  x < H_WIDTH'(H_ACTIVE + H_FRONT + H_SYNC));
        vsync = !(y >= V_WIDTH'(V_ACTIVE + V_FRONT) &&
                  y < V_WIDTH'(V_ACTIVE + V_FRONT + V_SYNC));
        line_start = x == 0;
        frame_start = x == 0 && y == 0;
        vblank_start = x == 0 && y == V_WIDTH'(V_ACTIVE);
    end
endmodule
