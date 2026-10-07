`timescale 1ns/1ps

module tmds_encoder (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] data,
    input  logic       control0,
    input  logic       control1,
    input  logic       data_enable,
    output logic [9:0] symbol
);
    logic [8:0] q_m;
    logic [3:0] data_ones;
    logic [3:0] q_m_ones;
    logic use_xnor;
    logic signed [5:0] balance;
    logic signed [5:0] disparity;

    function automatic logic [3:0] count_ones(input logic [7:0] value);
        logic [3:0] count;

        count = '0;
        for (int bit_index = 0; bit_index < 8; bit_index++)
            count = count + {3'b000, value[bit_index]};
        return count;
    endfunction

    function automatic logic [8:0] transition_minimize(
        input logic [7:0] value,
        input logic       xnor_mode
    );
        logic [8:0] result;

        result[0] = value[0];
        for (int bit_index = 1; bit_index < 8; bit_index++) begin
            result[bit_index] = xnor_mode
                ? ~(result[bit_index - 1] ^ value[bit_index])
                :  (result[bit_index - 1] ^ value[bit_index]);
        end
        result[8] = !xnor_mode;
        return result;
    endfunction

    assign data_ones = count_ones(data);
    assign use_xnor = data_ones > 4 || (data_ones == 4 && !data[0]);
    assign q_m = transition_minimize(data, use_xnor);
    assign q_m_ones = count_ones(q_m[7:0]);
    assign balance = $signed({1'b0, q_m_ones, 1'b0}) - 6'sd8;

    always_ff @(posedge clk) begin
        if (rst) begin
            disparity <= '0;
            symbol <= 10'b1101010100;
        end else if (!data_enable) begin
            disparity <= '0;
            case ({control1, control0})
                2'b00: symbol <= 10'b1101010100;
                2'b01: symbol <= 10'b0010101011;
                2'b10: symbol <= 10'b0101010100;
                2'b11: symbol <= 10'b1010101011;
                default: symbol <= 10'b1101010100;
            endcase
        end else if (disparity == 0 || balance == 0) begin
            symbol <= {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
            disparity <= disparity + (q_m[8] ? balance : -balance);
        end else if ((disparity > 0 && balance > 0) ||
                     (disparity < 0 && balance < 0)) begin
            symbol <= {1'b1, q_m[8], ~q_m[7:0]};
            disparity <= disparity + (q_m[8] ? 6'sd2 : 6'sd0) - balance;
        end else begin
            symbol <= {1'b0, q_m[8], q_m[7:0]};
            disparity <= disparity + balance - (!q_m[8] ? 6'sd2 : 6'sd0);
        end
    end
endmodule
