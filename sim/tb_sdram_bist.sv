`timescale 1ns/1ps

/* verilator lint_off DECLFILENAME */
module mock_sdram_controller #(
    parameter int unsigned WORD_COUNT = 16,
    parameter bit INJECT_READ_FAULT = 1'b0
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        write_n,
    input  logic        read_n,
    input  logic [20:0] address,
    input  logic [31:0] write_data,
    output logic        init_done,
    output logic        busy_n,
    output logic        ack,
    output logic        read_valid,
    output logic [31:0] read_data,
    output logic [31:0] write_count,
    output logic [31:0] read_count
);
    logic [31:0] memory [0:WORD_COUNT-1];
    logic pending;
    logic pending_read;
    logic [20:0] pending_address;
    logic [2:0] delay_count;
    logic [3:0] init_count;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            init_done <= 1'b0;
            busy_n <= 1'b1;
            ack <= 1'b0;
            read_valid <= 1'b0;
            read_data <= '0;
            write_count <= '0;
            read_count <= '0;
            pending <= 1'b0;
            pending_read <= 1'b0;
            pending_address <= '0;
            delay_count <= '0;
            init_count <= '0;
        end else begin
            ack <= 1'b0;
            read_valid <= 1'b0;

            if (!init_done) begin
                if (init_count == 4)
                    init_done <= 1'b1;
                else
                    init_count <= init_count + 1'b1;
            end

            if (!pending && init_done && busy_n && (!write_n || !read_n)) begin
                pending <= 1'b1;
                pending_read <= !read_n;
                pending_address <= address;
                delay_count <= '0;
                busy_n <= 1'b0;
                if (!write_n) begin
                    memory[address[$clog2(WORD_COUNT)-1:0]] <= write_data;
                    write_count <= write_count + 1'b1;
                end else begin
                    read_count <= read_count + 1'b1;
                end
            end else if (pending) begin
                delay_count <= delay_count + 1'b1;
                if (delay_count == 1)
                    ack <= 1'b1;
                if (pending_read && delay_count == 3) begin
                    read_valid <= 1'b1;
                    read_data <= memory[pending_address[$clog2(WORD_COUNT)-1:0]] ^
                                 ((INJECT_READ_FAULT && pending_address == 5) ?
                                  32'h0000_0001 : 32'h0000_0000);
                end
                if (delay_count == 4) begin
                    pending <= 1'b0;
                    busy_n <= 1'b1;
                end
            end
        end
    end
endmodule
/* verilator lint_on DECLFILENAME */

module tb_sdram_bist;
    localparam int unsigned WORD_COUNT = 16;

    logic clk;
    logic reset_n;

    logic good_init_done;
    logic good_busy_n;
    logic good_ack;
    logic good_read_valid;
    logic [31:0] good_read_data;
    logic good_write_n;
    logic good_read_n;
    logic [20:0] good_address;
    logic [7:0] good_data_len;
    logic [3:0] good_data_mask;
    logic [31:0] good_write_data;
    logic good_test_busy;
    logic good_test_pass;
    logic good_test_fail;
    logic [2:0] good_failure_code;
    logic [20:0] good_failure_address;
    logic [31:0] good_write_count;
    logic [31:0] good_read_count;

    logic bad_init_done;
    logic bad_busy_n;
    logic bad_ack;
    logic bad_read_valid;
    logic [31:0] bad_read_data;
    logic bad_write_n;
    logic bad_read_n;
    logic [20:0] bad_address;
    logic [7:0] bad_data_len;
    logic [3:0] bad_data_mask;
    logic [31:0] bad_write_data;
    logic bad_test_busy;
    logic bad_test_pass;
    logic bad_test_fail;
    logic [2:0] bad_failure_code;
    logic [20:0] bad_failure_address;
    logic [31:0] bad_write_count;
    logic [31:0] bad_read_count;

    logic timeout_write_n;
    logic timeout_read_n;
    logic [20:0] timeout_address;
    logic [7:0] timeout_data_len;
    logic [3:0] timeout_data_mask;
    logic [31:0] timeout_write_data;
    logic timeout_test_busy;
    logic timeout_test_pass;
    logic timeout_test_fail;
    logic [2:0] timeout_failure_code;
    logic [20:0] timeout_failure_address;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    sdram_bist #(
        .WORD_COUNT(WORD_COUNT),
        .INIT_TIMEOUT_CYCLES(32),
        .TRANSACTION_TIMEOUT_CYCLES(32)
    ) good_dut (
        .clk,
        .reset_n,
        .controller_init_done(good_init_done),
        .controller_busy_n(good_busy_n),
        .controller_ack(good_ack),
        .controller_read_valid(good_read_valid),
        .controller_read_data(good_read_data),
        .controller_write_n(good_write_n),
        .controller_read_n(good_read_n),
        .controller_address(good_address),
        .controller_data_len(good_data_len),
        .controller_data_mask(good_data_mask),
        .controller_write_data(good_write_data),
        .test_busy(good_test_busy),
        .test_pass(good_test_pass),
        .test_fail(good_test_fail),
        .failure_code(good_failure_code),
        .failure_address(good_failure_address)
    );

    mock_sdram_controller #(
        .WORD_COUNT(WORD_COUNT)
    ) good_controller (
        .clk,
        .reset_n,
        .write_n(good_write_n),
        .read_n(good_read_n),
        .address(good_address),
        .write_data(good_write_data),
        .init_done(good_init_done),
        .busy_n(good_busy_n),
        .ack(good_ack),
        .read_valid(good_read_valid),
        .read_data(good_read_data),
        .write_count(good_write_count),
        .read_count(good_read_count)
    );

    sdram_bist #(
        .WORD_COUNT(WORD_COUNT),
        .INIT_TIMEOUT_CYCLES(32),
        .TRANSACTION_TIMEOUT_CYCLES(32)
    ) bad_dut (
        .clk,
        .reset_n,
        .controller_init_done(bad_init_done),
        .controller_busy_n(bad_busy_n),
        .controller_ack(bad_ack),
        .controller_read_valid(bad_read_valid),
        .controller_read_data(bad_read_data),
        .controller_write_n(bad_write_n),
        .controller_read_n(bad_read_n),
        .controller_address(bad_address),
        .controller_data_len(bad_data_len),
        .controller_data_mask(bad_data_mask),
        .controller_write_data(bad_write_data),
        .test_busy(bad_test_busy),
        .test_pass(bad_test_pass),
        .test_fail(bad_test_fail),
        .failure_code(bad_failure_code),
        .failure_address(bad_failure_address)
    );

    mock_sdram_controller #(
        .WORD_COUNT(WORD_COUNT),
        .INJECT_READ_FAULT(1'b1)
    ) bad_controller (
        .clk,
        .reset_n,
        .write_n(bad_write_n),
        .read_n(bad_read_n),
        .address(bad_address),
        .write_data(bad_write_data),
        .init_done(bad_init_done),
        .busy_n(bad_busy_n),
        .ack(bad_ack),
        .read_valid(bad_read_valid),
        .read_data(bad_read_data),
        .write_count(bad_write_count),
        .read_count(bad_read_count)
    );

    sdram_bist #(
        .WORD_COUNT(WORD_COUNT),
        .INIT_TIMEOUT_CYCLES(8),
        .TRANSACTION_TIMEOUT_CYCLES(8)
    ) timeout_dut (
        .clk,
        .reset_n,
        .controller_init_done(1'b0),
        .controller_busy_n(1'b1),
        .controller_ack(1'b0),
        .controller_read_valid(1'b0),
        .controller_read_data(32'd0),
        .controller_write_n(timeout_write_n),
        .controller_read_n(timeout_read_n),
        .controller_address(timeout_address),
        .controller_data_len(timeout_data_len),
        .controller_data_mask(timeout_data_mask),
        .controller_write_data(timeout_write_data),
        .test_busy(timeout_test_busy),
        .test_pass(timeout_test_pass),
        .test_fail(timeout_test_fail),
        .failure_code(timeout_failure_code),
        .failure_address(timeout_failure_address)
    );

    initial begin
        logic completed;

        completed = 1'b0;
        reset_n = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        reset_n = 1'b1;

        repeat (2000) begin
            @(posedge clk);
            #1;
            if (good_test_pass && bad_test_fail && timeout_test_fail) begin
                if (good_test_fail || !good_test_pass || good_test_busy)
                    $fatal(1, "successful SDRAM BIST status is inconsistent");
                if (bad_test_pass || !bad_test_fail || bad_test_busy)
                    $fatal(1, "read corruption did not produce sticky failure");
                if (timeout_test_pass || !timeout_test_fail || timeout_test_busy)
                    $fatal(1, "initialization timeout did not produce sticky failure");
                if (good_failure_code != 3'd0 || good_failure_address != 0)
                    $fatal(1, "successful BIST reported failure diagnostics");
                if (bad_failure_code != 3'd6 || bad_failure_address != 5)
                    $fatal(1, "read corruption diagnostics are incorrect: code=%0d address=%0d",
                           bad_failure_code, bad_failure_address);
                if (timeout_failure_code != 3'd1 || timeout_failure_address != 0)
                    $fatal(1, "initialization-timeout diagnostics are incorrect");
                if (good_write_count != WORD_COUNT * 2 ||
                    good_read_count != WORD_COUNT * 2)
                    $fatal(1, "BIST did not complete both full pattern passes");
                if (good_data_len != 0 || good_data_mask != 0)
                    $fatal(1, "BIST must issue unmasked single-word transactions");
                if (bad_data_len != 0 || bad_data_mask != 0 ||
                    bad_write_count != WORD_COUNT || bad_read_count != 6)
                    $fatal(1, "corruption case did not fail at the expected address");
                if (!timeout_write_n || !timeout_read_n ||
                    timeout_address != 0 || timeout_data_len != 0 ||
                    timeout_data_mask != 0 || timeout_write_data != 0)
                    $fatal(1, "timed-out BIST issued an unexpected transaction");

                $display("PASS: two-pattern SDRAM BIST, corruption detection, and timeout");
                completed = 1'b1;
                break;
            end
        end

        if (!completed)
            $fatal(1, "SDRAM BIST testbench timed out");
        $finish;
    end
endmodule
