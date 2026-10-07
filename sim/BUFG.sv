`timescale 1ns/1ps

module BUFG (
    input  logic I,
    output logic O
);
    always_comb O = I;
endmodule
