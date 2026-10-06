`timescale 1ns/1ps

module sprite_renderer #(
    parameter int unsigned FRAME_WIDTH = 640,
    parameter int unsigned FRAME_HEIGHT = 480
) (
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [15:0] origin_x,
    input  logic [15:0] origin_y,
    input  logic sprite_valid,
    input  logic [31:0] sprite_base,
    input  logic [15:0] sprite_width,
    input  logic [15:0] sprite_height,
    output logic sprite_read_enable,
    output logic [31:0] sprite_address,
    input  logic sprite_pixel_valid,
    input  logic [15:0] sprite_pixel_color,
    input  logic sprite_pixel_opaque,
    output logic busy,
    output logic done,
    output logic write_valid,
    input  logic write_ready,
    output logic [15:0] write_x,
    output logic [15:0] write_y,
    output logic [15:0] write_color
);
    typedef enum logic [1:0] {IDLE, ISSUE_READ, WAIT_PIXEL, OUTPUT_PIXEL} state_t;

    state_t state;
    logic [15:0] source_width;
    logic [15:0] visible_width;
    logic [15:0] visible_height;
    logic [15:0] source_x;
    logic [15:0] source_y;
    logic [31:0] current_address;
    logic [15:0] start_visible_width;
    logic [15:0] start_visible_height;
    logic last_pixel;
    logic consume_pixel;

    always_comb begin
        start_visible_width = '0;
        start_visible_height = '0;
        if (int'(origin_x) < FRAME_WIDTH)
            start_visible_width = int'(sprite_width) < FRAME_WIDTH - int'(origin_x)
                                ? sprite_width
                                : 16'(FRAME_WIDTH - int'(origin_x));
        if (int'(origin_y) < FRAME_HEIGHT)
            start_visible_height = int'(sprite_height) < FRAME_HEIGHT - int'(origin_y)
                                 ? sprite_height
                                 : 16'(FRAME_HEIGHT - int'(origin_y));

        sprite_read_enable = state == ISSUE_READ;
        sprite_address = current_address;
        busy = state != IDLE;
        write_valid = state == OUTPUT_PIXEL;
        last_pixel = source_x == visible_width - 1'b1 &&
                     source_y == visible_height - 1'b1;
        consume_pixel = (state == WAIT_PIXEL && sprite_pixel_valid && !sprite_pixel_opaque) ||
                        (state == OUTPUT_PIXEL && write_ready);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            source_width <= '0;
            visible_width <= '0;
            visible_height <= '0;
            source_x <= '0;
            source_y <= '0;
            current_address <= '0;
            done <= 1'b0;
            write_x <= '0;
            write_y <= '0;
            write_color <= '0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        if (!sprite_valid || sprite_width == 0 || sprite_height == 0 ||
                            start_visible_width == 0 || start_visible_height == 0) begin
                            done <= 1'b1;
                        end else begin
                            source_width <= sprite_width;
                            visible_width <= start_visible_width;
                            visible_height <= start_visible_height;
                            source_x <= '0;
                            source_y <= '0;
                            current_address <= sprite_base;
                            state <= ISSUE_READ;
                        end
                    end
                end
                ISSUE_READ: state <= WAIT_PIXEL;
                WAIT_PIXEL: begin
                    if (sprite_pixel_valid && sprite_pixel_opaque) begin
                        write_x <= origin_x + source_x;
                        write_y <= origin_y + source_y;
                        write_color <= sprite_pixel_color;
                        state <= OUTPUT_PIXEL;
                    end
                end
                OUTPUT_PIXEL: state <= state;
                default: state <= IDLE;
            endcase

            if (consume_pixel) begin
                if (last_pixel) begin
                    state <= IDLE;
                    done <= 1'b1;
                end else begin
                    if (source_x == visible_width - 1'b1) begin
                        source_x <= '0;
                        source_y <= source_y + 1'b1;
                        current_address <= current_address + 32'(source_width) -
                                           32'(visible_width) + 32'd1;
                    end else begin
                        source_x <= source_x + 1'b1;
                        current_address <= current_address + 1'b1;
                    end
                    state <= ISSUE_READ;
                end
            end
        end
    end
endmodule
