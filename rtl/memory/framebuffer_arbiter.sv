`timescale 1ns/1ps

module framebuffer_arbiter #(
    parameter int unsigned READ_FIFO_LOW_WATER = 256,
    parameter int unsigned MAX_CONSECUTIVE_WRITES = 32
) (
    input  logic clk,
    input  logic rst,
    input  logic [15:0] read_fifo_level,
    input  logic scanout_valid,
    output logic scanout_ready,
    input  logic [31:0] scanout_address,
    input  logic write_valid,
    output logic write_ready,
    input  logic [31:0] write_address,
    input  logic [15:0] write_data,
    input  logic refresh_valid,
    output logic refresh_ready,
    output logic memory_valid,
    input  logic memory_ready,
    output logic [1:0] memory_operation,
    output logic [31:0] memory_address,
    output logic [15:0] memory_write_data
);
    localparam logic [1:0] OP_READ = 2'd0;
    localparam logic [1:0] OP_WRITE = 2'd1;
    localparam logic [1:0] OP_REFRESH = 2'd2;
    localparam int unsigned WRITE_COUNT_WIDTH =
        MAX_CONSECUTIVE_WRITES < 2 ? 1 : $clog2(MAX_CONSECUTIVE_WRITES + 1);

    logic [WRITE_COUNT_WIDTH-1:0] consecutive_writes;
    logic slot_available;
    logic selected_valid;
    logic [1:0] selected_operation;
    logic [31:0] selected_address;
    logic [15:0] selected_write_data;
    logic force_scanout;

    always_comb begin
        slot_available = !memory_valid || memory_ready;
        force_scanout = scanout_valid &&
                        (int'(read_fifo_level) < READ_FIFO_LOW_WATER ||
                         int'(consecutive_writes) >= MAX_CONSECUTIVE_WRITES);

        selected_valid = 1'b0;
        selected_operation = OP_READ;
        selected_address = '0;
        selected_write_data = '0;
        scanout_ready = 1'b0;
        write_ready = 1'b0;
        refresh_ready = 1'b0;

        if (slot_available) begin
            if (refresh_valid) begin
                selected_valid = 1'b1;
                selected_operation = OP_REFRESH;
                refresh_ready = 1'b1;
            end else if (force_scanout) begin
                selected_valid = 1'b1;
                selected_operation = OP_READ;
                selected_address = scanout_address;
                scanout_ready = 1'b1;
            end else if (write_valid) begin
                selected_valid = 1'b1;
                selected_operation = OP_WRITE;
                selected_address = write_address;
                selected_write_data = write_data;
                write_ready = 1'b1;
            end else if (scanout_valid) begin
                selected_valid = 1'b1;
                selected_operation = OP_READ;
                selected_address = scanout_address;
                scanout_ready = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            memory_valid <= 1'b0;
            memory_operation <= OP_READ;
            memory_address <= '0;
            memory_write_data <= '0;
            consecutive_writes <= '0;
        end else if (slot_available) begin
            memory_valid <= selected_valid;
            if (selected_valid) begin
                memory_operation <= selected_operation;
                memory_address <= selected_address;
                memory_write_data <= selected_write_data;
                if (selected_operation == OP_WRITE) begin
                    if (int'(consecutive_writes) < MAX_CONSECUTIVE_WRITES)
                        consecutive_writes <= consecutive_writes + 1'b1;
                end else begin
                    consecutive_writes <= '0;
                end
            end
        end
    end
endmodule
