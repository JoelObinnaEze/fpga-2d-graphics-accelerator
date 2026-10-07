`timescale 1ns/1ps

module sdram_pixel_adapter (
    input  logic        clk,
    input  logic        rst,
    input  logic        request_valid,
    output logic        request_ready,
    input  logic [1:0]  request_operation,
    input  logic [21:0] request_pixel_address,
    input  logic [15:0] request_write_data,
    output logic        response_valid,
    input  logic        response_ready,
    output logic [31:0] response_read_data,
    output logic        write_committed,
    input  logic        controller_init_done,
    input  logic        controller_busy_n,
    input  logic        controller_ack,
    input  logic        controller_read_valid,
    input  logic [31:0] controller_read_data,
    output logic        controller_write_n,
    output logic        controller_read_n,
    output logic [20:0] controller_address,
    output logic [7:0]  controller_data_len,
    output logic [3:0]  controller_data_mask,
    output logic [31:0] controller_write_data
);
    localparam logic [1:0] OP_READ = 2'd0;
    localparam logic [1:0] OP_WRITE = 2'd1;

    typedef enum logic [1:0] {
        IDLE,
        WAIT_WRITE,
        WAIT_READ,
        HOLD_RESPONSE
    } state_t;

    state_t state;
    logic ack_seen;
    logic read_seen;

    assign request_ready = state == IDLE && controller_init_done &&
                           controller_busy_n &&
                           (request_operation == OP_READ ||
                            request_operation == OP_WRITE);
    assign response_valid = state == HOLD_RESPONSE;
    assign controller_data_len = 8'd0;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            ack_seen <= 1'b0;
            read_seen <= 1'b0;
            response_read_data <= '0;
            write_committed <= 1'b0;
            controller_write_n <= 1'b1;
            controller_read_n <= 1'b1;
            controller_address <= '0;
            controller_data_mask <= '0;
            controller_write_data <= '0;
        end else begin
            controller_write_n <= 1'b1;
            controller_read_n <= 1'b1;
            write_committed <= 1'b0;

            case (state)
                IDLE: begin
                    if (request_valid && request_ready) begin
                        controller_address <= request_pixel_address[21:1];
                        ack_seen <= 1'b0;
                        read_seen <= 1'b0;

                        if (request_operation == OP_WRITE) begin
                            controller_data_mask <= request_pixel_address[0]
                                                  ? 4'b0011 : 4'b1100;
                            controller_write_data <= request_pixel_address[0]
                                                   ? {request_write_data, 16'd0}
                                                   : {16'd0, request_write_data};
                            controller_write_n <= 1'b0;
                            state <= WAIT_WRITE;
                        end else if (request_operation == OP_READ) begin
                            controller_data_mask <= 4'b0000;
                            controller_read_n <= 1'b0;
                            state <= WAIT_READ;
                        end
                    end
                end

                WAIT_WRITE: begin
                    if (controller_ack)
                        ack_seen <= 1'b1;

                    if ((ack_seen || controller_ack) && controller_busy_n) begin
                        write_committed <= 1'b1;
                        state <= IDLE;
                    end
                end

                WAIT_READ: begin
                    if (controller_ack)
                        ack_seen <= 1'b1;
                    if (controller_read_valid) begin
                        read_seen <= 1'b1;
                        response_read_data <= controller_read_data;
                    end

                    if ((ack_seen || controller_ack) &&
                        (read_seen || controller_read_valid) &&
                        controller_busy_n) begin
                        state <= HOLD_RESPONSE;
                    end
                end

                HOLD_RESPONSE: begin
                    if (response_ready)
                        state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
