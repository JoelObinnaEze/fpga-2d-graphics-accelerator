`timescale 1ns/1ps

module tb_command_path;
    import command_pkg::*;

    logic clk;
    logic rst;
    logic frame_start;
    logic frame_end;
    logic byte_valid;
    logic byte_ready;
    logic [7:0] byte_data;
    logic decoder_valid;
    logic decoder_ready;
    command_t decoder_command;
    logic protocol_error;
    logic [15:0] protocol_error_count;
    logic fifo_valid;
    logic fifo_ready;
    logic [$bits(command_t)-1:0] fifo_data;
    logic [1:0] fifo_count;
    command_t fifo_command;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    command_decoder decoder (
        .clk, .rst, .frame_start, .frame_end,
        .byte_valid, .byte_ready, .byte_data,
        .command_valid(decoder_valid),
        .command_ready(decoder_ready),
        .command(decoder_command),
        .protocol_error, .protocol_error_count
    );

    sync_fifo #(
        .WIDTH($bits(command_t)),
        .DEPTH(2)
    ) fifo (
        .clk, .rst,
        .in_valid(decoder_valid),
        .in_ready(decoder_ready),
        .in_data(decoder_command),
        .out_valid(fifo_valid),
        .out_ready(fifo_ready),
        .out_data(fifo_data),
        .count(fifo_count)
    );

    always_comb fifo_command = command_t'(fifo_data);

    function automatic logic [7:0] crc8(
        input logic [7:0] crc_in,
        input logic [7:0] data
    );
        logic [7:0] crc;
        crc = crc_in;
        for (int bit_index = 0; bit_index < 8; bit_index++) begin
            crc = (crc[7] ^ data[7-bit_index])
                ? {crc[6:0], 1'b0} ^ 8'h07
                : {crc[6:0], 1'b0};
        end
        return crc;
    endfunction

    task automatic pulse_frame_start;
        @(negedge clk);
        frame_start = 1'b1;
        @(posedge clk);
        #1;
        frame_start = 1'b0;
    endtask

    task automatic pulse_frame_end;
        @(negedge clk);
        frame_end = 1'b1;
        @(posedge clk);
        #1;
        frame_end = 1'b0;
    endtask

    task automatic send_byte(input logic [7:0] value);
        @(negedge clk);
        while (!byte_ready) @(negedge clk);
        byte_data = value;
        byte_valid = 1'b1;
        @(posedge clk);
        #1;
        byte_valid = 1'b0;
    endtask

    task automatic send_clear(
        input logic [7:0] sequence_id,
        input logic [15:0] color,
        input bit corrupt_crc
    );
        logic [7:0] crc;
        crc = 0;
        pulse_frame_start();
        send_byte(8'ha5);
        send_byte(OP_CLEAR); crc = crc8(crc, OP_CLEAR);
        send_byte(8'd2); crc = crc8(crc, 8'd2);
        send_byte(sequence_id); crc = crc8(crc, sequence_id);
        send_byte(color[7:0]); crc = crc8(crc, color[7:0]);
        send_byte(color[15:8]); crc = crc8(crc, color[15:8]);
        send_byte(corrupt_crc ? crc ^ 8'h01 : crc);
        pulse_frame_end();
    endtask

    task automatic send_rect(
        input logic [7:0] sequence_id,
        input logic [15:0] x,
        input logic [15:0] y,
        input logic [15:0] width,
        input logic [15:0] height,
        input logic [15:0] color
    );
        logic [7:0] crc;
        logic [15:0] words [0:4];
        words[0] = x; words[1] = y; words[2] = width; words[3] = height; words[4] = color;
        crc = 0;
        pulse_frame_start();
        send_byte(8'ha5);
        send_byte(OP_DRAW_RECT); crc = crc8(crc, OP_DRAW_RECT);
        send_byte(8'd10); crc = crc8(crc, 8'd10);
        send_byte(sequence_id); crc = crc8(crc, sequence_id);
        for (int i = 0; i < 5; i++) begin
            send_byte(words[i][7:0]); crc = crc8(crc, words[i][7:0]);
            send_byte(words[i][15:8]); crc = crc8(crc, words[i][15:8]);
        end
        send_byte(crc);
        pulse_frame_end();
    endtask

    task automatic send_present(input logic [7:0] sequence_id);
        logic [7:0] crc;
        crc = 0;
        pulse_frame_start();
        send_byte(8'ha5);
        send_byte(OP_PRESENT); crc = crc8(crc, OP_PRESENT);
        send_byte(8'd0); crc = crc8(crc, 8'd0);
        send_byte(sequence_id); crc = crc8(crc, sequence_id);
        send_byte(crc);
        pulse_frame_end();
    endtask

    task automatic expect_command(
        input opcode_t opcode,
        input logic [7:0] sequence_id,
        input logic [15:0] arg0,
        input logic [15:0] arg1,
        input logic [15:0] arg2,
        input logic [15:0] arg3,
        input logic [15:0] arg4
    );
        @(negedge clk);
        if (!fifo_valid)
            $fatal(1, "expected queued command %02x", opcode);
        if (fifo_command.opcode != opcode || fifo_command.sequence_id != sequence_id ||
            fifo_command.arg0 != arg0 || fifo_command.arg1 != arg1 ||
            fifo_command.arg2 != arg2 || fifo_command.arg3 != arg3 ||
            fifo_command.arg4 != arg4)
            $fatal(1, "queued command payload mismatch for opcode %02x", opcode);
        fifo_ready = 1'b1;
        @(posedge clk);
        #1;
        fifo_ready = 1'b0;
    endtask

    initial begin
        rst = 1'b1;
        frame_start = 1'b0;
        frame_end = 1'b0;
        byte_valid = 1'b0;
        byte_data = '0;
        fifo_ready = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;

        send_rect(8'h11, 16'd2, 16'd3, 16'd4, 16'd5, 16'hf800);
        send_present(8'h12);
        if (decoder_ready || fifo_count != 2)
            $fatal(1, "FIFO accepted a third command while full");
        expect_command(OP_DRAW_RECT, 8'h11, 16'd2, 16'd3, 16'd4, 16'd5, 16'hf800);
        expect_command(OP_PRESENT, 8'h12, 0, 0, 0, 0, 0);

        send_clear(8'h13, 16'h07e0, 1'b1);
        if (fifo_valid || protocol_error_count != 1)
            $fatal(1, "bad CRC was not rejected exactly once");

        pulse_frame_start();
        send_byte(8'ha5);
        send_byte(OP_CLEAR);
        pulse_frame_end();
        if (fifo_valid || protocol_error_count != 2)
            $fatal(1, "truncated packet was not rejected exactly once");

        send_clear(8'h14, 16'h001f, 1'b0);
        expect_command(OP_CLEAR, 8'h14, 16'h001f, 0, 0, 0, 0);

        if (protocol_error)
            $fatal(1, "protocol_error pulse remained asserted");
        $display("PASS: command framing, CRC, decoding, FIFO ordering, and backpressure");
        $finish;
    end
endmodule
