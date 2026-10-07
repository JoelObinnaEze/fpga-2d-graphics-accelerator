`timescale 1ns/1ps

module async_fifo #(
    parameter int unsigned WIDTH = 16,
    parameter int unsigned DEPTH = 512
) (
    input  logic write_clk,
    input  logic write_rst,
    input  logic write_valid,
    output logic write_ready,
    input  logic [WIDTH-1:0] write_data,
    output logic [$clog2(DEPTH + 1)-1:0] write_level,
    input  logic read_clk,
    input  logic read_rst,
    output logic read_valid,
    input  logic read_ready,
    output logic [WIDTH-1:0] read_data,
    output logic [$clog2(DEPTH + 1)-1:0] read_level
);
    localparam int unsigned ADDRESS_WIDTH = $clog2(DEPTH);
    localparam int unsigned POINTER_WIDTH = ADDRESS_WIDTH + 1;

    logic [WIDTH-1:0] memory [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] write_binary;
    logic [POINTER_WIDTH-1:0] write_gray;
    logic [POINTER_WIDTH-1:0] read_binary;
    logic [POINTER_WIDTH-1:0] read_gray;

    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0] read_gray_sync1;
    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0] read_gray_sync2;
    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0] write_gray_sync1;
    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0] write_gray_sync2;

    logic [POINTER_WIDTH-1:0] synced_read_binary;
    logic [POINTER_WIDTH-1:0] synced_write_binary;
    logic [POINTER_WIDTH-1:0] read_binary_incremented;

    function automatic logic [POINTER_WIDTH-1:0] binary_to_gray(
        input logic [POINTER_WIDTH-1:0] binary
    );
        binary_to_gray = (binary >> 1) ^ binary;
    endfunction

    function automatic logic [POINTER_WIDTH-1:0] gray_to_binary(
        input logic [POINTER_WIDTH-1:0] gray
    );
        logic [POINTER_WIDTH-1:0] binary;
        begin
            binary[POINTER_WIDTH-1] = gray[POINTER_WIDTH-1];
            for (int bit_index = POINTER_WIDTH - 2;
                 bit_index >= 0; bit_index--)
                binary[bit_index] = binary[bit_index + 1] ^ gray[bit_index];
            gray_to_binary = binary;
        end
    endfunction

    initial begin
        if (DEPTH < 4 || (DEPTH & (DEPTH - 1)) != 0)
            $error("async_fifo DEPTH must be a power of two of at least four");
    end

    always_comb begin
        synced_read_binary = gray_to_binary(read_gray_sync2);
        synced_write_binary = gray_to_binary(write_gray_sync2);
        read_binary_incremented = read_binary + 1'b1;
        write_level = write_binary - synced_read_binary;
        read_level = synced_write_binary - read_binary;
        write_ready = int'(write_level) < DEPTH;
    end

    always_ff @(posedge write_clk) begin
        if (write_rst) begin
            write_binary <= '0;
            write_gray <= '0;
            read_gray_sync1 <= '0;
            read_gray_sync2 <= '0;
        end else begin
            read_gray_sync1 <= read_gray;
            read_gray_sync2 <= read_gray_sync1;

            if (write_valid && write_ready) begin
                memory[write_binary[ADDRESS_WIDTH-1:0]] <= write_data;
                write_binary <= write_binary + 1'b1;
                write_gray <= binary_to_gray(write_binary + 1'b1);
            end
        end
    end

    always_ff @(posedge read_clk) begin
        if (read_rst) begin
            read_binary <= '0;
            read_gray <= '0;
            write_gray_sync1 <= '0;
            write_gray_sync2 <= '0;
            read_valid <= 1'b0;
            read_data <= '0;
        end else begin
            write_gray_sync1 <= write_gray;
            write_gray_sync2 <= write_gray_sync1;

            if (!read_valid) begin
                if (read_level != 0) begin
                    read_data <= memory[read_binary[ADDRESS_WIDTH-1:0]];
                    read_valid <= 1'b1;
                end
            end else if (read_ready) begin
                read_binary <= read_binary_incremented;
                read_gray <= binary_to_gray(read_binary_incremented);
                if (synced_write_binary != read_binary_incremented) begin
                    read_data <= memory[
                        read_binary_incremented[ADDRESS_WIDTH-1:0]
                    ];
                    read_valid <= 1'b1;
                end else begin
                    read_valid <= 1'b0;
                end
            end
        end
    end
endmodule
