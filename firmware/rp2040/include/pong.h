#ifndef PONG_H
#define PONG_H

#include "accelerator_protocol.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PONG_SCREEN_WIDTH 640
#define PONG_SCREEN_HEIGHT 480
#define PONG_PADDLE_WIDTH 8
#define PONG_PADDLE_HEIGHT 64
#define PONG_BALL_SIZE 8
#define PONG_LEFT_PADDLE_X 16
#define PONG_RIGHT_PADDLE_X (PONG_SCREEN_WIDTH - 24)
#define PONG_COLOR_BLACK 0x0000u
#define PONG_COLOR_WHITE 0xffffu

enum pong_input {
    PONG_INPUT_LEFT_UP = 1u << 0,
    PONG_INPUT_LEFT_DOWN = 1u << 1,
    PONG_INPUT_RIGHT_UP = 1u << 2,
    PONG_INPUT_RIGHT_DOWN = 1u << 3,
};

typedef struct {
    int16_t left_paddle_y;
    int16_t right_paddle_y;
    int16_t ball_x;
    int16_t ball_y;
    int16_t ball_dx;
    int16_t ball_dy;
    uint16_t left_score;
    uint16_t right_score;
} pong_state_t;

typedef bool (*pong_emit_packet_fn)(
    void *context, const uint8_t *packet, size_t packet_length
);

void pong_init(pong_state_t *game);
uint8_t pong_autonomous_input(const pong_state_t *game);
void pong_step(pong_state_t *game, uint8_t input);
bool pong_render(
    const pong_state_t *game,
    uint8_t *sequence,
    pong_emit_packet_fn emit_packet,
    void *context
);

#endif
