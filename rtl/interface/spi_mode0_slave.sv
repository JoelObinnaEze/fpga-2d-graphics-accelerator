`timescale 1ns/1ps

module spi_mode0_slave (
    input  logic clk,
    input  logic rst,
    input  logic spi_sclk,
    input  logic spi_cs_n,
    input  logic spi_mosi,
    output logic spi_miso,
    input  logic [7:0] status_byte,
    output logic frame_start,
    output logic frame_end,
    output logic byte_valid,
    input  logic byte_ready,
    output logic [7:0] byte_data,
    output logic partial_byte_error,
    output logic downstream_overflow
);
    logic sclk_meta;
    logic sclk_sync;
    logic sclk_previous;
    logic cs_meta;
    logic cs_sync;
    logic cs_previous;
    logic mosi_meta;
    logic mosi_sync;
    logic [7:0] receive_shift;
    logic [7:0] transmit_shift;
    logic [2:0] bit_count;
    logic sclk_rising;
    logic sclk_falling;
    logic cs_falling;
    logic cs_rising;

    always_comb begin
        sclk_rising = sclk_sync && !sclk_previous;
        sclk_falling = !sclk_sync && sclk_previous;
        cs_falling = !cs_sync && cs_previous;
        cs_rising = cs_sync && !cs_previous;
        spi_miso = spi_cs_n ? 1'b0 : transmit_shift[7];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            sclk_meta <= 1'b0;
            sclk_sync <= 1'b0;
            sclk_previous <= 1'b0;
            cs_meta <= 1'b1;
            cs_sync <= 1'b1;
            cs_previous <= 1'b1;
            mosi_meta <= 1'b0;
            mosi_sync <= 1'b0;
            receive_shift <= '0;
            transmit_shift <= '0;
            bit_count <= '0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
            byte_valid <= 1'b0;
            byte_data <= '0;
            partial_byte_error <= 1'b0;
            downstream_overflow <= 1'b0;
        end else begin
            sclk_meta <= spi_sclk;
            sclk_sync <= sclk_meta;
            sclk_previous <= sclk_sync;
            cs_meta <= spi_cs_n;
            cs_sync <= cs_meta;
            cs_previous <= cs_sync;
            mosi_meta <= spi_mosi;
            mosi_sync <= mosi_meta;

            frame_start <= 1'b0;
            frame_end <= 1'b0;
            byte_valid <= 1'b0;
            partial_byte_error <= 1'b0;
            downstream_overflow <= 1'b0;

            if (cs_falling) begin
                receive_shift <= '0;
                transmit_shift <= status_byte;
                bit_count <= '0;
                frame_start <= 1'b1;
            end else if (cs_rising) begin
                frame_end <= 1'b1;
                partial_byte_error <= bit_count != 0;
                bit_count <= '0;
            end else if (!cs_sync) begin
                if (sclk_rising) begin
                    receive_shift <= {receive_shift[6:0], mosi_sync};
                    if (bit_count == 3'd7) begin
                        byte_data <= {receive_shift[6:0], mosi_sync};
                        byte_valid <= 1'b1;
                        downstream_overflow <= !byte_ready;
                        bit_count <= '0;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end

                if (sclk_falling) begin
                    transmit_shift <= bit_count == 0
                                    ? status_byte
                                    : {transmit_shift[6:0], 1'b0};
                end
            end
        end
    end
endmodule
