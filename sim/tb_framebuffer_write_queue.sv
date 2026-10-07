`timescale 1ns/1ps

module tb_framebuffer_write_queue;
    localparam int unsigned FIFO_DEPTH = 4;
    localparam int unsigned MAX_OUTSTANDING_WRITES = 2;

    logic clk;
    logic rst;
    logic write_valid;
    logic write_ready;
    logic [21:0] write_pixel_address;
    logic [15:0] write_data;
    logic arbiter_valid;
    logic arbiter_ready;
    logic [21:0] arbiter_pixel_address;
    logic [15:0] arbiter_write_data;
    logic backend_write_committed;
    logic writes_committed;
    logic [$clog2(FIFO_DEPTH + 1)-1:0] queue_count;
    logic [$clog2(MAX_OUTSTANDING_WRITES + 1)-1:0] outstanding_count;
    logic protocol_error;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    framebuffer_write_queue #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .MAX_OUTSTANDING_WRITES(MAX_OUTSTANDING_WRITES)
    ) dut (
        .clk,
        .rst,
        .write_valid,
        .write_ready,
        .write_pixel_address,
        .write_data,
        .arbiter_valid,
        .arbiter_ready,
        .arbiter_pixel_address,
        .arbiter_write_data,
        .backend_write_committed,
        .writes_committed,
        .queue_count,
        .outstanding_count,
        .protocol_error
    );

    task automatic enqueue(
        input logic [21:0] pixel_address,
        input logic [15:0] pixel_data
    );
        @(negedge clk);
        while (!write_ready)
            @(negedge clk);
        write_pixel_address = pixel_address;
        write_data = pixel_data;
        write_valid = 1'b1;
        @(posedge clk);
        #1;
        write_valid = 1'b0;
    endtask

    task automatic accept_output(
        input logic [21:0] expected_address,
        input logic [15:0] expected_data,
        input bit commit_same_cycle
    );
        @(negedge clk);
        arbiter_ready = 1'b1;
        backend_write_committed = commit_same_cycle;
        #1;
        if (!arbiter_valid || arbiter_pixel_address != expected_address ||
            arbiter_write_data != expected_data)
            $fatal(1, "write dequeue mismatch: expected (%0d,%04x), got (%0d,%04x)",
                   expected_address, expected_data,
                   arbiter_pixel_address, arbiter_write_data);
        @(posedge clk);
        #1;
        arbiter_ready = 1'b0;
        backend_write_committed = 1'b0;
    endtask

    task automatic commit_one;
        @(negedge clk);
        backend_write_committed = 1'b1;
        @(posedge clk);
        #1;
        backend_write_committed = 1'b0;
    endtask

    initial begin
        rst = 1'b1;
        write_valid = 1'b0;
        write_pixel_address = '0;
        write_data = '0;
        arbiter_ready = 1'b0;
        backend_write_committed = 1'b0;

        repeat (3) @(posedge clk);
        rst = 1'b0;
        #1;
        if (!write_ready || !writes_committed || protocol_error)
            $fatal(1, "write queue reset state was incorrect");

        for (int i = 0; i < FIFO_DEPTH; i++)
            enqueue(22'd200 + 22'(i), 16'h5000 + 16'(i));

        @(negedge clk);
        if (write_ready || int'(queue_count) != FIFO_DEPTH ||
            !arbiter_valid || writes_committed)
            $fatal(1, "write queue did not report its full state");

        repeat (3) begin
            @(posedge clk);
            #1;
            if (!arbiter_valid || arbiter_pixel_address != 22'd200 ||
                arbiter_write_data != 16'h5000)
                $fatal(1, "write payload changed while arbiter was stalled");
        end

        accept_output(22'd200, 16'h5000, 1'b0);
        accept_output(22'd201, 16'h5001, 1'b0);
        @(negedge clk);
        if (arbiter_valid || int'(outstanding_count) != 2 ||
            int'(queue_count) != 2)
            $fatal(1, "outstanding-write limit did not apply backpressure");

        accept_output(22'd202, 16'h5002, 1'b1);
        if (int'(outstanding_count) != 2 || int'(queue_count) != 1)
            $fatal(1, "simultaneous commit/dequeue changed outstanding count");

        commit_one();
        accept_output(22'd203, 16'h5003, 1'b0);
        if (queue_count != 0 || int'(outstanding_count) != 2 ||
            writes_committed)
            $fatal(1, "queue empty was confused with backend commitment");

        commit_one();
        if (writes_committed || int'(outstanding_count) != 1)
            $fatal(1, "writes committed before the final backend completion");
        commit_one();
        if (!writes_committed || outstanding_count != 0 || protocol_error)
            $fatal(1, "final backend completion was not tracked");

        commit_one();
        if (!protocol_error || !writes_committed || outstanding_count != 0)
            $fatal(1, "unexpected backend completion corrupted queue state");

        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;
        if (protocol_error || !writes_committed)
            $fatal(1, "reset did not recover write-queue status");

        $display("PASS: framebuffer write queue capacity, ordering, commitment, and errors");
        $finish;
    end
endmodule
