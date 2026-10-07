`timescale 1ns/1ps

module tang_nano_20k_led #(
    parameter int unsigned HALF_PERIOD_CYCLES = 13_500_000
) (
    input  logic clk_27mhz,
    output wire  led0_n
);
    localparam int unsigned COUNTER_WIDTH =
        HALF_PERIOD_CYCLES <= 1 ? 1 : $clog2(HALF_PERIOD_CYCLES);

    logic clk_global;

    // The Gowin configuration bitstream establishes these power-up values.
    /* verilator lint_off PROCASSINIT */
    logic [COUNTER_WIDTH-1:0] counter = '0;
    logic led_state_n = 1'b1;
    /* verilator lint_on PROCASSINIT */

    BUFG clock_buffer (
        .I(clk_27mhz),
        .O(clk_global)
    );

    assign led0_n = led_state_n;

    always_ff @(posedge clk_global) begin
        if (counter == COUNTER_WIDTH'(HALF_PERIOD_CYCLES - 1)) begin
            counter <= '0;
            led_state_n <= ~led_state_n;
        end else begin
            counter <= counter + 1'b1;
        end
    end
endmodule
