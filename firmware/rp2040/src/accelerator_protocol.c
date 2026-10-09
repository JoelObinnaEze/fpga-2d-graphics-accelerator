#include "accelerator_protocol.h"

#include <string.h>

bool accel_status_is_compatible(uint8_t status) {
    return (status & ACCEL_STATUS_VERSION_MASK) == ACCEL_STATUS_VERSION_1;
}

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

static void put_u16(uint8_t *destination, uint16_t value) {
    destination[0] = (uint8_t)value;
    destination[1] = (uint8_t)(value >> 8);
}

static size_t encode(
    uint8_t *packet,
    size_t capacity,
    uint8_t opcode,
    uint8_t sequence,
    const uint8_t *payload,
    uint8_t payload_length
) {
    const size_t packet_length = (size_t)payload_length + 5u;

    if (packet == NULL || capacity < packet_length) {
        return 0;
    }

    packet[0] = ACCEL_PACKET_MAGIC;
    packet[1] = opcode;
    packet[2] = payload_length;
    packet[3] = sequence;
    if (payload_length != 0) {
        memcpy(&packet[4], payload, payload_length);
    }
    packet[packet_length - 1] = crc8(&packet[1], packet_length - 2u);
    return packet_length;
}

size_t accel_encode_clear(
    uint8_t *packet, size_t capacity, uint8_t sequence, uint16_t color
) {
    uint8_t payload[2];

    put_u16(payload, color);
    return encode(packet, capacity, ACCEL_OP_CLEAR, sequence, payload, sizeof payload);
}

size_t accel_encode_rect(
    uint8_t *packet,
    size_t capacity,
    uint8_t sequence,
    uint16_t x,
    uint16_t y,
    uint16_t width,
    uint16_t height,
    uint16_t color
) {
    uint8_t payload[10];

    put_u16(&payload[0], x);
    put_u16(&payload[2], y);
    put_u16(&payload[4], width);
    put_u16(&payload[6], height);
    put_u16(&payload[8], color);
    return encode(packet, capacity, ACCEL_OP_DRAW_RECT, sequence, payload, sizeof payload);
}

size_t accel_encode_sprite(
    uint8_t *packet,
    size_t capacity,
    uint8_t sequence,
    uint16_t sprite_id,
    uint16_t x,
    uint16_t y
) {
    uint8_t payload[6];

    put_u16(&payload[0], sprite_id);
    put_u16(&payload[2], x);
    put_u16(&payload[4], y);
    return encode(packet, capacity, ACCEL_OP_DRAW_SPRITE, sequence, payload, sizeof payload);
}

size_t accel_encode_present(uint8_t *packet, size_t capacity, uint8_t sequence) {
    return encode(packet, capacity, ACCEL_OP_PRESENT, sequence, NULL, 0);
}
