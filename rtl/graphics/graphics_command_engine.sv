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
        WAIT_RECT,
        WAIT_RECT_DRAIN,
        WAIT_PRESENT
    } state_t;

    state_t state;
    logic rect_command;
    logic rect_cmd_valid;
    logic rect_cmd_ready;
    logic [15:0] rect_cmd_x;
    logic [15:0] rect_cmd_y;
    logic [15:0] rect_cmd_width;
    logic [15:0] rect_cmd_height;
    logic [15:0] rect_cmd_color;
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
        rect_command = command.opcode == OP_CLEAR ||
                       command.opcode == OP_DRAW_RECT;
        command_ready = state == IDLE && draw_allowed &&
                        (!rect_command || rect_cmd_ready);

        rect_cmd_valid = command_valid && command_ready && rect_command;
        if (command.opcode == OP_CLEAR) begin
            rect_cmd_x = '0;
            rect_cmd_y = '0;
            rect_cmd_width = 16'(FRAME_WIDTH);
            rect_cmd_height = 16'(FRAME_HEIGHT);
            rect_cmd_color = command.arg0;
        end else begin
            rect_cmd_x = command.arg0;
            rect_cmd_y = command.arg1;
            rect_cmd_width = command.arg2;
            rect_cmd_height = command.arg3;
            rect_cmd_color = command.arg4;
        end

        rect_write_ready = !write_buffer_valid || write_ready;
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
        .cmd_x(rect_cmd_x),
        .cmd_y(rect_cmd_y),
        .cmd_width(rect_cmd_width),
        .cmd_height(rect_cmd_height),
        .cmd_color(rect_cmd_color),
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
                            OP_CLEAR, OP_DRAW_RECT: state <= WAIT_RECT;
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
                WAIT_RECT: begin
                    if (rect_done) begin
                        if (!write_buffer_valid || write_buffer_transfer)
                            state <= IDLE;
                        else
                            state <= WAIT_RECT_DRAIN;
                    end
                end
                WAIT_RECT_DRAIN: begin
                    if (!write_buffer_valid || write_buffer_transfer)
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
