`timescale 1ns/1ps

module tb_framebuffer_arbiter;
    localparam logic [1:0] OP_READ = 2'd0;
    localparam logic [1:0] OP_WRITE = 2'd1;
    localparam logic [1:0] OP_REFRESH = 2'd2;

    logic clk;
    logic rst;
    logic [15:0] read_fifo_level;
    logic scanout_valid;
    logic scanout_ready;
    logic [31:0] scanout_address;
    logic write_valid;
    logic write_ready;
    logic [31:0] write_address;
    logic [15:0] write_data;
    logic refresh_valid;
    logic refresh_ready;
    logic memory_valid;
    logic memory_ready;
    logic [1:0] memory_operation;
    logic [31:0] memory_address;
    logic [15:0] memory_write_data;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    framebuffer_arbiter #(
        .READ_FIFO_LOW_WATER(4),
        .MAX_CONSECUTIVE_WRITES(2)
    ) dut (
        .clk, .rst, .read_fifo_level,
        .scanout_valid, .scanout_ready, .scanout_address,
        .write_valid, .write_ready, .write_address, .write_data,
        .refresh_valid, .refresh_ready,
        .memory_valid, .memory_ready, .memory_operation,
        .memory_address, .memory_write_data
    );

    task automatic clear_inputs;
        scanout_valid = 1'b0;
        write_valid = 1'b0;
        refresh_valid = 1'b0;
    endtask

    task automatic retire_request;
        @(negedge clk);
        memory_ready = 1'b1;
        @(posedge clk);
        #1;
        memory_ready = 1'b0;
    endtask

    initial begin
        rst = 1'b1;
        read_fifo_level = 16'd8;
        scanout_address = 32'h1000;
        write_address = 32'h2000;
        write_data = 16'hbeef;
        memory_ready = 1'b0;
        clear_inputs();

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        // Low scanout FIFO wins over a simultaneous renderer write.
        @(negedge clk);
        read_fifo_level = 16'd3;
        scanout_valid = 1'b1;
        write_valid = 1'b1;
        #1;
        if (!scanout_ready || write_ready)
            $fatal(1, "low-water source handshake was incorrect");
        @(posedge clk);
        #1;
        if (!memory_valid || memory_operation != OP_READ ||
            memory_address != scanout_address)
            $fatal(1, "low-water scanout request did not win");
        clear_inputs();
        retire_request();

        // A healthy scanout FIFO leaves bandwidth for rendering.
        @(negedge clk);
        read_fifo_level = 16'd8;
        scanout_valid = 1'b1;
        write_valid = 1'b1;
        #1;
        if (scanout_ready || !write_ready)
            $fatal(1, "healthy-FIFO source handshake was incorrect");
        @(posedge clk);
        #1;
        if (!memory_valid || memory_operation != OP_WRITE ||
            memory_address != write_address || memory_write_data != write_data)
            $fatal(1, "renderer did not progress with a healthy read FIFO");

        // A stalled backend must hold its selected request and backpressure everyone.
        @(negedge clk);
        refresh_valid = 1'b1;
        read_fifo_level = 16'd0;
        repeat (3) begin
            @(posedge clk);
            #1;
            if (!memory_valid || memory_operation != OP_WRITE ||
                memory_address != write_address || memory_write_data != write_data ||
                scanout_ready || write_ready || refresh_ready)
                $fatal(1, "memory request changed while stalled");
        end
        clear_inputs();
        retire_request();

        // Refresh has absolute priority when the output slot is available.
        @(negedge clk);
        read_fifo_level = 16'd8;
        scanout_valid = 1'b1;
        write_valid = 1'b1;
        refresh_valid = 1'b1;
        #1;
        if (!refresh_ready || scanout_ready || write_ready)
            $fatal(1, "refresh source handshake was incorrect");
        @(posedge clk);
        #1;
        if (!memory_valid || memory_operation != OP_REFRESH)
            $fatal(1, "refresh did not preempt traffic");
        clear_inputs();
        retire_request();

        // Even with a healthy FIFO, no more than two writes may pass a pending read.
        @(negedge clk);
        read_fifo_level = 16'd8;
        scanout_valid = 1'b1;
        write_valid = 1'b1;
        memory_ready = 1'b1;
        @(posedge clk); #1;
        if (memory_operation != OP_WRITE) $fatal(1, "first write was not scheduled");
        @(posedge clk); #1;
        if (memory_operation != OP_WRITE) $fatal(1, "second write was not scheduled");
        @(posedge clk); #1;
        if (memory_operation != OP_READ) $fatal(1, "write burst limit did not force a read");

        clear_inputs();
        @(posedge clk);
        #1;
        memory_ready = 1'b0;

        $display("PASS: scanout priority, renderer progress, refresh, burst bound, and stalls");
        $finish;
    end
endmodule
