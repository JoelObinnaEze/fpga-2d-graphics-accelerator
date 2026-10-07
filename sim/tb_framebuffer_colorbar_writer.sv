`timescale 1ns/1ps

module tb_framebuffer_colorbar_writer;
    localparam int unsigned FRAME_WIDTH = 8;
    localparam int unsigned FRAME_HEIGHT = 2;
    // Cross the split-counter carry boundary while checking exact addressing.
    localparam logic [21:0] BASE_ADDRESS = 22'd2040;

    logic clk;
    logic rst;
    logic start_valid;
    logic start_ready;
    logic [21:0] start_pixel_address;
    logic write_valid;
    logic write_ready;
    logic [21:0] write_pixel_address;
    logic [15:0] write_data;
    logic active;
    logic complete;
    int unsigned accepted_writes;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    framebuffer_colorbar_writer #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) dut (
        .clk,
        .rst,
        .start_valid,
        .start_ready,
        .start_pixel_address,
        .write_valid,
        .write_ready,
        .write_pixel_address,
        .write_data,
        .active,
        .complete
    );

    function automatic logic [15:0] expected_color(input int x);
        case (x)
            0: return 16'hffff;
            1: return 16'hffe0;
            2: return 16'h07ff;
            3: return 16'h07e0;
            4: return 16'hf81f;
            5: return 16'hf800;
            6: return 16'h001f;
            default: return 16'h0000;
        endcase
    endfunction

    initial begin
        rst = 1'b1;
        start_valid = 1'b0;
        start_pixel_address = BASE_ADDRESS;
        write_ready = 1'b0;
        accepted_writes = 0;

        repeat (3) @(posedge clk);
        rst = 1'b0;
        #1;
        if (!start_ready || active || complete || write_valid)
            $fatal(1, "color-bar writer reset state was incorrect");

        @(negedge clk);
        start_valid = 1'b1;
        @(posedge clk);
        #1;
        start_valid = 1'b0;
        if (!active || start_ready)
            $fatal(1, "color-bar writer did not start");

        while (active) begin
            logic [21:0] held_address;
            logic [15:0] held_data;
            int expected_x;
            int expected_y;

            @(negedge clk);
            if (!write_valid)
                $fatal(1, "active writer did not present a pixel");
            expected_x = accepted_writes % FRAME_WIDTH;
            expected_y = accepted_writes / FRAME_WIDTH;
            if (write_pixel_address != BASE_ADDRESS + 22'(accepted_writes) ||
                write_data != expected_color(expected_x))
                $fatal(1, "pixel %0d (%0d,%0d) was (%0d,%04x)",
                       accepted_writes, expected_x, expected_y,
                       write_pixel_address, write_data);

            write_ready = accepted_writes % 3 != 1;
            if (!write_ready) begin
                held_address = write_pixel_address;
                held_data = write_data;
                repeat (2) begin
                    @(posedge clk);
                    #1;
                    if (!write_valid || write_pixel_address != held_address ||
                        write_data != held_data)
                        $fatal(1, "color-bar write changed while stalled");
                end
                @(negedge clk);
                write_ready = 1'b1;
            end

            @(posedge clk);
            #1;
            accepted_writes++;
        end

        if (!complete || !start_ready || accepted_writes !=
            FRAME_WIDTH * FRAME_HEIGHT)
            $fatal(1, "color-bar writer completion was incorrect");
        @(posedge clk);
        #1;
        if (complete)
            $fatal(1, "complete must be a one-cycle pulse");

        $display("PASS: full-frame RGB565 color-bar writer with stalls");
        $finish;
    end
endmodule
