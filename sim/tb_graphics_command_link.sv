`timescale 1ns/1ps

module tb_graphics_command_link;
    import command_pkg::*;

    localparam int FRAME_WIDTH = 8;
    localparam int FRAME_HEIGHT = 6;
    localparam int EXPECTED_WRITES = FRAME_WIDTH * FRAME_HEIGHT + 8;

    logic clk;
    logic rst;
    logic spi_sclk;
    logic spi_cs_n;
    logic spi_mosi;
    logic spi_miso;
    logic ready;
    logic draw_allowed;
    logic write_valid;
    logic write_ready;
    logic [21:0] write_pixel_address;
    logic [15:0] write_data;
    logic present_valid;
    logic present_ready;
    logic [7:0] present_sequence;
    logic present_pending;
    logic graphics_busy;
    logic protocol_error_latched;
    logic [15:0] link_error_count;
    logic [1:0] command_count;

    int expected_address [0:EXPECTED_WRITES-1];
    logic [15:0] expected_color [0:EXPECTED_WRITES-1];
    int received_writes;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    graphics_command_link #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .COMMAND_FIFO_DEPTH(2)
    ) dut (.*);

    always_ff @(posedge clk) begin
        if (rst) begin
            received_writes <= 0;
        end else if (write_valid && write_ready) begin
            if (received_writes >= EXPECTED_WRITES)
                $fatal(1, "unexpected extra graphics write");
            if (int'(write_pixel_address) != expected_address[received_writes])
                $fatal(1, "write %0d address was %0d, expected %0d",
                       received_writes, write_pixel_address,
                       expected_address[received_writes]);
            if (write_data != expected_color[received_writes])
                $fatal(1, "write %0d color was %04x, expected %04x",
                       received_writes, write_data,
                       expected_color[received_writes]);
            received_writes <= received_writes + 1;
        end
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

    task automatic send_packet(
        input logic [7:0] bytes [0:14],
        input int length,
        output logic [7:0] first_status
    );
        logic [7:0] rx;
        spi_begin();
        for (int byte_index = 0; byte_index < length; byte_index++) begin
            spi_transfer_byte(bytes[byte_index], rx);
            if (byte_index == 0)
                first_status = rx;
        end
        spi_end();
    endtask

    task automatic send_clear(
        input logic [7:0] sequence_id,
        input logic [15:0] color,
        input bit corrupt_crc,
        output logic [7:0] first_status
    );
        logic [7:0] packet [0:14];
        logic [7:0] crc;
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
        packet[6] = corrupt_crc ? crc ^ 8'h01 : crc;
        send_packet(packet, 7, first_status);
    endtask

    task automatic send_rect(
        input logic [7:0] sequence_id,
        input logic [15:0] x,
        input logic [15:0] y,
        input logic [15:0] width,
        input logic [15:0] height,
        input logic [15:0] color,
        output logic [7:0] first_status
    );
        logic [7:0] packet [0:14];
        logic [15:0] words [0:4];
        logic [7:0] crc;
        int packet_index;
        words[0] = x;
        words[1] = y;
        words[2] = width;
        words[3] = height;
        words[4] = color;
        packet[0] = 8'ha5;
        packet[1] = OP_DRAW_RECT;
        packet[2] = 8'd10;
        packet[3] = sequence_id;
        crc = crc8(0, packet[1]);
        crc = crc8(crc, packet[2]);
        crc = crc8(crc, packet[3]);
        packet_index = 4;
        for (int word_index = 0; word_index < 5; word_index++) begin
            packet[packet_index] = words[word_index][7:0];
            crc = crc8(crc, packet[packet_index]);
            packet_index++;
            packet[packet_index] = words[word_index][15:8];
            crc = crc8(crc, packet[packet_index]);
            packet_index++;
        end
        packet[14] = crc;
        send_packet(packet, 15, first_status);
    endtask

    task automatic send_present(
        input logic [7:0] sequence_id,
        output logic [7:0] first_status
    );
        logic [7:0] packet [0:14];
        logic [7:0] crc;
        crc = crc8(0, OP_PRESENT);
        crc = crc8(crc, 8'd0);
        crc = crc8(crc, sequence_id);
        packet[0] = 8'ha5;
        packet[1] = OP_PRESENT;
        packet[2] = 8'd0;
        packet[3] = sequence_id;
        packet[4] = crc;
        send_packet(packet, 5, first_status);
    endtask

    initial begin
        logic [7:0] first_status;
        int expected_index;

        for (int address = 0; address < FRAME_WIDTH * FRAME_HEIGHT; address++) begin
            expected_address[address] = address;
            expected_color[address] = 16'h1234;
        end
        expected_index = FRAME_WIDTH * FRAME_HEIGHT;
        expected_address[expected_index + 0] = 1 * FRAME_WIDTH + 1;
        expected_address[expected_index + 1] = 1 * FRAME_WIDTH + 2;
        expected_address[expected_index + 2] = 2 * FRAME_WIDTH + 1;
        expected_address[expected_index + 3] = 2 * FRAME_WIDTH + 2;
        expected_address[expected_index + 4] = 4 * FRAME_WIDTH + 6;
        expected_address[expected_index + 5] = 4 * FRAME_WIDTH + 7;
        expected_address[expected_index + 6] = 5 * FRAME_WIDTH + 6;
        expected_address[expected_index + 7] = 5 * FRAME_WIDTH + 7;
        for (int write_index = 0; write_index < 4; write_index++) begin
            expected_color[expected_index + write_index] = 16'hf800;
            expected_color[expected_index + 4 + write_index] = 16'h07e0;
        end

        rst = 1'b1;
        spi_sclk = 1'b0;
        spi_cs_n = 1'b1;
        spi_mosi = 1'b0;
        draw_allowed = 1'b1;
        write_ready = 1'b0;
        present_ready = 1'b0;
        present_pending = 1'b0;

        repeat (4) @(posedge clk);
        #1;
        rst = 1'b0;
        @(posedge clk);
        #1;
        if (!ready)
            $fatal(1, "READY was low with an empty command FIFO");

        send_clear(8'h10, 16'h1234, 1'b0, first_status);
        if (first_status != 8'h11)
            $fatal(1, "idle status was %02x, expected 11", first_status);
        wait (graphics_busy);

        send_rect(8'h11, 16'd1, 16'd1, 16'd2, 16'd2,
                  16'hf800, first_status);
        if (first_status[7:4] != 4'h1 || !first_status[1] || !first_status[0])
            $fatal(1, "busy/ready status was invalid: %02x", first_status);
        send_rect(8'h12, 16'd6, 16'd4, 16'd4, 16'd4,
                  16'h07e0, first_status);
        wait (!ready);
        if (command_count != 2)
            $fatal(1, "READY did not reserve exactly two queued commands");

        write_ready = 1'b1;
        wait (received_writes == EXPECTED_WRITES);
        wait (!graphics_busy && command_count == 0);

        send_present(8'h5a, first_status);
        wait (present_valid);
        repeat (4) begin
            @(posedge clk);
            #1;
            if (!present_valid || present_sequence != 8'h5a)
                $fatal(1, "PRESENT did not remain stable while stalled");
        end
        present_pending = 1'b1;
        @(negedge clk);
        present_ready = 1'b1;
        @(posedge clk);
        #1;
        present_ready = 1'b0;
        wait (!present_valid);

        send_clear(8'h20, 16'h0000, 1'b1, first_status);
        if (first_status[7:4] != 4'h1 || !first_status[3])
            $fatal(1, "presentation-pending status was invalid: %02x", first_status);
        wait (protocol_error_latched);
        present_pending = 1'b0;

        send_present(8'h5b, first_status);
        if (!first_status[2])
            $fatal(1, "latched protocol error was absent from status: %02x",
                   first_status);
        present_ready = 1'b1;
        wait (!graphics_busy);
        if (link_error_count != 1)
            $fatal(1, "bad CRC incremented aggregate error count %0d times",
                   link_error_count);

        $display("PASS: SPI READY/status, decoder FIFO, ordered rendering, and PRESENT");
        $finish;
    end
endmodule
