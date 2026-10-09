#include "accelerator_protocol.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint8_t crc8(const uint8_t *data, size_t length) {
    uint8_t crc = 0;

    for (size_t i = 0; i < length; ++i) {
        crc ^= data[i];
        for (unsigned bit = 0; bit < 8; ++bit) {
            const uint8_t top_bit = (uint8_t)(crc & 0x80u);
            crc = (uint8_t)(crc << 1);
            if (top_bit != 0) {
                crc ^= 0x07u;
            }
        }
    }
    return crc;
}

static void expect_packet(
    const uint8_t *packet,
    size_t length,
    uint8_t opcode,
    uint8_t payload_length,
    uint8_t sequence,
    const uint8_t *payload
) {
    assert(length == (size_t)payload_length + 5u);
    assert(packet[0] == ACCEL_PACKET_MAGIC);
    assert(packet[1] == opcode);
    assert(packet[2] == payload_length);
    assert(packet[3] == sequence);
    assert(memcmp(&packet[4], payload, payload_length) == 0);
    assert(packet[length - 1] == crc8(&packet[1], length - 2));
}

int main(void) {
    uint8_t packet[ACCEL_PACKET_MAX_SIZE];
    const uint8_t clear_payload[] = {0x1f, 0xf8};
    const uint8_t rect_payload[] = {
        0x34, 0x12, 0x78, 0x56, 0xbc, 0x9a, 0xf0, 0xde, 0xe0, 0x07
    };
    const uint8_t sprite_payload[] = {0x02, 0x01, 0x04, 0x03, 0x06, 0x05};

    expect_packet(
        packet,
        accel_encode_clear(packet, sizeof packet, 0x10, 0xf81f),
        ACCEL_OP_CLEAR,
        sizeof clear_payload,
        0x10,
        clear_payload
    );
    expect_packet(
        packet,
        accel_encode_rect(packet, sizeof packet, 0x11, 0x1234, 0x5678,
                          0x9abc, 0xdef0, 0x07e0),
        ACCEL_OP_DRAW_RECT,
        sizeof rect_payload,
        0x11,
        rect_payload
    );
    expect_packet(
        packet,
        accel_encode_sprite(packet, sizeof packet, 0x12, 0x0102, 0x0304, 0x0506),
        ACCEL_OP_DRAW_SPRITE,
        sizeof sprite_payload,
        0x12,
        sprite_payload
    );
    expect_packet(
        packet,
        accel_encode_present(packet, sizeof packet, 0x13),
        ACCEL_OP_PRESENT,
        0,
        0x13,
        NULL
    );

    assert(accel_encode_clear(NULL, sizeof packet, 0, 0) == 0);
    assert(accel_encode_rect(packet, ACCEL_PACKET_MAX_SIZE - 1u, 0, 0, 0, 0, 0, 0) == 0);
    assert(accel_status_is_compatible(ACCEL_STATUS_VERSION_1 | ACCEL_STATUS_READY));
    assert(accel_status_is_compatible(ACCEL_STATUS_VERSION_1 |
                                      ACCEL_STATUS_READY |
                                      ACCEL_STATUS_PROTOCOL_ERROR));
    assert(!accel_status_is_compatible(ACCEL_STATUS_READY));
    assert(!accel_status_is_compatible(0x20u | ACCEL_STATUS_READY));

    puts("PASS: RP2040 command packet encoding and status compatibility");
    return 0;
}
