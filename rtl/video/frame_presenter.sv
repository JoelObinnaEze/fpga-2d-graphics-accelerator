`timescale 1ns/1ps

module frame_presenter #(
    parameter logic [31:0] BUFFER0_BASE = 32'd0,
    parameter logic [31:0] BUFFER1_BASE = 32'd307200
) (
    input  logic clk,
    input  logic rst,
    input  logic present_valid,
    output logic present_ready,
    input  logic [7:0] present_sequence,
    input  logic writes_committed,
    input  logic vblank_start,
    input  logic prefetch_ready,
    output logic [31:0] front_buffer_base,
    output logic [31:0] draw_buffer_base,
    output logic draw_allowed,
    output logic present_pending,
    output logic prefetch_restart,
    output logic present_done,
    output logic [7:0] completed_sequence
);
    typedef enum logic [1:0] {IDLE, WAIT_VBLANK, WAIT_PREFETCH} state_t;

    state_t state;
    logic [7:0] pending_sequence;

    always_comb begin
        present_ready = state == IDLE;
        draw_allowed = state == IDLE;
        present_pending = state != IDLE;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            pending_sequence <= '0;
            front_buffer_base <= BUFFER0_BASE;
            draw_buffer_base <= BUFFER1_BASE;
            prefetch_restart <= 1'b0;
            present_done <= 1'b0;
            completed_sequence <= '0;
        end else begin
            prefetch_restart <= 1'b0;
            present_done <= 1'b0;

            case (state)
                IDLE: begin
                    if (present_valid) begin
                        pending_sequence <= present_sequence;
                        state <= WAIT_VBLANK;
                    end
                end
                WAIT_VBLANK: begin
                    if (writes_committed && vblank_start) begin
                        front_buffer_base <= draw_buffer_base;
                        draw_buffer_base <= front_buffer_base;
                        prefetch_restart <= 1'b1;
                        state <= WAIT_PREFETCH;
                    end
                end
                WAIT_PREFETCH: begin
                    if (prefetch_ready) begin
                        completed_sequence <= pending_sequence;
                        present_done <= 1'b1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
