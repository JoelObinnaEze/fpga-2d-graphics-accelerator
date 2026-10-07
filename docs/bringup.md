# Bring-up Record

## Confirmed Hardware

- All ordered parts arrived by 2026-10-06.
- The FPGA board is a Tang Nano 20K. A live JTAG scan identifies its device as
  `GW2AR-18C` with ID `0x0000081B`.
- The onboard BL616 debugger firmware reports version `2025030317`.
- Windows enumerates both FTDI channels as `USB Serial Converter A/B`; the
  associated serial ports are COM4 and COM5.
- The RP2040 board, video connector, cables, and jumper wiring are available.
- The exact SDRAM component marking and RP2040 board model still need to be
  recorded before those interfaces are enabled.

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

## Reproduce

```powershell
pwsh -File scripts/test.ps1
pwsh -File scripts/build_led.ps1
pwsh -File scripts/program_led_sram.ps1
pwsh -File scripts/build_dvi.ps1
pwsh -File scripts/program_dvi_sram.ps1
```

The programming script uses SRAM operation 2 only. It does not write onboard
flash; removing power restores the prior FPGA configuration.

## Remaining Hardware Verification

- Board revision and SDRAM component marking.
- Schematic revision, remaining FPGA pin map, I/O standards, and voltages.
- Legal PLL outputs for SDRAM clocks.

No hardware milestone is marked complete before these checks.
