#include "accelerator_link.h"

#include "accelerator_protocol.h"

#include "hardware/gpio.h"
#include "hardware/spi.h"
#include "pico/stdlib.h"

enum {
    ACCEL_SPI_MISO_PIN = 0,
    ACCEL_SPI_CS_PIN = 1,
    ACCEL_SPI_SCLK_PIN = 2,
    ACCEL_SPI_MOSI_PIN = 3,
    ACCEL_READY_PIN = 4,
    ACCEL_SPI_BAUD_HZ = 1 * 1000 * 1000,
    ACCEL_READY_TIMEOUT_MS = 500,
};

static bool wait_until_ready(accel_link_t *link) {
    const absolute_time_t deadline = make_timeout_time_ms(ACCEL_READY_TIMEOUT_MS);

    while (!gpio_get(ACCEL_READY_PIN)) {
        if (time_reached(deadline)) {
            link->ready_timeouts++;
            return false;
        }
        tight_loop_contents();
    }
    return true;
}

void accel_link_init(accel_link_t *link) {
    *link = (accel_link_t){0};

    gpio_init(ACCEL_SPI_CS_PIN);
    gpio_put(ACCEL_SPI_CS_PIN, 1);
    gpio_set_dir(ACCEL_SPI_CS_PIN, GPIO_OUT);

    gpio_init(ACCEL_READY_PIN);
    gpio_set_dir(ACCEL_READY_PIN, GPIO_IN);

    spi_init(spi0, ACCEL_SPI_BAUD_HZ);
    spi_set_format(spi0, 8, SPI_CPOL_0, SPI_CPHA_0, SPI_MSB_FIRST);
    gpio_set_function(ACCEL_SPI_MISO_PIN, GPIO_FUNC_SPI);
    gpio_set_function(ACCEL_SPI_SCLK_PIN, GPIO_FUNC_SPI);
    gpio_set_function(ACCEL_SPI_MOSI_PIN, GPIO_FUNC_SPI);
}

bool accel_link_emit(void *context, const uint8_t *packet, size_t packet_length) {
    accel_link_t *const link = context;
    uint8_t received[ACCEL_PACKET_MAX_SIZE] = {0};

    if (link == NULL || packet == NULL || packet_length == 0 ||
        packet_length > sizeof received || !wait_until_ready(link)) {
        return false;
    }

    gpio_put(ACCEL_SPI_CS_PIN, 0);
    busy_wait_us_32(1);
    const int transferred = spi_write_read_blocking(
        spi0, packet, received, packet_length
    );
    busy_wait_us_32(1);
    gpio_put(ACCEL_SPI_CS_PIN, 1);
    busy_wait_us_32(2);

    if (transferred != (int)packet_length) {
        link->status_errors++;
        return false;
    }

    link->last_status = received[0];
    if (!accel_status_is_compatible(link->last_status)) {
        link->status_errors++;
        return false;
    }

    const bool protocol_error =
        (link->last_status & ACCEL_STATUS_PROTOCOL_ERROR) != 0;
    if (protocol_error && !link->protocol_error_seen) {
        link->status_errors++;
    }
    link->protocol_error_seen = protocol_error;

    link->packets_sent++;
    return true;
}
