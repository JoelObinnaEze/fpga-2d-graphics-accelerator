# Gowin generated SDRAM controller

`SDRAM_controller_top_SIP.v` is the unmodified encrypted controller generated
by Gowin's official `SDRAM Controller GW2AR-18 RefDesign`, published on
2023-09-04. It is included because the GW2AR-18 embedded SDRAM uses fixed,
vendor-defined package-internal interface routing.

- Upstream page: <https://www.gowinsemi.com/en/support/ip_detail/5/>
- Upstream archive: <https://www.gowinsemi.com/upload/database_doc/2058/document/64f5457822ba5.rar>
- SHA-256: `B3197AA3EC2C5C63CAB8B64B6BC3BCEDB6D9FBF2AF98B09F238285BE306B4EEB`

Keep the SDRAM-side port names unchanged at the FPGA top level. Gowin's tools
use those names to route the signals within the system-in-package device.
