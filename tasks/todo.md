# Build Tasks

## Task 1: Portable video timing and pattern

- [x] Add reproducible Verilator test command.
- [x] Check 800 x 525 totals, active area, negative sync pulses, and frame events.
- [x] Check RGB565 color bars and black blanking output.
- [x] Record simulator version and passing command.

Verify: `pwsh -File scripts/test.ps1`

## Task 2: Small framebuffer scanout

- [x] Add parameterized synchronous framebuffer and read-latency handling.
- [x] Compare a known pixel map through scanout.

Verify: focused framebuffer test plus the full test script.

## Task 3: Rectangle rendering

- [x] Emit ready/valid pixel writes for clipped half-open rectangles.
- [x] Compare normal, zero-size, edge-clipped, and off-screen cases to a reference.

Verify: focused rectangle test plus the full test script.

## Task 4: Host command link

- [x] Freeze packet/status protocol.
- [x] Implement command FIFO, decoder, SPI receive path, and RP2040 encoder.
- [x] Prove invalid, partial, full-queue, and back-to-back behavior.

Verify: protocol RTL tests and firmware host tests.

## Task 5: Sprite rendering

- [x] Add RGB565 sprite words with a separate opacity mask.
- [x] Prove source indexing, clipping, transparency, invalid IDs, and stalls.

Verify: focused sprite test plus the full test script.

## Task 6: SDRAM and arbitration

- [x] Verify the embedded 64-Mbit, 32-bit GW2AR SDRAM organization and official
  controller interface.
- [x] Implement portable scanout/write/refresh arbitration with bounded write bursts.
- [x] Integrate the official embedded controller and a full-memory two-pattern BIST.
- [x] Characterize the SDRAM clock phase and confirm the full physical BIST.
- [x] Implement and verify a dual-clock FIFO for video/memory CDC.
- [x] Implement bounded framebuffer read prefetch and verify it through the
  arbiter and SDRAM pixel adapter.
- [ ] Implement the renderer write FIFO and backend drain path.
- [ ] Prove scanout priority and renderer progress through the SDRAM adapter.

Verify: `pwsh -File scripts/test.ps1`, then the SDRAM build/program scripts.

## Task 7: Frame presentation

- [x] Track front/back ownership and committed writes.
- [x] Swap only at VBlank and invalidate stale prefetch data.

Verify: delayed-write, missed-VBlank, consecutive-present, and reset tests.

## Task 8: Board integration and Pong

- [x] Build a portable RP2040 Pong model and graphics-command stream.
- [x] Verify the 27 MHz clock pin, LED0 pin, JTAG enumeration, volatile SRAM
  programming, and physical LED blink.
- [x] Verify 640 x 480 DVI/TMDS output with a physical monitor.
- [ ] Verify full SDRAM scanout.
- [ ] Run Pong and record timing, utilization, bandwidth, and error counters.

Verify: reproducible hardware procedure and saved reports.
