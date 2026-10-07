`timescale 1ns/1ps

module graphics_command_link #(
    parameter int unsigned FRAME_WIDTH = 640,
    parameter int unsigned FRAME_HEIGHT = 480,
    parameter int unsigned COMMAND_FIFO_DEPTH = 4
) (
    input  logic clk,
    input  logic rst,
    input  logic spi_sclk,
    input  logic spi_cs_n,
    input  logic spi_mosi,
    output logic spi_miso,
    output logic ready,
    input  logic draw_allowed,
    output logic write_valid,
    input  logic write_ready,
    output logic [21:0] write_pixel_address,
    output logic [15:0] write_data,
    output logic present_valid,
    input  logic present_ready,
    output logic [7:0] present_sequence,
    input  logic present_pending,
    output logic graphics_busy,
    output logic protocol_error_latched,
    output logic [15:0] link_error_count,
    output logic [$clog2(COMMAND_FIFO_DEPTH + 1)-1:0] command_count
);
    import command_pkg::*;

    logic [7:0] status_byte;
    logic frame_start;
    logic frame_end;
    logic byte_valid;
    logic byte_ready;
    logic [7:0] byte_data;
    logic partial_byte_error;
    logic downstream_overflow;

    logic decoder_command_valid;
    logic decoder_command_ready;
    command_t decoder_command;
    logic decoder_protocol_error;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [15:0] decoder_protocol_error_count;

    logic fifo_command_valid;
    logic fifo_command_ready;
    logic [$bits(command_t)-1:0] fifo_command_data;
    command_t fifo_command;

    logic unsupported_command;
    logic [15:0] unsupported_command_count;
    /* verilator lint_on UNUSEDSIGNAL */
    logic link_error_event;

    initial begin
        if (COMMAND_FIFO_DEPTH == 0)
            $error("command FIFO depth must be nonzero");
    end

    always_comb begin
        fifo_command = command_t'(fifo_command_data);
        ready = command_count < $clog2(COMMAND_FIFO_DEPTH + 1)'(COMMAND_FIFO_DEPTH) &&
                !decoder_command_valid;
        status_byte = {
            4'h1,
            present_pending,
            protocol_error_latched,
            graphics_busy,
            ready
        };
        link_error_event = decoder_protocol_error || partial_byte_error ||
                           downstream_overflow || unsupported_command;
    end

    spi_mode0_slave spi_receiver (
        .clk,
        .rst,
        .spi_sclk,
        .spi_cs_n,
        .spi_mosi,
        .spi_miso,
        .status_byte,
        .frame_start,
        .frame_end,
        .byte_valid,
        .byte_ready,
        .byte_data,
        .partial_byte_error,
        .downstream_overflow
    );

    command_decoder packet_decoder (
        .clk,
        .rst,
        .frame_start,
        .frame_end,
        .byte_valid,
        .byte_ready,
        .byte_data,
        .command_valid(decoder_command_valid),
        .command_ready(decoder_command_ready),
        .command(decoder_command),
        .protocol_error(decoder_protocol_error),
        .protocol_error_count(decoder_protocol_error_count)
    );

    sync_fifo #(
        .WIDTH($bits(command_t)),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) command_fifo (
        .clk,
        .rst,
        .in_valid(decoder_command_valid),
        .in_ready(decoder_command_ready),
        .in_data(decoder_command),
        .out_valid(fifo_command_valid),
        .out_ready(fifo_command_ready),
        .out_data(fifo_command_data),
        .count(command_count)
    );

    graphics_command_engine #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) command_engine (
        .clk,
        .rst,
        .command_valid(fifo_command_valid),
        .command_ready(fifo_command_ready),
        .command(fifo_command),
        .draw_allowed,
        .write_valid,
        .write_ready,
        .write_pixel_address,
        .write_data,
        .present_valid,
        .present_ready,
        .present_sequence,
        .busy(graphics_busy),
        .unsupported_command,
        .unsupported_command_count
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            protocol_error_latched <= 1'b0;
            link_error_count <= '0;
        end else begin
            if (link_error_event)
                protocol_error_latched <= 1'b1;

            if (link_error_event && link_error_count != 16'hffff)
                link_error_count <= link_error_count + 1'b1;
        end
    end
endmodule
