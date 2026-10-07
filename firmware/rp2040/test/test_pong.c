#include "pong.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint8_t packets[8][ACCEL_PACKET_MAX_SIZE];
    size_t lengths[8];
    size_t count;
    size_t fail_at;
} packet_log_t;

static bool collect_packet(void *context, const uint8_t *packet, size_t length) {
    packet_log_t *log = context;

    if (log->count == log->fail_at) {
        return false;
    }
    assert(log->count < 8);
    memcpy(log->packets[log->count], packet, length);
    log->lengths[log->count] = length;
    log->count++;
    return true;
}

static uint16_t packet_u16(const uint8_t *packet, size_t offset) {
    return (uint16_t)(packet[offset] | (uint16_t)packet[offset + 1] << 8);
}

int main(void) {
    pong_state_t game;
    packet_log_t log = {.fail_at = (size_t)-1};
    uint8_t sequence = 0x20;

    pong_init(&game);
    assert(game.ball_x == (PONG_SCREEN_WIDTH - PONG_BALL_SIZE) / 2);
    assert(game.ball_y == (PONG_SCREEN_HEIGHT - PONG_BALL_SIZE) / 2);

    game.left_paddle_y = 200;
    game.right_paddle_y = 100;
    game.ball_y = 0;
    assert(pong_autonomous_input(&game) ==
           (PONG_INPUT_LEFT_UP | PONG_INPUT_RIGHT_UP));
    game.ball_y = 400;
    assert(pong_autonomous_input(&game) ==
           (PONG_INPUT_LEFT_DOWN | PONG_INPUT_RIGHT_DOWN));
    game.left_paddle_y = 200;
    game.right_paddle_y = 200;
    game.ball_y = 228;
    assert(pong_autonomous_input(&game) == 0);

    pong_init(&game);

    pong_step(&game, 0);
    assert(game.ball_x == (PONG_SCREEN_WIDTH - PONG_BALL_SIZE) / 2 + 4);
    assert(game.ball_y == (PONG_SCREEN_HEIGHT - PONG_BALL_SIZE) / 2 + 3);

    game.left_paddle_y = 0;
    pong_step(&game, PONG_INPUT_LEFT_UP);
    assert(game.left_paddle_y == 0);
    game.right_paddle_y = PONG_SCREEN_HEIGHT - PONG_PADDLE_HEIGHT;
    pong_step(&game, PONG_INPUT_RIGHT_DOWN);
    assert(game.right_paddle_y == PONG_SCREEN_HEIGHT - PONG_PADDLE_HEIGHT);

    game.ball_y = 0;
    game.ball_dy = -3;
    pong_step(&game, 0);
    assert(game.ball_y == 0 && game.ball_dy == 3);

    game.left_paddle_y = 100;
    game.ball_x = PONG_LEFT_PADDLE_X + PONG_PADDLE_WIDTH + 1;
    game.ball_y = 110;
    game.ball_dx = -4;
    pong_step(&game, 0);
    assert(game.ball_x == PONG_LEFT_PADDLE_X + PONG_PADDLE_WIDTH);
    assert(game.ball_dx == 4);

    game.ball_x = -PONG_BALL_SIZE;
    game.ball_dx = -4;
    pong_step(&game, 0);
    assert(game.left_score == 0 && game.right_score == 1);
    assert(game.ball_x == (PONG_SCREEN_WIDTH - PONG_BALL_SIZE) / 2);

    assert(pong_render(&game, &sequence, collect_packet, &log));
    assert(log.count == 5);
    assert(sequence == 0x25);
    assert(log.packets[0][1] == ACCEL_OP_CLEAR);
    assert(packet_u16(log.packets[0], 4) == PONG_COLOR_BLACK);
    assert(log.packets[1][1] == ACCEL_OP_DRAW_RECT);
    assert(packet_u16(log.packets[1], 4) == PONG_LEFT_PADDLE_X);
    assert(packet_u16(log.packets[1], 8) == PONG_PADDLE_WIDTH);
    assert(packet_u16(log.packets[1], 12) == PONG_COLOR_WHITE);
    assert(log.packets[2][1] == ACCEL_OP_DRAW_RECT);
    assert(packet_u16(log.packets[2], 4) == PONG_RIGHT_PADDLE_X);
    assert(log.packets[3][1] == ACCEL_OP_DRAW_RECT);
    assert(packet_u16(log.packets[3], 4) == (uint16_t)game.ball_x);
    assert(packet_u16(log.packets[3], 6) == (uint16_t)game.ball_y);
    assert(log.packets[4][1] == ACCEL_OP_PRESENT);
    for (size_t i = 0; i < log.count; ++i) {
        assert(log.packets[i][0] == ACCEL_PACKET_MAGIC);
        assert(log.packets[i][3] == (uint8_t)(0x20 + i));
    }

    memset(&log, 0, sizeof log);
    log.fail_at = 2;
    assert(!pong_render(&game, &sequence, collect_packet, &log));
    assert(log.count == 2);

    puts("PASS: Pong motion, bounds, scoring, and command emission");
    return 0;
}
