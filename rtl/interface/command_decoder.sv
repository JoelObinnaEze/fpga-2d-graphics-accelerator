`timescale 1ns/1ps

module command_decoder (
    input  logic clk,
    input  logic rst,
    input  logic frame_start,
    input  logic frame_end,
    input  logic byte_valid,
    output logic byte_ready,
    input  logic [7:0] byte_data,
    output logic command_valid,
    input  logic command_ready,
    output command_pkg::command_t command,
    output logic protocol_error,
    output logic [15:0] protocol_error_count
);
    import command_pkg::*;

    typedef enum logic [3:0] {
        IDLE,
        EXPECT_MAGIC,
        EXPECT_OPCODE,
        EXPECT_LENGTH,
        EXPECT_SEQUENCE,
        EXPECT_PAYLOAD,
        EXPECT_CRC,
        WAIT_FRAME_END,
        DISCARD_FRAME
    } state_t;

    state_t state;
    logic [7:0] opcode;
    logic [7:0] payload_length;
    logic [7:0] sequence_id;
    logic [3:0] payload_index;
    logic [7:0] payload [0:9];
    logic [7:0] running_crc;
    command_t decoded_command;

    function automatic logic [7:0] expected_length(input logic [7:0] value);
        case (value)
            OP_CLEAR:       return 8'd2;
            OP_DRAW_RECT:   return 8'd10;
            OP_DRAW_SPRITE: return 8'd6;
            OP_PRESENT:     return 8'd0;
            default:        return 8'hff;
        endcase
    endfunction

    function automatic logic [7:0] crc8_next(
        input logic [7:0] crc_in,
        input logic [7:0] data
    );
        logic [7:0] crc;
        crc = crc_in;
        for (int bit_index = 0; bit_index < 8; bit_index++) begin
            crc = (crc[7] ^ data[7-bit_index])
                ? {crc[6:0], 1'b0} ^ 8'h07
                : {crc[6:0], 1'b0};
        end
        return crc;
    endfunction

    always_comb begin
        byte_ready = !command_valid && state inside {
            EXPECT_MAGIC, EXPECT_OPCODE, EXPECT_LENGTH, EXPECT_SEQUENCE,
            EXPECT_PAYLOAD, EXPECT_CRC, DISCARD_FRAME
        };

        decoded_command = '0;
        decoded_command.opcode = opcode_t'(opcode);
        decoded_command.sequence_id = sequence_id;
        case (opcode)
            OP_CLEAR: begin
                decoded_command.arg0 = {payload[1], payload[0]};
            end
            OP_DRAW_RECT: begin
                decoded_command.arg0 = {payload[1], payload[0]};
                decoded_command.arg1 = {payload[3], payload[2]};
                decoded_command.arg2 = {payload[5], payload[4]};
                decoded_command.arg3 = {payload[7], payload[6]};
                decoded_command.arg4 = {payload[9], payload[8]};
            end
            OP_DRAW_SPRITE: begin
                decoded_command.arg0 = {payload[1], payload[0]};
                decoded_command.arg1 = {payload[3], payload[2]};
                decoded_command.arg2 = {payload[5], payload[4]};
            end
            default: decoded_command = decoded_command;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            opcode <= '0;
            payload_length <= '0;
            sequence_id <= '0;
            payload_index <= '0;
            running_crc <= '0;
            command <= '0;
            command_valid <= 1'b0;
            protocol_error <= 1'b0;
            protocol_error_count <= '0;
        end else begin
            protocol_error <= 1'b0;
            if (command_valid && command_ready)
                command_valid <= 1'b0;

            if (frame_start) begin
                if (state != IDLE || command_valid) begin
                    state <= DISCARD_FRAME;
                    protocol_error <= 1'b1;
                    if (protocol_error_count != 16'hffff)
                        protocol_error_count <= protocol_error_count + 1'b1;
                end else begin
                    state <= EXPECT_MAGIC;
                    running_crc <= '0;
                    payload_index <= '0;
                end
            end else if (frame_end) begin
                if (state == WAIT_FRAME_END || state == DISCARD_FRAME || state == IDLE) begin
                    state <= IDLE;
                end else begin
                    state <= IDLE;
                    protocol_error <= 1'b1;
                    if (protocol_error_count != 16'hffff)
                        protocol_error_count <= protocol_error_count + 1'b1;
                end
            end else if (byte_valid && byte_ready) begin
                case (state)
                    EXPECT_MAGIC: begin
                        if (byte_data == 8'ha5) begin
                            state <= EXPECT_OPCODE;
                        end else begin
                            state <= DISCARD_FRAME;
                            protocol_error <= 1'b1;
                            if (protocol_error_count != 16'hffff)
                                protocol_error_count <= protocol_error_count + 1'b1;
                        end
                    end
                    EXPECT_OPCODE: begin
                        opcode <= byte_data;
                        running_crc <= crc8_next(8'h00, byte_data);
                        state <= EXPECT_LENGTH;
                    end
                    EXPECT_LENGTH: begin
                        if (expected_length(opcode) == byte_data && byte_data != 8'hff) begin
                            payload_length <= byte_data;
                            running_crc <= crc8_next(running_crc, byte_data);
                            state <= EXPECT_SEQUENCE;
                        end else begin
                            state <= DISCARD_FRAME;
                            protocol_error <= 1'b1;
                            if (protocol_error_count != 16'hffff)
                                protocol_error_count <= protocol_error_count + 1'b1;
                        end
                    end
                    EXPECT_SEQUENCE: begin
                        sequence_id <= byte_data;
                        running_crc <= crc8_next(running_crc, byte_data);
                        state <= payload_length == 0 ? EXPECT_CRC : EXPECT_PAYLOAD;
                    end
                    EXPECT_PAYLOAD: begin
                        payload[payload_index] <= byte_data;
                        running_crc <= crc8_next(running_crc, byte_data);
                        if (8'(payload_index) + 8'd1 == payload_length) begin
                            state <= EXPECT_CRC;
                        end else begin
                            payload_index <= payload_index + 1'b1;
                        end
                    end
                    EXPECT_CRC: begin
                        if (byte_data == running_crc) begin
                            command <= decoded_command;
                            command_valid <= 1'b1;
                            state <= WAIT_FRAME_END;
                        end else begin
                            state <= DISCARD_FRAME;
                            protocol_error <= 1'b1;
                            if (protocol_error_count != 16'hffff)
                                protocol_error_count <= protocol_error_count + 1'b1;
                        end
                    end
                    default: state <= state;
                endcase
            end
        end
    end
endmodule
