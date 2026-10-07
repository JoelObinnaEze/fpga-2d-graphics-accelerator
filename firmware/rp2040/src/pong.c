#include "pong.h"

enum {
    PADDLE_SPEED = 6,
    BALL_SPEED_X = 4,
    BALL_SPEED_Y = 3,
    AI_DEADBAND = 4,
};

static int16_t clamp_paddle(int16_t y) {
    if (y < 0) {
        return 0;
    }
    if (y > PONG_SCREEN_HEIGHT - PONG_PADDLE_HEIGHT) {
        return PONG_SCREEN_HEIGHT - PONG_PADDLE_HEIGHT;
    }
    return y;
}

static bool overlaps_paddle(int16_t ball_y, int16_t paddle_y) {
    return ball_y + PONG_BALL_SIZE > paddle_y &&
           ball_y < paddle_y + PONG_PADDLE_HEIGHT;
}

static void reset_ball(pong_state_t *game, int16_t direction) {
    game->ball_x = (PONG_SCREEN_WIDTH - PONG_BALL_SIZE) / 2;
    game->ball_y = (PONG_SCREEN_HEIGHT - PONG_BALL_SIZE) / 2;
    game->ball_dx = (int16_t)(direction * BALL_SPEED_X);
    game->ball_dy = BALL_SPEED_Y;
}

void pong_init(pong_state_t *game) {
    game->left_paddle_y = (PONG_SCREEN_HEIGHT - PONG_PADDLE_HEIGHT) / 2;
    game->right_paddle_y = game->left_paddle_y;
    game->left_score = 0;
    game->right_score = 0;
    reset_ball(game, 1);
}

uint8_t pong_autonomous_input(const pong_state_t *game) {
    const int ball_center = game->ball_y + PONG_BALL_SIZE / 2;
    const int left_center = game->left_paddle_y + PONG_PADDLE_HEIGHT / 2;
    const int right_center = game->right_paddle_y + PONG_PADDLE_HEIGHT / 2;
    uint8_t input = 0;

    if (ball_center < left_center - AI_DEADBAND)
        input |= PONG_INPUT_LEFT_UP;
    else if (ball_center > left_center + AI_DEADBAND)
        input |= PONG_INPUT_LEFT_DOWN;

    if (ball_center < right_center - AI_DEADBAND)
        input |= PONG_INPUT_RIGHT_UP;
    else if (ball_center > right_center + AI_DEADBAND)
        input |= PONG_INPUT_RIGHT_DOWN;

    return input;
}

void pong_step(pong_state_t *game, uint8_t input) {
    if ((input & PONG_INPUT_LEFT_UP) != 0)
        game->left_paddle_y -= PADDLE_SPEED;
    if ((input & PONG_INPUT_LEFT_DOWN) != 0)
        game->left_paddle_y += PADDLE_SPEED;
    if ((input & PONG_INPUT_RIGHT_UP) != 0)
        game->right_paddle_y -= PADDLE_SPEED;
    if ((input & PONG_INPUT_RIGHT_DOWN) != 0)
        game->right_paddle_y += PADDLE_SPEED;
    game->left_paddle_y = clamp_paddle(game->left_paddle_y);
    game->right_paddle_y = clamp_paddle(game->right_paddle_y);

    game->ball_x += game->ball_dx;
    game->ball_y += game->ball_dy;

    if (game->ball_y < 0) {
        game->ball_y = 0;
        game->ball_dy = BALL_SPEED_Y;
    } else if (game->ball_y > PONG_SCREEN_HEIGHT - PONG_BALL_SIZE) {
        game->ball_y = PONG_SCREEN_HEIGHT - PONG_BALL_SIZE;
        game->ball_dy = -BALL_SPEED_Y;
    }

    if (game->ball_dx < 0 &&
        game->ball_x <= PONG_LEFT_PADDLE_X + PONG_PADDLE_WIDTH &&
        game->ball_x + PONG_BALL_SIZE >= PONG_LEFT_PADDLE_X &&
        overlaps_paddle(game->ball_y, game->left_paddle_y)) {
        game->ball_x = PONG_LEFT_PADDLE_X + PONG_PADDLE_WIDTH;
        game->ball_dx = BALL_SPEED_X;
    } else if (game->ball_dx > 0 &&
               game->ball_x + PONG_BALL_SIZE >= PONG_RIGHT_PADDLE_X &&
               game->ball_x <= PONG_RIGHT_PADDLE_X + PONG_PADDLE_WIDTH &&
               overlaps_paddle(game->ball_y, game->right_paddle_y)) {
        game->ball_x = PONG_RIGHT_PADDLE_X - PONG_BALL_SIZE;
        game->ball_dx = -BALL_SPEED_X;
    }

    if (game->ball_x + PONG_BALL_SIZE < 0) {
        game->right_score++;
        reset_ball(game, 1);
    } else if (game->ball_x > PONG_SCREEN_WIDTH) {
        game->left_score++;
        reset_ball(game, -1);
    }
}

static bool emit(
    uint8_t *packet,
    size_t length,
    uint8_t *sequence,
    pong_emit_packet_fn emit_packet,
    void *context
) {
    if (length == 0 || !emit_packet(context, packet, length)) {
        return false;
    }
    (*sequence)++;
    return true;
}

bool pong_render(
    const pong_state_t *game,
    uint8_t *sequence,
    pong_emit_packet_fn emit_packet,
    void *context
) {
    uint8_t packet[ACCEL_PACKET_MAX_SIZE];

    if (game == NULL || sequence == NULL || emit_packet == NULL) {
        return false;
    }
    if (!emit(packet, accel_encode_clear(packet, sizeof packet, *sequence, PONG_COLOR_BLACK),
              sequence, emit_packet, context))
        return false;
    if (!emit(packet, accel_encode_rect(packet, sizeof packet, *sequence,
                                        PONG_LEFT_PADDLE_X, (uint16_t)game->left_paddle_y,
                                        PONG_PADDLE_WIDTH, PONG_PADDLE_HEIGHT, PONG_COLOR_WHITE),
              sequence, emit_packet, context))
        return false;
    if (!emit(packet, accel_encode_rect(packet, sizeof packet, *sequence,
                                        PONG_RIGHT_PADDLE_X, (uint16_t)game->right_paddle_y,
                                        PONG_PADDLE_WIDTH, PONG_PADDLE_HEIGHT, PONG_COLOR_WHITE),
              sequence, emit_packet, context))
        return false;
    if (!emit(packet, accel_encode_rect(packet, sizeof packet, *sequence,
                                        (uint16_t)game->ball_x, (uint16_t)game->ball_y,
                                        PONG_BALL_SIZE, PONG_BALL_SIZE, PONG_COLOR_WHITE),
              sequence, emit_packet, context))
        return false;
    return emit(packet, accel_encode_present(packet, sizeof packet, *sequence),
                sequence, emit_packet, context);
}
