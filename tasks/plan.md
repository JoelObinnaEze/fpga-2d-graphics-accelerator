# Implementation Plan: FPGA 2D Graphics Accelerator

## Decisions

- Develop on Windows 11; run Verilator 5.050 through MSYS2 UCRT64.
- Target Tang Nano 20K GW2AR-LV18QN88C8/I7 and its onboard HDMI/SDR SDRAM.
- Use 640 x 480p60 RGB565 with a portable timing core and a later Gowin-specific
  DVI/TMDS output wrapper.
- Use ready/valid interfaces and keep rendering independent of physical SDRAM.
- Use Gowin's embedded SDRAM controller only at the fixed SiP boundary; keep
  project scheduling, buffering, scanout, and rendering behind its user port.
- Use Pico SDK 2.3.1, SPI mode 0 at an initial 8 MHz, and Pong for the demo.

## Build Order

1. Repository/tooling and portable video timing with generated patterns.
2. Small BSRAM-style framebuffer and scanout.
3. Clipped rectangle renderer against the logical memory interface.
4. Packet protocol, command FIFO, SPI receiver, and RP2040 sender.
5. Sprite ROM with a separate opacity mask.
6. SDR SDRAM controller, bursts, FIFOs, and memory arbitration.
7. Double-buffer ownership and VBlank presentation.
8. Board constraints, DVI/TMDS output, hardware bring-up, and Pong measurements.

Each item is a self-checking vertical slice. All ordered hardware arrived by
2026-10-06; each board slice still requires an explicit physical observation.

## Risks

| Risk | Mitigation |
| --- | --- |
| Embedded SDRAM integration differs from the reference | Preserve exact SiP port names; pin the official controller; verify full-memory readback |
| Scanout misses deadlines | Parameterized FIFO threshold, bounded write bursts, underflow counter |
| HDMI serialization is vendor-specific | Keep `video_timing` portable and isolate primitives in `video_out` |
| SPI crosses clock domains incorrectly | Freeze protocol first; use coherent byte/packet crossing and CDC tests |
| Standalone repository has no remote | Keep atomic local commits; add an explicit remote before sharing |

## Checkpoints

- Portable video: full-frame timing and pattern tests pass under Verilator.
- Graphics core: reference framebuffer matches rectangles and sprites.
- Command path: malformed/backpressured SPI traffic never loses a command.
- Memory: timing model passes initialization, refresh, bursts, and arbitration.
- Hardware: programming, display, memory readback, and Pong measurements recorded.

## Final Demo Slices

1. Integrate front/back SDRAM ownership into the verified scanout core. A
   presentation must wait for committed renderer writes and a quiescent old
   prefetch, flush stale FIFO words, restart from the new front buffer, and
   resume during vertical blanking.
2. Add a controller-domain graphics command engine that executes `CLEAR` and
   `DRAW_RECT`, preserves command ordering, converts coordinates to draw-buffer
   pixel addresses, and hands `PRESENT` to the frame presenter. Keep the tested
   sprite command interface available as the next renderer dispatch path.
3. Connect the tested oversampled SPI receiver, decoder, and command FIFO to the
   graphics engine. Expose packet capacity on a dedicated READY pin and report
   busy, protocol-error, and presentation-pending status on MISO.
4. Build a Pico SDK 2.3.1 firmware target for autonomous Pong. Use RP2040 SPI0
   at 8 MHz with manual per-packet chip select and wait for FPGA READY before
   every packet.
5. Synthesize, close timing, volatile-program both boards, verify moving Pong,
   and record utilization, bandwidth, throughput, and all error indications.

Dependency order is 1 -> 2 -> 3 -> 4 -> 5. Each slice must pass a focused
self-checking test and be committed before the next slice starts.
