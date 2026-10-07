`timescale 1ns/1ps

module graphics_command_engine #(
    parameter int unsigned FRAME_WIDTH = 640,
    parameter int unsigned FRAME_HEIGHT = 480,
    parameter int unsigned ADDRESS_WIDTH = 22
) (
    input  logic clk,
    input  logic rst,
    input  logic command_valid,
    output logic command_ready,
    input  command_pkg::command_t command,
    input  logic draw_allowed,
    output logic write_valid,
    input  logic write_ready,
    output logic [ADDRESS_WIDTH-1:0] write_pixel_address,
    output logic [15:0] write_data,
    output logic present_valid,
    input  logic present_ready,
    output logic [7:0] present_sequence,
    output logic busy,
    output logic unsupported_command,
    output logic [15:0] unsupported_command_count
);
    import command_pkg::*;

    localparam int unsigned X_WIDTH = $clog2(FRAME_WIDTH);
    localparam int unsigned Y_WIDTH = $clog2(FRAME_HEIGHT);

    typedef enum logic [2:0] {
        IDLE,
        START_RECT,
        WAIT_RECT,
        WAIT_RECT_DRAIN,
        WAIT_PRESENT
    } state_t;

    state_t state;
    logic rect_cmd_valid;
    logic rect_cmd_ready;
    logic [15:0] stored_rect_x;
    logic [15:0] stored_rect_y;
    logic [15:0] stored_rect_width;
    logic [15:0] stored_rect_height;
    logic [15:0] stored_rect_color;
    logic rect_write_valid;
    logic rect_write_ready;
    logic [X_WIDTH-1:0] rect_write_x;
    logic [Y_WIDTH-1:0] rect_write_y;
    logic [15:0] rect_write_pixel;
    logic rect_busy;
    logic rect_done;

    logic write_buffer_valid;
    logic [ADDRESS_WIDTH-1:0] write_buffer_address;
    logic [15:0] write_buffer_data;
    logic write_buffer_transfer;

    initial begin
        if (FRAME_WIDTH == 0 || FRAME_HEIGHT == 0)
            $error("frame dimensions must be nonzero");
        if (FRAME_WIDTH * FRAME_HEIGHT > 2**ADDRESS_WIDTH)
            $error("frame must fit the renderer pixel-address space");
    end

    always_comb begin
        command_ready = state == IDLE && draw_allowed;
        rect_cmd_valid = state == START_RECT;

        // The registered output is deliberately not fall-through. This keeps
        // SDRAM-ready combinational logic out of the renderer's coordinate
        // feedback path; the one-cycle bubble is harmless at video rates.
        rect_write_ready = !write_buffer_valid;
        write_buffer_transfer = write_buffer_valid && write_ready;
        write_valid = write_buffer_valid;
        write_pixel_address = write_buffer_address;
        write_data = write_buffer_data;

        present_valid = state == WAIT_PRESENT;
        busy = state != IDLE || rect_busy;
    end

    rect_renderer #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .COORD_WIDTH(16)
    ) rectangle_renderer (
        .clk,
        .rst,
        .cmd_valid(rect_cmd_valid),
        .cmd_ready(rect_cmd_ready),
        .cmd_x(stored_rect_x),
        .cmd_y(stored_rect_y),
        .cmd_width(stored_rect_width),
        .cmd_height(stored_rect_height),
        .cmd_color(stored_rect_color),
        .write_valid(rect_write_valid),
        .write_ready(rect_write_ready),
        .write_x(rect_write_x),
        .write_y(rect_write_y),
        .write_pixel(rect_write_pixel),
        .busy(rect_busy),
        .done(rect_done)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            write_buffer_valid <= 1'b0;
            write_buffer_address <= '0;
            write_buffer_data <= '0;
            stored_rect_x <= '0;
            stored_rect_y <= '0;
            stored_rect_width <= '0;
            stored_rect_height <= '0;
            stored_rect_color <= '0;
            present_sequence <= '0;
            unsupported_command <= 1'b0;
            unsupported_command_count <= '0;
        end else begin
            unsupported_command <= 1'b0;

            if (write_buffer_transfer)
                write_buffer_valid <= 1'b0;

            if (rect_write_valid && rect_write_ready) begin
                write_buffer_valid <= 1'b1;
                write_buffer_address <=
                    ADDRESS_WIDTH'(rect_write_y) * ADDRESS_WIDTH'(FRAME_WIDTH) +
                    ADDRESS_WIDTH'(rect_write_x);
                write_buffer_data <= rect_write_pixel;
            end

            case (state)
                IDLE: begin
                    if (command_valid && command_ready) begin
                        case (command.opcode)
                            OP_CLEAR: begin
                                stored_rect_x <= '0;
                                stored_rect_y <= '0;
                                stored_rect_width <= 16'(FRAME_WIDTH);
                                stored_rect_height <= 16'(FRAME_HEIGHT);
                                stored_rect_color <= command.arg0;
                                state <= START_RECT;
                            end
                            OP_DRAW_RECT: begin
                                stored_rect_x <= command.arg0;
                                stored_rect_y <= command.arg1;
                                stored_rect_width <= command.arg2;
                                stored_rect_height <= command.arg3;
                                stored_rect_color <= command.arg4;
                                state <= START_RECT;
                            end
                            OP_PRESENT: begin
                                present_sequence <= command.sequence_id;
                                state <= WAIT_PRESENT;
                            end
                            default: begin
                                unsupported_command <= 1'b1;
                                if (unsupported_command_count != 16'hffff)
                                    unsupported_command_count <=
                                        unsupported_command_count + 1'b1;
                            end
                        endcase
                    end
                end
                START_RECT: begin
                    if (rect_cmd_ready)
                        state <= WAIT_RECT;
                end
                WAIT_RECT: begin
                    if (rect_done) begin
                        if (!write_buffer_valid)
                            state <= IDLE;
                        else
                            state <= WAIT_RECT_DRAIN;
                    end
                end
                WAIT_RECT_DRAIN: begin
                    if (!write_buffer_valid)
                        state <= IDLE;
                end
                WAIT_PRESENT: begin
                    if (present_ready)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
