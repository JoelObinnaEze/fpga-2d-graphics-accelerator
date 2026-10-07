`timescale 1ns/1ps

module tb_async_fifo;
    localparam int unsigned WIDTH = 16;
    localparam int unsigned DEPTH = 8;

    logic write_clk;
    logic write_rst;
    logic write_valid;
    logic write_ready;
    logic [WIDTH-1:0] write_data;
    logic [$clog2(DEPTH + 1)-1:0] write_level;
    logic read_clk;
    logic read_rst;
    logic read_valid;
    logic read_ready;
    logic [WIDTH-1:0] read_data;
    logic [$clog2(DEPTH + 1)-1:0] read_level;

    initial begin
        write_clk = 1'b0;
        forever #3 write_clk = ~write_clk;
    end

    initial begin
        read_clk = 1'b0;
        forever #5 read_clk = ~read_clk;
    end

    async_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .write_clk,
        .write_rst,
        .write_valid,
        .write_ready,
        .write_data,
        .write_level,
        .read_clk,
        .read_rst,
        .read_valid,
        .read_ready,
        .read_data,
        .read_level
    );

    task automatic push(input logic [WIDTH-1:0] value);
        @(negedge write_clk);
        while (!write_ready)
            @(negedge write_clk);
        write_data = value;
        write_valid = 1'b1;
        @(posedge write_clk);
        #1;
        write_valid = 1'b0;
    endtask

    task automatic pop_and_expect(input logic [WIDTH-1:0] expected);
        @(negedge read_clk);
        while (!read_valid)
            @(negedge read_clk);
        if (read_data != expected)
            $fatal(1, "FIFO order mismatch: expected %04x got %04x",
                   expected, read_data);
        read_ready = 1'b1;
        @(posedge read_clk);
        #1;
        read_ready = 1'b0;
    endtask

    initial begin
        write_rst = 1'b1;
        read_rst = 1'b1;
        write_valid = 1'b0;
        write_data = '0;
        read_ready = 1'b0;

        repeat (4) @(posedge write_clk);
        write_rst = 1'b0;
        repeat (4) @(posedge read_clk);
        read_rst = 1'b0;

        for (int i = 0; i < DEPTH; i++)
            push(16'h1000 + 16'(i));

        @(negedge write_clk);
        if (write_ready || int'(write_level) != DEPTH)
            $fatal(1, "FIFO did not report full at depth %0d", DEPTH);

        repeat (4) @(posedge read_clk);
        if (int'(read_level) != DEPTH)
            $fatal(1, "read-domain level did not converge to full");

        for (int i = 0; i < DEPTH; i++) begin
            if ((i & 1) == 0)
                repeat (2) @(posedge read_clk);
            pop_and_expect(16'h1000 + 16'(i));
        end

        repeat (4) @(posedge write_clk);
        if (write_level != 0 || !write_ready)
            $fatal(1, "write-domain level did not converge to empty");

        write_rst = 1'b1;
        read_rst = 1'b1;
        repeat (3) @(posedge write_clk);
        repeat (3) @(posedge read_clk);
        write_rst = 1'b0;
        read_rst = 1'b0;

        fork
            begin
                for (int i = 0; i < 40; i++)
                    push(16'h4000 + 16'(i));
            end
            begin
                for (int i = 0; i < 40; i++) begin
                    if ((i % 3) == 1)
                        repeat (3) @(posedge read_clk);
                    pop_and_expect(16'h4000 + 16'(i));
                end
            end
        join

        repeat (5) @(posedge read_clk);
        if (read_valid || read_level != 0)
            $fatal(1, "FIFO did not return to empty after concurrent traffic");

        $display("PASS: asynchronous FIFO full/empty, stalls, ordering, and reset recovery");
        $finish;
    end
endmodule
