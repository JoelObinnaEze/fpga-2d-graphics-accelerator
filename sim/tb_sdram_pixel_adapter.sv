`timescale 1ns/1ps

module tb_sdram_pixel_adapter;
    localparam logic [1:0] OP_READ = 2'd0;
    localparam logic [1:0] OP_WRITE = 2'd1;
    localparam logic [1:0] OP_REFRESH = 2'd2;

    logic clk;
    logic rst;
    logic request_valid;
    logic request_ready;
    logic [1:0] request_operation;
    logic [21:0] request_pixel_address;
    logic [15:0] request_write_data;
    logic response_valid;
    logic response_ready;
    logic [15:0] response_read_data;
    logic write_committed;
    logic controller_init_done;
    logic controller_busy_n;
    logic controller_ack;
    logic controller_read_valid;
    logic [31:0] controller_read_data;
    logic controller_write_n;
    logic controller_read_n;
    logic [20:0] controller_address;
    logic [7:0] controller_data_len;
    logic [3:0] controller_data_mask;
    logic [31:0] controller_write_data;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    sdram_pixel_adapter dut (
        .clk,
        .rst,
        .request_valid,
        .request_ready,
        .request_operation,
        .request_pixel_address,
        .request_write_data,
        .response_valid,
        .response_ready,
        .response_read_data,
        .write_committed,
        .controller_init_done,
        .controller_busy_n,
        .controller_ack,
        .controller_read_valid,
        .controller_read_data,
        .controller_write_n,
        .controller_read_n,
        .controller_address,
        .controller_data_len,
        .controller_data_mask,
        .controller_write_data
    );

    task automatic issue_request(
        input logic [1:0] operation,
        input logic [21:0] pixel_address,
        input logic [15:0] write_data
    );
        @(negedge clk);
        request_operation = operation;
        request_pixel_address = pixel_address;
        request_write_data = write_data;
        request_valid = 1'b1;
        #1;
        if (!request_ready)
            $fatal(1, "adapter did not accept an idle request");
        @(posedge clk);
        #1;
        request_valid = 1'b0;
    endtask

    task automatic acknowledge_transaction;
        @(negedge clk);
        controller_busy_n = 1'b0;
        controller_ack = 1'b1;
        @(posedge clk);
        #1;
        controller_ack = 1'b0;
        @(negedge clk);
        controller_busy_n = 1'b1;
    endtask

    task automatic complete_read(input logic [31:0] read_data);
        @(negedge clk);
        controller_busy_n = 1'b0;
        controller_ack = 1'b1;
        @(posedge clk);
        #1;
        controller_ack = 1'b0;
        @(negedge clk);
        controller_read_data = read_data;
        controller_read_valid = 1'b1;
        @(posedge clk);
        #1;
        controller_read_valid = 1'b0;
        @(negedge clk);
        controller_busy_n = 1'b1;
        @(posedge clk);
        #1;
    endtask

    task automatic retire_response;
        response_ready = 1'b1;
        @(posedge clk);
        #1;
        response_ready = 1'b0;
        if (response_valid)
            $fatal(1, "read response did not retire");
    endtask

    initial begin
        rst = 1'b1;
        request_valid = 1'b0;
        request_operation = OP_READ;
        request_pixel_address = '0;
        request_write_data = '0;
        response_ready = 1'b0;
        controller_init_done = 1'b0;
        controller_busy_n = 1'b1;
        controller_ack = 1'b0;
        controller_read_valid = 1'b0;
        controller_read_data = '0;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;
        if (request_ready)
            $fatal(1, "request accepted before controller initialization");
        controller_init_done = 1'b1;

        request_operation = OP_REFRESH;
        request_valid = 1'b1;
        #1;
        if (request_ready)
            $fatal(1, "unsupported explicit refresh was accepted");
        request_valid = 1'b0;

        issue_request(OP_WRITE, 22'd4, 16'h1234);
        if (controller_write_n || !controller_read_n ||
            controller_address != 21'd2 || controller_data_len != 0 ||
            controller_data_mask != 4'b1100 ||
            controller_write_data != 32'h0000_1234)
            $fatal(1, "even-pixel write mapping is incorrect");
        @(posedge clk);
        #1;
        if (!controller_write_n)
            $fatal(1, "write request was not a one-cycle pulse");
        acknowledge_transaction();
        @(posedge clk);
        #1;
        if (!write_committed)
            $fatal(1, "write completion was not reported");

        issue_request(OP_WRITE, 22'd5, 16'habcd);
        if (controller_address != 21'd2 ||
            controller_data_mask != 4'b0011 ||
            controller_write_data != 32'habcd_0000)
            $fatal(1, "odd-pixel write mapping is incorrect");
        acknowledge_transaction();
        @(posedge clk);
        #1;
        if (!write_committed)
            $fatal(1, "odd write completion was not reported");

        issue_request(OP_READ, 22'd5, 16'd0);
        if (controller_read_n || !controller_write_n ||
            controller_address != 21'd2 || controller_data_mask != 0)
            $fatal(1, "read request mapping is incorrect");

        complete_read(32'hdead_beef);
        if (!response_valid || response_read_data != 16'hdead || request_ready)
            $fatal(1, "odd-pixel read response is incorrect");

        repeat (3) begin
            @(posedge clk);
            #1;
            if (!response_valid || response_read_data != 16'hdead)
                $fatal(1, "stalled read response was not held stable");
        end

        retire_response();

        issue_request(OP_READ, 22'd4, 16'd0);
        complete_read(32'hcafe_5678);
        if (!response_valid || response_read_data != 16'h5678)
            $fatal(1, "even-pixel read response is incorrect");
        retire_response();

        $display("PASS: SDRAM pixel packing, request pulses, completion, and response stalls");
        $finish;
    end
endmodule
