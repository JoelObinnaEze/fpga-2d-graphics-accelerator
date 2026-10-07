# ADR-001: Use Gowin's Embedded SDRAM Controller

## Status

Accepted

## Date

2026-10-06

## Context

The Tang Nano 20K's 64-Mbit, 32-bit SDR SDRAM is system-in-package memory
inside the GW2AR-18 rather than a separately marked PCB component. Gowin's
embedded-memory flow requires the SDRAM-side ports to retain exact names at the
FPGA top level so place-and-route can connect the package-internal interface.
Those ports intentionally have no user CST pin constraints.

The project still needs portable scheduling, buffering, scanout, and rendering
logic, but reproducing the fixed package interface and its initialization and
refresh behavior as independent project RTL would add hardware risk without
making those portable layers better.

## Decision

Use the encrypted `SDRAM_controller_top_SIP` from Gowin's official GW2AR-18
reference design for initialization, refresh, physical SDRAM commands, and the
package-internal data path. Preserve the upstream file unchanged and keep its
source URL and checksum in `vendor/gowin/README.md`.

Wrap its 21-bit word-addressed, 32-bit user interface with project-owned RTL.
The initial board target uses a 162 MHz controller clock and an equal-frequency,
phase-shifted SDRAM clock derived from the onboard 27 MHz oscillator. Project
simulation verifies the request logic against a behavioral controller model;
hardware readback and timing reports verify the integrated boundary.

## Alternatives Considered

### Handwritten physical SDRAM controller

- Pro: all source would be visible and directly controlled by the project.
- Con: the SiP interface has vendor-defined routing and fixed parameters, and
  the supported flow is the Gowin embedded controller.
- Rejected: it adds avoidable risk at the non-portable package boundary.

### Depend on an untracked local IP-generator output

- Pro: no vendor artifact in the repository.
- Con: builds would depend on local GUI state and could silently use different
  generated source.
- Rejected: the official generated artifact is small enough to pin and verify.

### Add external SDRAM

- Pro: a conventional, fully documented physical bus.
- Con: extra hardware and wiring while an 8 MiB device is already in-package.
- Rejected: unnecessary for the required 640 x 480 RGB565 buffers.

## Consequences

- The physical controller depends on Gowin EDA and an encrypted vendor module.
- Exact SDRAM-side top-level port names are part of the hardware contract.
- Portable framebuffer logic remains isolated behind the controller's user
  interface and can still use behavioral or BSRAM models in simulation.
- Any memory-clock or phase change requires fresh timing analysis and physical
  readback testing.
