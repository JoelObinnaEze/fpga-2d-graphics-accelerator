`timescale 1ns/1ps

module test_pattern #(
    parameter int unsigned H_ACTIVE = 640
) (
    input  logic [$clog2(H_ACTIVE + 1)-1:0] x,
    input  logic active_video,
    output logic [15:0] pixel
);
    localparam int unsigned X_WIDTH = $clog2(H_ACTIVE + 1);

    always_comb begin
        pixel = 16'h0000;
        if (active_video) begin
            if      (x < X_WIDTH'(H_ACTIVE * 1/8)) pixel = 16'hffff;
            else if (x < X_WIDTH'(H_ACTIVE * 2/8)) pixel = 16'hffe0;
            else if (x < X_WIDTH'(H_ACTIVE * 3/8)) pixel = 16'h07ff;
            else if (x < X_WIDTH'(H_ACTIVE * 4/8)) pixel = 16'h07e0;
            else if (x < X_WIDTH'(H_ACTIVE * 5/8)) pixel = 16'hf81f;
            else if (x < X_WIDTH'(H_ACTIVE * 6/8)) pixel = 16'hf800;
            else if (x < X_WIDTH'(H_ACTIVE * 7/8)) pixel = 16'h001f;
        end
    end
endmodule
