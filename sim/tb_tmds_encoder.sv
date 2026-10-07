`timescale 1ns/1ps

module tb_tmds_encoder;
    logic clk;
    logic rst;
    logic [7:0] data;
    logic control0;
    logic control1;
    logic data_enable;
    logic [9:0] symbol;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    tmds_encoder dut (
        .clk,
        .rst,
        .data,
        .control0,
        .control1,
        .data_enable,
        .symbol
    );

    task automatic check_symbol(
        input logic       next_data_enable,
        input logic       next_control0,
        input logic       next_control1,
        input logic [7:0] next_data,
        input logic [9:0] expected
    );
        data_enable = next_data_enable;
        control0 = next_control0;
        control1 = next_control1;
        data = next_data;
        @(posedge clk);
        #1;
        if (symbol != expected)
            $fatal(1,
                   "TMDS mismatch: de=%0b c1c0=%0b%0b data=%02x got=%03x expected=%03x",
                   data_enable, control1, control0, data, symbol, expected);
    endtask

    initial begin
        rst = 1'b1;
        data = '0;
        control0 = 1'b0;
        control1 = 1'b0;
        data_enable = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;

        check_symbol(1'b0, 1'b0, 1'b0, 8'h00, 10'b1101010100);
        check_symbol(1'b0, 1'b1, 1'b0, 8'h00, 10'b0010101011);
        check_symbol(1'b0, 1'b0, 1'b1, 8'h00, 10'b0101010100);
        check_symbol(1'b0, 1'b1, 1'b1, 8'h00, 10'b1010101011);

        // Blanking resets running disparity. These are known first-symbol
        // encodings plus a second black pixel that exercises disparity.
        check_symbol(1'b0, 1'b0, 1'b0, 8'h00, 10'b1101010100);
        check_symbol(1'b1, 1'b0, 1'b0, 8'h00, 10'b0100000000);
        check_symbol(1'b1, 1'b0, 1'b0, 8'h00, 10'b1111111111);
        check_symbol(1'b0, 1'b0, 1'b0, 8'h00, 10'b1101010100);
        check_symbol(1'b1, 1'b0, 1'b0, 8'hff, 10'b1000000000);
        check_symbol(1'b0, 1'b0, 1'b0, 8'h00, 10'b1101010100);
        check_symbol(1'b1, 1'b0, 1'b0, 8'h01, 10'b0111111111);

        $display("PASS: DVI control tokens and TMDS running-disparity encoding");
        $finish;
    end
endmodule
