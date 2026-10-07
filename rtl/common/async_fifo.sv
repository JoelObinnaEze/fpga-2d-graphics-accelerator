`timescale 1ns/1ps

module async_fifo #(
    parameter int unsigned WIDTH = 16,
    parameter int unsigned DEPTH = 512,
    parameter bit EXTERNAL_CAPACITY_CONTROL = 1'b0
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
    logic [POINTER_WIDTH-1:0] write_binary_incremented;
    logic [POINTER_WIDTH-1:0] write_gray_incremented;
    logic [POINTER_WIDTH-1:0] write_binary_next;
    logic [POINTER_WIDTH-1:0] write_gray_next;
    logic [POINTER_WIDTH-1:0] read_binary_incremented;
    logic write_full;
    logic write_full_current;
    logic write_full_after_write;
    logic write_full_next;
    logic write_fire;
    logic read_empty;
    logic read_empty_after_pop;

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
            // Parallel-prefix XOR conversion has logarithmic rather than
            // pointer-width logic depth in the fast write clock domain.
            binary = gray;
            for (int shift = 1; shift < POINTER_WIDTH; shift <<= 1)
                binary = binary ^ (binary >> shift);
            gray_to_binary = binary;
        end
    endfunction

    initial begin
        if (DEPTH < 4 || (DEPTH & (DEPTH - 1)) != 0)
            $error("async_fifo DEPTH must be a power of two of at least four");
    end

    always_comb begin
        synced_write_binary = gray_to_binary(write_gray_sync2);
        write_ready = EXTERNAL_CAPACITY_CONTROL ? 1'b1 : !write_full;
        write_fire = write_valid && write_ready;
        write_binary_incremented = write_binary + 1'b1;
        write_gray_incremented = binary_to_gray(write_binary_incremented);
        write_binary_next = write_fire ? write_binary_incremented : write_binary;
        write_gray_next = write_fire ? write_gray_incremented : write_gray;
        read_binary_incremented = read_binary + 1'b1;
        write_level = write_binary - synced_read_binary;
        read_level = synced_write_binary - read_binary;
        write_full_current = write_gray ==
                             {~read_gray_sync2[POINTER_WIDTH-1:POINTER_WIDTH-2],
                              read_gray_sync2[POINTER_WIDTH-3:0]};
        write_full_after_write = write_gray_incremented ==
                                 {~read_gray_sync2[POINTER_WIDTH-1:POINTER_WIDTH-2],
                                  read_gray_sync2[POINTER_WIDTH-3:0]};
        write_full_next = write_fire ? write_full_after_write
                                     : write_full_current;
        read_empty = read_gray == write_gray_sync2;
        read_empty_after_pop = binary_to_gray(read_binary_incremented) ==
                               write_gray_sync2;
    end

    always_ff @(posedge write_clk) begin
        if (write_rst) begin
            write_binary <= '0;
            write_gray <= '0;
            write_full <= 1'b0;
            synced_read_binary <= '0;
            read_gray_sync1 <= '0;
            read_gray_sync2 <= '0;
        end else begin
            read_gray_sync1 <= read_gray;
            read_gray_sync2 <= read_gray_sync1;
            // Pipeline the Gray decode before the occupancy subtract. This
            // level is intentionally conservative while a read crosses over.
            synced_read_binary <= gray_to_binary(read_gray_sync2);
            write_binary <= write_binary_next;
            write_gray <= write_gray_next;
            write_full <= write_full_next;

        end
    end

    // FIFO memory contents need no reset. Keeping this write process separate
    // prevents the high-fanout reset tree from becoming part of the RAM WRE
    // timing path.
    always_ff @(posedge write_clk) begin
        if (write_fire)
            memory[write_binary[ADDRESS_WIDTH-1:0]] <= write_data;
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
                if (!read_empty) begin
                    read_data <= memory[read_binary[ADDRESS_WIDTH-1:0]];
                    read_valid <= 1'b1;
                end
            end else if (read_ready) begin
                read_binary <= read_binary_incremented;
                read_gray <= binary_to_gray(read_binary_incremented);
                if (!read_empty_after_pop) begin
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
