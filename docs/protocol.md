# RP2040-to-FPGA Command Protocol v1

## Electrical Contract

- SPI mode 0: clock idle low, sample MOSI on rising edges, change MISO on falling edges.
- Bytes are sent most-significant bit first.
- Each active-low chip-select interval contains exactly one packet.
- Initial SCLK is 8 MHz. Raise it only after CDC and hardware measurements pass.
- A separate active-high `READY` GPIO is sampled before chip select is asserted.
  `READY` guarantees room for one complete command; it never changes the packet
  already in flight and the FPGA never silently drops that packet.
- The FPGA samples synchronized SPI inputs in the 100.8 MHz system-clock domain.
  The system clock must remain at least 8 times faster than SCLK; the selected
  8 MHz SCLK has a 12.6x margin. Any clock change must preserve this bound.

## Packet

| Byte | Field | Meaning |
| --- | --- | --- |
| 0 | Magic | `0xA5` |
| 1 | Opcode | Command identifier below |
| 2 | Length | Payload byte count |
| 3 | Sequence | Host-selected identifier, echoed in completion status |
| 4..N | Payload | Little-endian fields |
| N+1 | CRC-8 | Polynomial `0x07`, initial value `0x00`, over opcode through payload |

Chip select rising before the CRC aborts the packet and increments the protocol
error counter. Bad magic, opcode, length, or CRC also rejects the whole packet.

## Commands

| Opcode | Name | Payload |
| --- | --- | --- |
| `0x01` | `CLEAR` | `color:u16` |
| `0x02` | `DRAW_RECT` | `x:u16, y:u16, width:u16, height:u16, color:u16` |
| `0x03` | `DRAW_SPRITE` | `sprite_id:u16, x:u16, y:u16` |
| `0x04` | `PRESENT` | empty |

Coordinates are unsigned. Unknown opcodes and noncanonical lengths are errors.
Commands enter the FIFO only after the complete packet and CRC validate.

## Status

MISO repeats the current status byte while MOSI sends a packet:

| Bit | Meaning |
| --- | --- |
| 0 | Ready for one complete packet |
| 1 | Graphics engine busy |
| 2 | Protocol error latched |
| 3 | Presentation pending |
| 7:4 | Protocol version (`0x1`) |

Firmware treats queued, executing, memory-committed, and presented as distinct
states. `PRESENT` completion is identified by its sequence value in the later
status-register implementation.
