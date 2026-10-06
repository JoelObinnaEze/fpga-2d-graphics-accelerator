`timescale 1ns/1ps

module tb_frame_presenter;
    logic clk;
    logic rst;
    logic present_valid;
    logic present_ready;
    logic [7:0] present_sequence;
    logic writes_committed;
    logic vblank_start;
    logic prefetch_ready;
    logic [31:0] front_buffer_base;
    logic [31:0] draw_buffer_base;
    logic draw_allowed;
    logic present_pending;
    logic prefetch_restart;
    logic present_done;
    logic [7:0] completed_sequence;
    int restart_count;
    int completion_count;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    frame_presenter #(
        .BUFFER0_BASE(32'd0),
        .BUFFER1_BASE(32'd1000)
    ) dut (
        .clk, .rst,
        .present_valid, .present_ready, .present_sequence,
        .writes_committed, .vblank_start, .prefetch_ready,
        .front_buffer_base, .draw_buffer_base,
        .draw_allowed, .present_pending,
        .prefetch_restart, .present_done, .completed_sequence
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            restart_count <= 0;
            completion_count <= 0;
        end else begin
            if (prefetch_restart)
                restart_count <= restart_count + 1;
            if (present_done)
                completion_count <= completion_count + 1;
        end
    end

    task automatic pulse_present(input logic [7:0] sequence_id);
        @(negedge clk);
        if (!present_ready)
            $fatal(1, "present request was not ready");
        present_sequence = sequence_id;
        present_valid = 1'b1;
        @(posedge clk);
        #1;
        present_valid = 1'b0;
    endtask

    task automatic pulse_vblank;
        @(negedge clk);
        vblank_start = 1'b1;
        @(posedge clk);
        #1;
        vblank_start = 1'b0;
    endtask

    task automatic pulse_prefetch_ready;
        @(negedge clk);
        prefetch_ready = 1'b1;
        @(posedge clk);
        #1;
        prefetch_ready = 1'b0;
    endtask

    initial begin
        rst = 1'b1;
        present_valid = 1'b0;
        present_sequence = '0;
        writes_committed = 1'b0;
        vblank_start = 1'b0;
        prefetch_ready = 1'b0;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;
        if (front_buffer_base != 0 || draw_buffer_base != 1000 ||
            !draw_allowed || present_pending)
            $fatal(1, "reset buffer ownership was incorrect");

        pulse_present(8'h10);
        if (draw_allowed || !present_pending || present_ready)
            $fatal(1, "accepted PRESENT did not lock the draw buffer");

        pulse_vblank();
        if (front_buffer_base != 0 || restart_count != 0)
            $fatal(1, "frame swapped before writes committed");

        writes_committed = 1'b1;
        repeat (2) @(posedge clk);
        if (front_buffer_base != 0)
            $fatal(1, "frame swapped outside VBlank");

        pulse_vblank();
        if (front_buffer_base != 1000 || draw_buffer_base != 0 ||
            !prefetch_restart || restart_count != 0 || completion_count != 0)
            $fatal(1, "committed frame did not swap and restart prefetch at VBlank");

        @(posedge clk);
        #1;
        if (prefetch_restart || restart_count != 1)
            $fatal(1, "prefetch restart was not a single pulse");
        repeat (2) @(posedge clk);
        if (draw_allowed || !present_pending || completion_count != 0)
            $fatal(1, "presentation completed before prefetch restart was ready");

        pulse_prefetch_ready();
        if (!present_done || completed_sequence != 8'h10 ||
            !draw_allowed || present_pending || completion_count != 0)
            $fatal(1, "presentation completion was not acknowledged correctly");
        @(posedge clk);
        #1;
        if (present_done || completion_count != 1)
            $fatal(1, "presentation completion was not a single pulse");

        // A second request swaps ownership back and reports its own sequence.
        pulse_present(8'h11);
        pulse_vblank();
        pulse_prefetch_ready();
        if (!present_done || completed_sequence != 8'h11 ||
            front_buffer_base != 0 || draw_buffer_base != 1000)
            $fatal(1, "consecutive presentation did not preserve ownership/sequence");

        // Reset while pending cancels the request and restores deterministic ownership.
        pulse_present(8'h12);
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;
        if (front_buffer_base != 0 || draw_buffer_base != 1000 ||
            present_pending || !draw_allowed || present_done)
            $fatal(1, "reset did not cancel pending presentation");

        $display("PASS: delayed writes, VBlank swap, prefetch restart, sequences, and reset");
        $finish;
    end
endmodule
