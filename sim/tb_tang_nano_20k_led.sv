`timescale 1ns/1ps

module tb_tang_nano_20k_led;
    localparam int unsigned HALF_PERIOD_CYCLES = 4;

    logic clk_27mhz;
    logic led0_n;

    initial begin
        clk_27mhz = 1'b0;
        forever #5 clk_27mhz = ~clk_27mhz;
    end

    tang_nano_20k_led #(
        .HALF_PERIOD_CYCLES(HALF_PERIOD_CYCLES)
    ) dut (
        .clk_27mhz,
        .led0_n
    );

    task automatic check_led(input logic expected, input int cycle);
        if (led0_n !== expected)
            $fatal(1, "LED0 mismatch after cycle %0d: got %0b, expected %0b",
                   cycle, led0_n, expected);
    endtask

    initial begin
        #1;
        check_led(1'b1, 0);

        for (int cycle = 1; cycle <= 2 * HALF_PERIOD_CYCLES; cycle++) begin
            @(posedge clk_27mhz);
            #1;
            if (cycle < HALF_PERIOD_CYCLES)
                check_led(1'b1, cycle);
            else if (cycle < 2 * HALF_PERIOD_CYCLES)
                check_led(1'b0, cycle);
            else
                check_led(1'b1, cycle);
        end

        $display("PASS: active-low LED0 toggles every %0d clock cycles",
                 HALF_PERIOD_CYCLES);
        $finish;
    end
endmodule
