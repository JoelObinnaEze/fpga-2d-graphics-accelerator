# Bring-up Record

## Confirmed Hardware

- All ordered parts arrived by 2026-10-06.
- The FPGA board is a Tang Nano 20K. A live JTAG scan identifies its device as
  `GW2AR-18C` with ID `0x0000081B`.
- The onboard BL616 debugger firmware reports version `2025030317`.
- Windows enumerates both FTDI channels as `USB Serial Converter A/B`; the
  associated serial ports are COM4 and COM5.
- The RP2040 board, video connector, cables, and jumper wiring are available.
- The memory is the GW2AR-18's embedded 64-Mbit SDR SDRAM, so there is no
  separate SDRAM package marking to record. The exact RP2040 board model still
  needs to be recorded before its hardware interface is enabled.

## Selected Baseline

- Host OS: Windows 11 Home 64-bit.
- FPGA: Tang Nano 20K, GW2AR-LV18QN88C8/I7.
- Onboard resources: 27 MHz crystal, HDMI connector, and 64-Mbit 32-bit SDR SDRAM.
- Video: 640 x 480p60, RGB565 framebuffer, negative horizontal/vertical sync.
- Simulation/lint: Verilator 5.050 through MSYS2 UCRT64.
- FPGA tools: Gowin EDA Education 1.9.11.03.
- Firmware: Raspberry Pi Pico SDK 2.3.1, generic RP2040 target.
- Host link: SPI mode 0, MSB first, 1 MHz jumper-wire bring-up rate; final
  maximum is measured.
- Demo: Pong.

## Sources

- Tang Nano 20K hardware: https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html
- Tang Nano 20K LED example and pin assignments: https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/example/led.html
- Tang Nano 20K HDMI example and connector constraints: https://github.com/sipeed/TangNano-20K-example/tree/main/hdmi
- Gowin EDA 1.9.11.03: https://www.gowinsemi.com/en/document/main/database/1865/
- Verilator installation: https://veripool.org/guide/latest/install.html
- Pico SDK 2.3.1: https://www.raspberrypi.com/documentation/pico-sdk/
- Gowin SDRAM controller: https://www.gowinsemi.com/en/support/ip_detail/5/
- Gowin SDRAM controller guide: https://www.gowinsemi.com/upload/database_doc/2057/document/6820d99fcc4d1.pdf

## Verified FPGA LED Slice

- Input clock: onboard 27 MHz oscillator on package pin 4, constrained to
  37.037 ns.
- Output: active-low onboard LED0 on package pin 15.
- Simulation: the LED output starts off and toggles after each configured
  half-period.
- Synthesis, place-and-route, and bitstream generation complete with Gowin EDA
  Education 1.9.11.03.
- Timing: zero setup/hold violations at 27 MHz; reported Fmax is 314.525 MHz.
- Utilization: 34 LUTs and 25 flip-flops, both below 1%.
- Clock resources: one of eight primary global clocks used.
- Programmer: volatile SRAM operation completed successfully on 2026-10-06.
  User code was `0x0000EDC4`; status code was `0x00006020`.
- Joel visually confirmed the one-hertz LED0 blink on 2026-10-06.

Gowin emits `PR1014` because the Tang Nano 20K's fixed 27 MHz oscillator pin
has a generic-route segment before the global buffer. The official board LED
example uses this same pin. The implemented clock is promoted to a primary
global clock, closes timing with substantial margin, and the warning is
accepted for this bring-up target only.

## Verified DVI Color-Bar Slice

- Video mode: 640 x 480, 800 x 525 total, 25.2 MHz pixel clock, negative
  horizontal and vertical synchronization, approximately 60 Hz refresh.
- Clocking: the 27 MHz oscillator feeds one rPLL at 126 MHz; a divide-by-five
  clock produces 25.2 MHz for pixel logic and `OSER10` serializers transmit
  two TMDS bits per 126 MHz cycle.
- Output: four differential pairs on package pins 33 through 40, matching the
  current official Sipeed HDMI example.
- Encoding: self-checking simulation covers all four DVI control tokens, known
  pixel symbols, and running disparity behavior.
- Synthesis, place-and-route, and bitstream generation complete with Gowin EDA
  Education 1.9.11.03.
- Timing: zero setup/hold violations at 25.2 MHz; reported pixel-domain Fmax is
  189.539 MHz.
