`timescale 1ns/1ps

module tb_graphics_command_engine;
    import command_pkg::*;

    localparam int FRAME_WIDTH = 8;
    localparam int FRAME_HEIGHT = 6;
    localparam int EXPECTED_WRITES = FRAME_WIDTH * FRAME_HEIGHT + 4;

    logic clk;
    logic rst;
    logic command_valid;
    logic command_ready;
    command_t command;
    logic draw_allowed;
    logic write_valid;
    logic write_ready;
    logic [21:0] write_pixel_address;
    logic [15:0] write_data;
    logic present_valid;
    logic present_ready;
    logic [7:0] present_sequence;
    logic busy;
    logic unsupported_command;
    logic [15:0] unsupported_command_count;

    int expected_address [0:EXPECTED_WRITES-1];
    logic [15:0] expected_color [0:EXPECTED_WRITES-1];
    int received_writes;
    int ready_pattern;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    graphics_command_engine #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) dut (.*);

    always_ff @(posedge clk) begin
        if (rst) begin
            received_writes <= 0;
            ready_pattern <= 0;
            write_ready <= 1'b0;
        end else begin
            ready_pattern <= ready_pattern + 1;
            write_ready <= ready_pattern % 4 != 1;

            if (write_valid && write_ready) begin
                if (received_writes >= EXPECTED_WRITES)
                    $fatal(1, "unexpected extra pixel write");
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
    end

    task automatic issue_command(input command_t value, output int wait_cycles);
        @(negedge clk);
        command = value;
        command_valid = 1'b1;
        wait_cycles = 0;
        while (!command_ready) begin
            @(negedge clk);
            wait_cycles++;
            if (wait_cycles > 500)
                $fatal(1, "command acceptance timed out");
        end
        @(posedge clk);
        #1;
        command_valid = 1'b0;
    endtask

    initial begin
        command_t next_command;
        int wait_cycles;
        int index;

        for (int address = 0; address < FRAME_WIDTH * FRAME_HEIGHT; address++) begin
            expected_address[address] = address;
            expected_color[address] = 16'h1234;
        end
        index = FRAME_WIDTH * FRAME_HEIGHT;
        expected_address[index + 0] = 4 * FRAME_WIDTH + 6;
        expected_address[index + 1] = 4 * FRAME_WIDTH + 7;
        expected_address[index + 2] = 5 * FRAME_WIDTH + 6;
        expected_address[index + 3] = 5 * FRAME_WIDTH + 7;
        for (int rect_index = 0; rect_index < 4; rect_index++)
            expected_color[index + rect_index] = 16'hf800;

        rst = 1'b1;
        command_valid = 1'b0;
        command = '0;
        draw_allowed = 1'b0;
        present_ready = 1'b0;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        next_command = '0;
        next_command.opcode = OP_CLEAR;
        next_command.sequence_id = 8'h10;
        next_command.arg0 = 16'h1234;

        @(negedge clk);
        command = next_command;
        command_valid = 1'b1;
        repeat (3) begin
            @(posedge clk);
            #1;
            if (command_ready)
                $fatal(1, "command accepted while draw buffer was locked");
        end
        draw_allowed = 1'b1;
        @(negedge clk);
        if (!command_ready)
            $fatal(1, "CLEAR was not accepted when drawing became available");
        @(posedge clk);
        #1;
        command_valid = 1'b0;

        next_command = '0;
        next_command.opcode = OP_DRAW_RECT;
        next_command.sequence_id = 8'h11;
        next_command.arg0 = 16'd6;
        next_command.arg1 = 16'd4;
        next_command.arg2 = 16'd4;
        next_command.arg3 = 16'd4;
        next_command.arg4 = 16'hf800;
        issue_command(next_command, wait_cycles);
        if (wait_cycles == 0)
            $fatal(1, "DRAW_RECT bypassed the in-flight CLEAR");
        if (received_writes != FRAME_WIDTH * FRAME_HEIGHT)
            $fatal(1, "next command was accepted before the final CLEAR write drained");

        wait (received_writes == EXPECTED_WRITES);
        wait (!busy);
        @(posedge clk);
        #1;

        next_command = '0;
        next_command.opcode = OP_PRESENT;
        next_command.sequence_id = 8'h5a;
        issue_command(next_command, wait_cycles);

        repeat (4) begin
            @(posedge clk);
            #1;
            if (!present_valid || present_sequence != 8'h5a || !busy)
                $fatal(1, "PRESENT was not held stable under backpressure");
            if (command_ready)
                $fatal(1, "engine accepted a command while PRESENT was pending");
        end

        @(negedge clk);
        present_ready = 1'b1;
        @(posedge clk);
        #1;
        present_ready = 1'b0;
        if (present_valid || busy)
            $fatal(1, "PRESENT handshake did not retire the command");

        if (unsupported_command || unsupported_command_count != 0)
            $fatal(1, "supported commands raised unsupported-command status");

        $display("PASS: ordered CLEAR, clipped DRAW_RECT, and stalled PRESENT execution");
        $finish;
    end
endmodule
