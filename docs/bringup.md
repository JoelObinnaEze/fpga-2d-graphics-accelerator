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
- Host link: SPI mode 0, MSB first, initial 8 MHz; final maximum is measured.
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
- Scanout: 512-pixel dual-clock FIFO, 256-pixel refill threshold, 32-pixel
  logical read bursts, VBlank-gated startup, and black fallback with a sticky
  underflow indicator. Each 32-bit SDRAM read now supplies both packed RGB565
  pixels to the FIFO, lower half first and upper half second.
- Clocking: 25.2 MHz pixel clock, 126 MHz TMDS serializer clock, and the
  hardware-characterized 162 MHz controller/phase-11 SDRAM clocks.
- Simulation: initialization, delayed commits, cross-domain prefetch, complete
  and repeated frames, backpressure, address carry boundaries, and forced
  underflow pass in the full self-checking suite.
- Place-and-route timing: all setup, hold, recovery, and removal TNS values are
  zero. Reported Fmax is 60.565 MHz for the 25.2 MHz pixel domain and
  162.202 MHz for the 161.996 MHz controller constraint.
- Utilization: 2,388 logic elements (12%), 956 registers (6%), four BSRAMs,
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
- Diagnostic LEDs, active low: LED0 reset released, LED1 controller initialized,
  LED2 framebuffer initialized and committed, LED3 scanout enabled, LED4 sticky
  underflow/protocol error, and LED5 at least one complete prefetch.

The packed-word revision is simulation-, timing-, and programming-verified but
failed the physical stability check. Stage 8 remains open while the read path
is changed to use the controller's multi-word burst interface.

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
```

The programming script uses SRAM operation 2 only. It does not write onboard
flash; removing power restores the prior FPGA configuration.

## Remaining Hardware Verification

- Confirm that the newly programmed packed-word scanout shows stable color bars
  and record the six LED states after at least one complete frame. LED4 must be
  off; LED0, LED1, LED2, LED3, and LED5 should be on.
- Board/schematic revision, remaining FPGA pin map, I/O standards, and voltages.

No hardware milestone is marked complete before these checks.
