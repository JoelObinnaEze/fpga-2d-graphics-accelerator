`timescale 1ns/1ps

module tb_spi_command;
    import command_pkg::*;

    localparam logic [7:0] STATUS = 8'h15;

    logic clk;
    logic rst;
    logic spi_sclk;
    logic spi_cs_n;
    logic spi_mosi;
    logic spi_miso;
    logic frame_start;
    logic frame_end;
    logic byte_valid;
    logic byte_ready;
    logic [7:0] byte_data;
    logic partial_byte_error;
    logic downstream_overflow;
    logic decoder_valid;
    logic decoder_ready;
    command_t decoder_command;
    logic protocol_error;
    logic [15:0] protocol_error_count;
    logic fifo_valid;
    logic fifo_ready;
    logic [$bits(command_t)-1:0] fifo_data;
    command_t fifo_command;
    int partial_error_count;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    spi_mode0_slave spi (
        .clk, .rst,
        .spi_sclk, .spi_cs_n, .spi_mosi, .spi_miso,
        .status_byte(STATUS),
        .frame_start, .frame_end,
        .byte_valid, .byte_ready, .byte_data,
        .partial_byte_error, .downstream_overflow
    );

    command_decoder decoder (
        .clk, .rst, .frame_start, .frame_end,
        .byte_valid, .byte_ready, .byte_data,
        .command_valid(decoder_valid),
        .command_ready(decoder_ready),
        .command(decoder_command),
        .protocol_error, .protocol_error_count
    );

    sync_fifo #(
        .WIDTH($bits(command_t)), .DEPTH(2)
    ) fifo (
        .clk, .rst,
        .in_valid(decoder_valid), .in_ready(decoder_ready), .in_data(decoder_command),
        .out_valid(fifo_valid), .out_ready(fifo_ready), .out_data(fifo_data), .count()
    );

    always_comb fifo_command = command_t'(fifo_data);

    always_ff @(posedge clk) begin
        if (rst)
            partial_error_count <= 0;
        else if (partial_byte_error)
            partial_error_count <= partial_error_count + 1;
    end

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

    task automatic spi_begin;
        spi_cs_n = 1'b0;
        #100;
    endtask

    task automatic spi_end;
        #60;
        spi_cs_n = 1'b1;
        #100;
    endtask

    task automatic spi_transfer_byte(
        input logic [7:0] tx,
        output logic [7:0] rx
    );
        for (int bit_index = 7; bit_index >= 0; bit_index--) begin
            spi_mosi = tx[bit_index];
            #60;
            spi_sclk = 1'b1;
            #1;
            rx[bit_index] = spi_miso;
            #59;
            spi_sclk = 1'b0;
        end
    endtask

    task automatic send_clear_spi(
        input logic [7:0] sequence_id,
        input logic [15:0] color
    );
        logic [7:0] crc;
        logic [7:0] rx;
        logic [7:0] packet [0:6];

        crc = crc8(0, OP_CLEAR);
        crc = crc8(crc, 8'd2);
        crc = crc8(crc, sequence_id);
        crc = crc8(crc, color[7:0]);
        crc = crc8(crc, color[15:8]);
        packet[0] = 8'ha5;
        packet[1] = OP_CLEAR;
        packet[2] = 8'd2;
        packet[3] = sequence_id;
        packet[4] = color[7:0];
        packet[5] = color[15:8];
        packet[6] = crc;

        spi_begin();
        for (int i = 0; i < 7; i++) begin
            spi_transfer_byte(packet[i], rx);
            if (rx != STATUS)
                $fatal(1, "MISO status byte was %02x, expected %02x", rx, STATUS);
        end
        spi_end();
    endtask

    initial begin
        rst = 1'b1;
        spi_sclk = 1'b0;
        spi_cs_n = 1'b1;
        spi_mosi = 1'b0;
        fifo_ready = 1'b0;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        send_clear_spi(8'h42, 16'hf81f);
        repeat (20) begin
            @(posedge clk);
            #1;
            if (fifo_valid) break;
        end
        if (!fifo_valid)
            $fatal(1, "SPI command did not reach the FIFO");
        if (fifo_command.opcode != OP_CLEAR || fifo_command.sequence_id != 8'h42 ||
            fifo_command.arg0 != 16'hf81f)
            $fatal(1, "SPI command payload mismatch");
        if (downstream_overflow)
            $fatal(1, "unexpected downstream overflow");

        @(negedge clk);
        fifo_ready = 1'b1;
        @(posedge clk);
        #1;
        fifo_ready = 1'b0;

        spi_begin();
        for (int i = 0; i < 3; i++) begin
            spi_mosi = i[0];
            #60; spi_sclk = 1'b1;
            #60; spi_sclk = 1'b0;
        end
        spi_end();
        if (partial_error_count != 1 || protocol_error_count != 1)
            $fatal(1, "partial SPI byte/frame was not rejected exactly once");

        $display("PASS: oversampled SPI mode-0 receive, status transmit, and partial-frame rejection");
        $finish;
    end
endmodule
