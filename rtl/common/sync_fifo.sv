`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned WIDTH = 8,
    parameter int unsigned DEPTH = 4
) (
    input  logic clk,
    input  logic rst,
    input  logic in_valid,
    output logic in_ready,
    input  logic [WIDTH-1:0] in_data,
    output logic out_valid,
    input  logic out_ready,
    output logic [WIDTH-1:0] out_data,
    output logic [$clog2(DEPTH + 1)-1:0] count
);
    localparam int unsigned PTR_WIDTH = DEPTH <= 1 ? 1 : $clog2(DEPTH);
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH + 1);

    logic [WIDTH-1:0] memory [0:DEPTH-1];
    logic [PTR_WIDTH-1:0] write_pointer;
    logic [PTR_WIDTH-1:0] read_pointer;
    logic [COUNT_WIDTH-1:0] stored_count;
    logic push;
    logic pop;

    always_comb begin
        in_ready = stored_count < COUNT_WIDTH'(DEPTH);
        out_valid = stored_count != 0;
        out_data = memory[read_pointer];
        count = stored_count;
        push = in_valid && in_ready;
        pop = out_valid && out_ready;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            write_pointer <= '0;
            read_pointer <= '0;
            stored_count <= '0;
        end else begin
            if (push) begin
                memory[write_pointer] <= in_data;
                write_pointer <= int'(write_pointer) == DEPTH - 1
                               ? '0 : write_pointer + 1'b1;
            end
            if (pop) begin
                read_pointer <= int'(read_pointer) == DEPTH - 1
                              ? '0 : read_pointer + 1'b1;
            end

            case ({push, pop})
                2'b10: stored_count <= stored_count + 1'b1;
                2'b01: stored_count <= stored_count - 1'b1;
                default: stored_count <= stored_count;
            endcase
        end
    end
endmodule