- Utilization: 106 logic elements, 51 flip-flops, one rPLL, one CLKDIV, four
  OSER10 serializers, and four differential output buffers.
- Volatile SRAM programming completed successfully on 2026-10-06. User code
  was `0x000082AD`; status code was `0x00006020`.
- Joel visually confirmed the eight 640 x 480 color bars on a connected monitor
  on 2026-10-06.

The DVI build retains the same documented `PR1014` oscillator-pin warning as
the LED build. The generated clocks are reported at exactly 126.000 MHz and
25.200 MHz, and the design closes timing with substantial margin.

## SDRAM Readback Slice

- Organization: 2,097,152 32-bit words (8 MiB), exposed through the GW2AR-18
  embedded SDRAM controller's 21-bit word address.
- Boundary: unmodified encrypted controller from Gowin's official GW2AR-18
  reference design; project-owned RTL implements the self-test and status.
- Clocking: the 27 MHz oscillator feeds one rPLL at 162 MHz. A hardware sweep
  tested all 16 equal-frequency SDRAM clock phases with the full BIST. Phase 10
  was the first passing position; the characterized window midpoint, phase 11
  (247.5 degrees), is fixed in the production clock wrapper.
- Test: write and read every word with a unique address-derived pattern, then
  repeat with every bit inverted. Any mismatch or controller timeout is sticky.
- Simulation: self-checking tests cover both complete pattern passes, injected
  read corruption, and initialization timeout.
- Timing: zero setup/hold violations at 162 MHz; reported Fmax is 162.442 MHz.
- Utilization: 703 logic elements, 630 registers, one BSRAM, and one rPLL.
- Volatile SRAM programming completed successfully on 2026-10-06. User code
  was `0x0000C222`; status code was `0x00006020`.
- Physical result: hardware passed both patterns across all 2,097,152 words at
  the fixed phase-11 setting. Final LEDs showed reset, initialization,
  acknowledgement, read-valid, and pass; the mismatch LED remained off.

The decision to use the vendor controller only at the SiP boundary is recorded
in `docs/decisions/0001-use-gowin-embedded-sdram-controller.md`.

## SDRAM Scanout Bring-up

- Resolution and format: 640 x 480 RGB565, initialized to eight vertical color
  bars through the same queued write and real SDRAM commit path used by later
  renderers.
- Scanout: 256-word (512-pixel) dual-clock FIFO, 256-pixel refill threshold,
  16-word (32-pixel) controller bursts, VBlank-gated startup, and black fallback
  with a sticky underflow indicator. The controller streams each packed 32-bit
  word into the FIFO; the pixel domain emits its lower RGB565 half first and its
  upper half second.
- Clocking: 25.2 MHz pixel clock, 126 MHz TMDS serializer clock, and the
  hardware-characterized 162 MHz controller/phase-11 SDRAM clocks.
- Simulation: initialization, delayed commits, cross-domain prefetch, complete
  and repeated frames, backpressure, address carry boundaries, and forced
  underflow pass in the full self-checking suite.
- Place-and-route timing: all setup and hold TNS values are zero. Reported Fmax
  is 65.733 MHz for the 25.2 MHz pixel domain and 162.722 MHz for the 161.996 MHz
  controller constraint.
- Utilization: 2,434 logic elements (12%), 938 registers (6%), four BSRAMs,
  two rPLLs, one CLKDIV, and four OSER10 serializers.
- The first per-pixel-read candidate was programmed with user code `0x0000D8A8`.
  Physical testing showed moving RGB and all six LEDs on; LED4 therefore
  confirmed a sticky scanout underflow/protocol error. This matched the known
  bandwidth risk: the adapter reread every 32-bit SDRAM word once per 16-bit
  pixel and discarded half of each response.
- The packed-word revision is covered by regressions proving that six ordered
  pixels require exactly three SDRAM reads, including FIFO backpressure and an
  address carry boundary. It was programmed into volatile SRAM on 2026-10-06
  with user code `0x00003E55` and status code `0x00006020`.
- Physical testing of that revision still showed moving RGB and all six LEDs
  on. LED4 therefore remained asserted: halving the controller command count
  changed the corruption pattern but did not provide sustained scanout.
- The burst-read revision uses the controller guide's `data_len + 1` transfer
  rule to return 16 consecutive packed words per command. The full RTL and
  RP2040 regression passes, place-and-route meets timing with zero TNS, and the
  candidate was programmed into volatile SRAM on 2026-10-06 with user code
  `0x0000BADE` and status code `0x00006020`.
