#ifndef ACCELERATOR_LINK_H
#define ACCELERATOR_LINK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t last_status;
    uint32_t packets_sent;
    uint32_t ready_timeouts;
    uint32_t status_errors;
} accel_link_t;

void accel_link_init(accel_link_t *link);
bool accel_link_emit(void *context, const uint8_t *packet, size_t packet_length);

#endif
