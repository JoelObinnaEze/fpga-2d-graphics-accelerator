`timescale 1ns/1ps

module tang_nano_20k_sdram_bist (
    input  wire        clk_27mhz,
    output wire [5:0]  led_n,
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    output wire [3:0]  O_sdram_dqm,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    inout  wire [31:0] IO_sdram_dq
);
    wire controller_clk;
    wire sdram_clk;
    wire pll_locked;
    logic [3:0] reset_pipeline = '0;
    wire controller_reset_n = reset_pipeline[3];

    wire controller_init_done;
    wire controller_busy_n;
    wire controller_ack;
    wire controller_read_valid;
    wire [31:0] controller_read_data;
    wire controller_write_n;
    wire controller_read_n;
    wire [20:0] controller_address;
    wire [7:0] controller_data_len;
    wire [3:0] controller_data_mask;
    wire [31:0] controller_write_data;
    wire test_busy;
    wire test_pass;
    wire test_fail;
    wire [2:0] failure_code;
    wire [20:0] failure_address;

    logic init_seen;
    logic ack_seen;
    logic read_seen;

    gowin_sdram_clock clock_generator (
        .clk_27mhz,
        .controller_clk,
        .sdram_clk,
        .locked(pll_locked)
    );

    always_ff @(posedge controller_clk or negedge pll_locked) begin
        if (!pll_locked)
            reset_pipeline <= '0;
        else
            reset_pipeline <= {reset_pipeline[2:0], 1'b1};
    end

    sdram_bist memory_test (
        .clk(controller_clk),
        .reset_n(controller_reset_n),
        .controller_init_done,
        .controller_busy_n,
        .controller_ack,
        .controller_read_valid,
        .controller_read_data,
        .controller_write_n,
        .controller_read_n,
        .controller_address,
        .controller_data_len,
        .controller_data_mask,
        .controller_write_data,
        .test_busy,
        .test_pass,
        .test_fail,
        .failure_code,
        .failure_address
    );

    SDRAM_controller_top_SIP controller (
        .I_sdrc_rst_n(controller_reset_n),
        .I_sdrc_clk(controller_clk),
        .I_sdram_clk(sdram_clk),
        .I_sdrc_selfrefresh(1'b0),
        .I_sdrc_power_down(1'b0),
        .I_sdrc_wr_n(controller_write_n),
        .I_sdrc_rd_n(controller_read_n),
        .I_sdrc_addr(controller_address),
        .I_sdrc_data_len(controller_data_len),
        .I_sdrc_dqm(controller_data_mask),
        .I_sdrc_data(controller_write_data),
        .O_sdrc_data(controller_read_data),
        .O_sdrc_init_done(controller_init_done),
        .O_sdrc_busy_n(controller_busy_n),
        .O_sdrc_rd_valid(controller_read_valid),
        .O_sdrc_wrd_ack(controller_ack),
        .O_sdram_clk,
        .O_sdram_cke,
        .O_sdram_cs_n,
        .O_sdram_cas_n,
        .O_sdram_ras_n,
        .O_sdram_wen_n,
        .O_sdram_dqm,
        .O_sdram_addr,
        .O_sdram_ba,
        .IO_sdram_dq
    );

    always_ff @(posedge controller_clk or negedge controller_reset_n) begin
        if (!controller_reset_n) begin
            init_seen <= 1'b0;
            ack_seen <= 1'b0;
            read_seen <= 1'b0;
        end else begin
            if (controller_init_done)
                init_seen <= 1'b1;
            if (controller_ack)
                ack_seen <= 1'b1;
            if (controller_read_valid)
                read_seen <= 1'b1;
        end
    end

    // Active-low final diagnostics, LED0 through LED5: reset released,
    // initialization seen, acknowledgement seen, read data seen, data
    // mismatch, and full BIST pass.
    assign led_n[0] = ~controller_reset_n;
    assign led_n[1] = ~init_seen;
    assign led_n[2] = ~ack_seen;
    assign led_n[3] = ~read_seen;
    assign led_n[4] = ~(test_fail && failure_code == 3'd6);
    assign led_n[5] = ~test_pass;
endmodule