- Joel physically confirmed stable eight-bar output and the expected diagnostic
  state: LED0, LED1, LED2, LED3, and LED5 on, with LED4 off. This verifies
  sustained scanout without an underflow or protocol error.
- Diagnostic LEDs, active low: LED0 reset released, LED1 controller initialized,
  LED2 framebuffer initialized and committed, LED3 scanout enabled, LED4 sticky
  underflow/protocol error, and LED5 at least one complete prefetch.

The burst-read revision is simulation-, timing-, programming-, and
hardware-verified. The full SDRAM scanout milestone is complete; Stage 8 now
proceeds to Pong integration.

## Host Command Link and Pong Firmware

- SPI mode 0, MSB first, 1 MHz, one command packet per active-low chip-select
  interval. Firmware waits for the separate active-high READY signal before
  every packet, validates the protocol version returned on MISO, and reports a
  sticky FPGA protocol-error indication without deadlocking future packets.
- The final pin harness is:

| RP2040 | Direction at RP2040 | Signal | Tang Nano 20K | FPGA pin |
| --- | --- | --- | --- | --- |
| GP0 | input | MISO | J6-8 | 27 |
| GP1 | output | CS_N | J6-9 | 28 |
| GP2 | output | SCLK | J6-10 | 25 |
| GP3 | output | MOSI | J6-11 | 26 |
| GP4 | input | READY | J6-12 | 29 |
| GND | - | common ground | J6-20 | GND |

- Both boards may remain powered from their own USB connectors after the
  harness is installed. Connect only the five 3.3 V logic signals and common
  ground; do not join 5 V, VSYS, or 3V3 rails between the powered boards.
- Full end-to-end simulation covers READY backpressure, status, valid and bad
  CRCs, FIFO ordering, CLEAR/DRAW_RECT execution, and delayed PRESENT.
- Final FPGA place-and-route has zero setup and hold TNS. Controller-domain
  Fmax is 163.612 MHz against a 161.996 MHz constraint; pixel-domain Fmax is
  72.109 MHz against 25.200 MHz. Utilization is 3,138 logic elements (16%),
  1,465 registers (10%), and four BSRAMs (9%).
- The command-link bitstream was programmed into volatile SRAM on 2026-10-06
  with user code `0x00005590` and status code `0x00006020`.
- The autonomous two-AI Pong firmware builds with Pico SDK 2.3.1 for the
  generic `pico` RP2040 board. It renders CLEAR, two paddles, a ball, and
  PRESENT at approximately 60 Hz, reports link counters over USB serial, and
  produces `build/pico/fpga_pong/fpga_pong.uf2`.
- On 2026-10-08 the corrected UF2 was loaded over USB and the FPGA was
  reprogrammed in volatile SRAM. USB serial showed the autonomous loop advance
  from frame 300 / packet 1500 to frame 360 / packet 1800, with current status
  `0x13` and zero READY timeouts. This verifies sustained RP2040-to-FPGA command
  traffic after recovery from an earlier sticky protocol fault.

Joel visually confirmed moving Pong on the monitor after the corrected firmware
load on 2026-10-08. The final diagnostic state also matched expectations:
LED0, LED1, LED2, LED3, and LED5 on, with LED4 off. This completes physical
Pong validation without a live underflow or protocol-error indication.

## Reproduce

```powershell
pwsh -File scripts/test.ps1
pwsh -File scripts/build_led.ps1
pwsh -File scripts/program_led_sram.ps1
pwsh -File scripts/build_dvi.ps1
pwsh -File scripts/program_dvi_sram.ps1
pwsh -File scripts/build_sdram_bist.ps1
pwsh -File scripts/program_sdram_bist_sram.ps1
pwsh -File scripts/build_sdram_scanout.ps1
pwsh -File scripts/program_sdram_scanout_sram.ps1
pwsh -File scripts/build_pico_pong.ps1
pwsh -File scripts/flash_pico_pong.ps1
```

The programming script uses SRAM operation 2 only. It does not write onboard
flash; removing power restores the prior FPGA configuration.

## Remaining Hardware Verification

- Board/schematic revision, remaining FPGA pin map, I/O standards, and voltages.

Record the remaining board details before final project handoff.
