#include "accelerator_link.h"
#include "pong.h"

#include "pico/stdlib.h"

#include <stdio.h>

enum {
    FRAME_PERIOD_US = 16667,
};

static void set_activity_led(bool on) {
#ifdef PICO_DEFAULT_LED_PIN
    gpio_put(PICO_DEFAULT_LED_PIN, on);
#else
    (void)on;
#endif
}

int main(void) {
    accel_link_t link;
    pong_state_t game;
    uint8_t sequence = 0;
    uint32_t frames_rendered = 0;

    stdio_init_all();
#ifdef PICO_DEFAULT_LED_PIN
    gpio_init(PICO_DEFAULT_LED_PIN);
    gpio_set_dir(PICO_DEFAULT_LED_PIN, GPIO_OUT);
#endif
    accel_link_init(&link);
    pong_init(&game);

    printf("FPGA Pong: SPI0 1 MHz, GP0/1/2/3/4 MISO/CS/SCLK/MOSI/READY\n");
    absolute_time_t next_frame = get_absolute_time();

    while (true) {
        if (pong_render(&game, &sequence, accel_link_emit, &link)) {
            frames_rendered++;
            set_activity_led((frames_rendered & 0x20u) != 0);
            pong_step(&game, pong_autonomous_input(&game));

            if (frames_rendered % 60u == 0) {
                printf("frames=%lu packets=%lu status=0x%02x timeouts=%lu errors=%lu\n",
                       (unsigned long)frames_rendered,
                       (unsigned long)link.packets_sent,
                       link.last_status,
                       (unsigned long)link.ready_timeouts,
                       (unsigned long)link.status_errors);
            }

            next_frame = delayed_by_us(next_frame, FRAME_PERIOD_US);
            sleep_until(next_frame);
        } else {
            set_activity_led(false);
            printf("link retry: status=0x%02x timeouts=%lu errors=%lu\n",
                   link.last_status,
                   (unsigned long)link.ready_timeouts,
                   (unsigned long)link.status_errors);
            sleep_ms(250);
            next_frame = get_absolute_time();
        }
    }
}
