`timescale 1ns/1ps

module rect_renderer #(
    parameter int unsigned FRAME_WIDTH  = 640,
    parameter int unsigned FRAME_HEIGHT = 480,
    parameter int unsigned COORD_WIDTH  = 16
) (
    input  logic clk,
    input  logic rst,
    input  logic cmd_valid,
    output logic cmd_ready,
    input  logic [COORD_WIDTH-1:0] cmd_x,
    input  logic [COORD_WIDTH-1:0] cmd_y,
    input  logic [COORD_WIDTH-1:0] cmd_width,
    input  logic [COORD_WIDTH-1:0] cmd_height,
    input  logic [15:0] cmd_color,
    output logic write_valid,
    input  logic write_ready,
    output logic [$clog2(FRAME_WIDTH)-1:0] write_x,
    output logic [$clog2(FRAME_HEIGHT)-1:0] write_y,
    output logic [15:0] write_pixel,
    output logic busy,
    output logic done
);
    localparam int unsigned X_WIDTH = $clog2(FRAME_WIDTH);
    localparam int unsigned Y_WIDTH = $clog2(FRAME_HEIGHT);
    localparam int unsigned COMMAND_LIMIT_WIDTH = COORD_WIDTH + 1;

    logic [X_WIDTH-1:0] current_x;
    logic [Y_WIDTH-1:0] current_y;
    logic [X_WIDTH-1:0] start_x;
    logic [X_WIDTH-1:0] last_x;
    logic [Y_WIDTH-1:0] last_y;
    logic [15:0] color;
    logic [COMMAND_LIMIT_WIDTH-1:0] command_end_x;
    logic [COMMAND_LIMIT_WIDTH-1:0] command_end_y;
    logic [X_WIDTH-1:0] clipped_last_x;
    logic [Y_WIDTH-1:0] clipped_last_y;
    logic command_empty;

    always_comb begin
        command_end_x = {1'b0, cmd_x} + {1'b0, cmd_width};
        command_end_y = {1'b0, cmd_y} + {1'b0, cmd_height};
        clipped_last_x = command_end_x > COMMAND_LIMIT_WIDTH'(FRAME_WIDTH)
                       ? X_WIDTH'(FRAME_WIDTH - 1)
                       : X_WIDTH'(command_end_x - 1'b1);
        clipped_last_y = command_end_y > COMMAND_LIMIT_WIDTH'(FRAME_HEIGHT)
                       ? Y_WIDTH'(FRAME_HEIGHT - 1)
                       : Y_WIDTH'(command_end_y - 1'b1);
        command_empty = cmd_width == 0 || cmd_height == 0 ||
                        int'(cmd_x) >= FRAME_WIDTH || int'(cmd_y) >= FRAME_HEIGHT;

        cmd_ready = !busy;
        write_valid = busy;
        write_x = current_x;
        write_y = current_y;
        write_pixel = color;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            current_x <= '0;
            current_y <= '0;
            start_x <= '0;
            last_x <= '0;
            last_y <= '0;
            color <= '0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy && cmd_valid) begin
                if (command_empty) begin
                    done <= 1'b1;
                end else begin
                    current_x <= cmd_x[X_WIDTH-1:0];
                    current_y <= cmd_y[Y_WIDTH-1:0];
                    start_x <= cmd_x[X_WIDTH-1:0];
                    last_x <= clipped_last_x;
                    last_y <= clipped_last_y;
                    color <= cmd_color;
                    busy <= 1'b1;
                end
            end else if (busy && write_ready) begin
                if (current_x == last_x) begin
                    if (current_y == last_y) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        current_x <= start_x;
                        current_y <= current_y + 1'b1;
                    end
                end else begin
                    current_x <= current_x + 1'b1;
                end
            end
        end
    end
endmodule
