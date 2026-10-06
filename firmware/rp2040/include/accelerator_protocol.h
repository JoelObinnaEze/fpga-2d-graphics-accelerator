#ifndef ACCELERATOR_PROTOCOL_H
#define ACCELERATOR_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#define ACCEL_PACKET_MAGIC 0xa5u
#define ACCEL_PACKET_MAX_SIZE 15u

enum accel_opcode {
    ACCEL_OP_CLEAR = 0x01,
    ACCEL_OP_DRAW_RECT = 0x02,
    ACCEL_OP_DRAW_SPRITE = 0x03,
    ACCEL_OP_PRESENT = 0x04,
};

size_t accel_encode_clear(
    uint8_t *packet, size_t capacity, uint8_t sequence, uint16_t color
);

size_t accel_encode_rect(
    uint8_t *packet,
    size_t capacity,
    uint8_t sequence,
    uint16_t x,
    uint16_t y,
    uint16_t width,
    uint16_t height,
    uint16_t color
);

size_t accel_encode_sprite(
    uint8_t *packet,
    size_t capacity,
    uint8_t sequence,
    uint16_t sprite_id,
    uint16_t x,
    uint16_t y
);

size_t accel_encode_present(uint8_t *packet, size_t capacity, uint8_t sequence);

#endif
