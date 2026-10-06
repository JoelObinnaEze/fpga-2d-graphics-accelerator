# Bring-up Record

## Confirmed by Joel

- RP2040 board, video connector, cables, and jumper wiring are available.
- Remaining parts are expected on 2026-10-15.

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
- Gowin EDA 1.9.11.03: https://www.gowinsemi.com/en/document/main/database/1865/
- Verilator installation: https://veripool.org/guide/latest/install.html
- Pico SDK 2.3.1: https://www.raspberrypi.com/documentation/pico-sdk/

## Verify When the Board Arrives

- Board revision and SDRAM component marking.
- Schematic revision, FPGA pin map, I/O standards, and voltages.
- 27 MHz oscillator behavior and legal PLL outputs.
- Programmer/debugger enumeration and LED bitstream.
- Monitor acceptance of the generated 640 x 480 mode.

No hardware milestone is marked complete before these checks.
