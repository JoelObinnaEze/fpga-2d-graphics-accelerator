`timescale 1ns/1ps

module sdram_bist #(
    parameter int unsigned WORD_COUNT = 2_097_152,
    parameter int unsigned INIT_TIMEOUT_CYCLES = 5_000_000,
    parameter int unsigned TRANSACTION_TIMEOUT_CYCLES = 65_536
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        controller_init_done,
    input  logic        controller_busy_n,
    input  logic        controller_ack,
    input  logic        controller_read_valid,
    input  logic [31:0] controller_read_data,
    output logic        controller_write_n,
    output logic        controller_read_n,
    output logic [20:0] controller_address,
    output logic [7:0]  controller_data_len,
    output logic [3:0]  controller_data_mask,
    output logic [31:0] controller_write_data,
    output logic        test_busy,
    output logic        test_pass,
    output logic        test_fail,
    output logic [2:0]  failure_code,
    output logic [20:0] failure_address
);
    localparam logic [2:0] FAILURE_NONE = 3'd0;
    localparam logic [2:0] FAILURE_INIT_TIMEOUT = 3'd1;
    localparam logic [2:0] FAILURE_WRITE_REQUEST_TIMEOUT = 3'd2;
    localparam logic [2:0] FAILURE_WRITE_WAIT_TIMEOUT = 3'd3;
    localparam logic [2:0] FAILURE_READ_REQUEST_TIMEOUT = 3'd4;
    localparam logic [2:0] FAILURE_READ_WAIT_TIMEOUT = 3'd5;
    localparam logic [2:0] FAILURE_DATA_MISMATCH = 3'd6;
    localparam logic [2:0] FAILURE_INTERNAL = 3'd7;
    typedef enum logic [2:0] {
        WAIT_INIT,
        WRITE_REQUEST,
        WRITE_WAIT,
        READ_REQUEST,
        READ_WAIT,
        READ_CHECK,
        PASS,
        FAIL
    } state_t;

    state_t state;
    logic [20:0] address;
    logic invert_pattern;
    logic ack_seen;
    logic read_seen;
    logic [31:0] expected_read_data;
    logic [31:0] read_mismatch;
    logic [31:0] watchdog;

    function automatic logic [31:0] pattern_for(
        input logic [20:0] pattern_address,
        input logic        invert
    );
        logic [31:0] base_pattern;
        begin
            // Every word address maps to a unique word, then the second pass
            // complements every bit to exercise both stored polarities.
            base_pattern = 32'hA5A5_5A5A ^
                           {pattern_address, pattern_address[10:0]};
            pattern_for = base_pattern ^ {32{invert}};
        end
    endfunction

    assign controller_data_len = 8'd0;
    assign controller_data_mask = 4'd0;
    assign test_busy = !test_pass && !test_fail;

    initial begin
        if (WORD_COUNT == 0 || WORD_COUNT > 2_097_152)
            $error("WORD_COUNT must be in the range 1..2097152");
        if (INIT_TIMEOUT_CYCLES == 0 || TRANSACTION_TIMEOUT_CYCLES == 0)
            $error("SDRAM BIST timeouts must be nonzero");
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= WAIT_INIT;
            address <= '0;
            invert_pattern <= 1'b0;
            ack_seen <= 1'b0;
            read_seen <= 1'b0;
            expected_read_data <= '0;
            read_mismatch <= '0;
            watchdog <= '0;
            controller_write_n <= 1'b1;
            controller_read_n <= 1'b1;
            controller_address <= '0;
            controller_write_data <= '0;
            test_pass <= 1'b0;
            test_fail <= 1'b0;
            failure_code <= FAILURE_NONE;
            failure_address <= '0;
        end else begin
            controller_write_n <= 1'b1;
            controller_read_n <= 1'b1;

            case (state)
                WAIT_INIT: begin
                    if (controller_init_done && controller_busy_n) begin
                        state <= WRITE_REQUEST;
                        watchdog <= '0;
                    end else if (watchdog >= INIT_TIMEOUT_CYCLES - 1) begin
                        state <= FAIL;
                        test_fail <= 1'b1;
                        failure_code <= FAILURE_INIT_TIMEOUT;
                        failure_address <= address;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                WRITE_REQUEST: begin
                    if (controller_busy_n) begin
                        controller_address <= address;
                        controller_write_data <= pattern_for(address, invert_pattern);
                        controller_write_n <= 1'b0;
                        ack_seen <= 1'b0;
                        watchdog <= '0;
                        state <= WRITE_WAIT;
                    end else if (watchdog >= TRANSACTION_TIMEOUT_CYCLES - 1) begin
                        state <= FAIL;
                        test_fail <= 1'b1;
                        failure_code <= FAILURE_WRITE_REQUEST_TIMEOUT;
                        failure_address <= address;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                WRITE_WAIT: begin
                    if (controller_ack)
                        ack_seen <= 1'b1;

                    if ((ack_seen || controller_ack) && controller_busy_n) begin
                        watchdog <= '0;
                        if (address == 21'(WORD_COUNT - 1)) begin
                            address <= '0;
                            state <= READ_REQUEST;
                        end else begin
                            address <= address + 1'b1;
                            state <= WRITE_REQUEST;
                        end
                    end else if (watchdog >= TRANSACTION_TIMEOUT_CYCLES - 1) begin
                        state <= FAIL;
                        test_fail <= 1'b1;
                        failure_code <= FAILURE_WRITE_WAIT_TIMEOUT;
                        failure_address <= address;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                READ_REQUEST: begin
                    if (controller_busy_n) begin
                        controller_address <= address;
                        expected_read_data <= pattern_for(address, invert_pattern);
                        controller_read_n <= 1'b0;
                        ack_seen <= 1'b0;
                        read_seen <= 1'b0;
                        read_mismatch <= '0;
                        watchdog <= '0;
                        state <= READ_WAIT;
                    end else if (watchdog >= TRANSACTION_TIMEOUT_CYCLES - 1) begin
                        state <= FAIL;
                        test_fail <= 1'b1;
                        failure_code <= FAILURE_READ_REQUEST_TIMEOUT;
                        failure_address <= address;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                READ_WAIT: begin
                    if (controller_ack)
                        ack_seen <= 1'b1;
                    if (controller_read_valid) begin
                        read_seen <= 1'b1;
                        read_mismatch <= controller_read_data ^ expected_read_data;
                    end

                    if ((ack_seen || controller_ack) &&
                        (read_seen || controller_read_valid) &&
                        controller_busy_n) begin
                        watchdog <= '0;
                        state <= READ_CHECK;
                    end else if (watchdog >= TRANSACTION_TIMEOUT_CYCLES - 1) begin
                        state <= FAIL;
                        test_fail <= 1'b1;
                        failure_code <= FAILURE_READ_WAIT_TIMEOUT;
                        failure_address <= address;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                READ_CHECK: begin
                    if (|read_mismatch) begin
                        state <= FAIL;
                        test_fail <= 1'b1;
                        failure_code <= FAILURE_DATA_MISMATCH;
                        failure_address <= address;
                    end else if (address == 21'(WORD_COUNT - 1)) begin
                        address <= '0;
                        if (invert_pattern) begin
                            state <= PASS;
                            test_pass <= 1'b1;
                        end else begin
                            invert_pattern <= 1'b1;
                            state <= WRITE_REQUEST;
                        end
                    end else begin
                        address <= address + 1'b1;
                        state <= READ_REQUEST;
                    end
                end

                PASS: begin
                    test_pass <= 1'b1;
                end

                FAIL: begin
                    test_fail <= 1'b1;
                end

                default: begin
                    state <= FAIL;
                    test_fail <= 1'b1;
                    failure_code <= FAILURE_INTERNAL;
                    failure_address <= address;
                end
            endcase
        end
    end
endmodule
