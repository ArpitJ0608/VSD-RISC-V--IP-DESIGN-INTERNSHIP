# SPI Master IP — VSDSquadron FPGA / RISC-V SoC

**A commercial-grade, memory-mapped, polling-based SPI Master peripheral for the VSDSquadron Fpga based RISC-V SoC.**

![Status](https://img.shields.io/badge/status-simulation--verified-green)
![Interface](https://img.shields.io/badge/interface-Memory--Mapped%20IO-blue)
![Mode](https://img.shields.io/badge/SPI-Mode%200%20(CPOL%3D0%2C%20CPHA%3D0)-lightgrey)
![Width](https://img.shields.io/badge/data%20width-8--bit-orange)

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Repository Structure](#repository-structure)
4. [Quick Start](#quick-start)
5. [Folder Description](#folder-description)
6. [Documentation](#documentation)
7. [Example Output](#example-output)
8. [Future Work](#future-work)
9.

---

## Overview

The **SPI Master IP** is a completely synchronous, register-driven SPI Master peripheral specifically designed for use in the VSDSquadron FPGA RISC-V SoC. This enables firmware executing on the RISC-V core to conduct 8-bit SPI transactions (Mode 0) by merely writing to a few memory-mapped registers – no interrupts, no SPI controller, and no need for a proprietary IP license.

This IP has been designed, implemented and simulated through all phases of verification: RTL -> RISC-V SoC Integration -> C firmware -> successfully completing loopback transactions.

> **This is for you if:** you own a VSDSquadron FPGA, have a RISC-V soft-core SoC, and do not wish to delve into a single line of Verilog.

---

## Features

| Feature | Value |
|---|---|
| Protocol | SPI, Mode 0 (`CPOL = 0`, `CPHA = 0`) |
| Data width | 8-bit, MSB-first |
| Clock source | Programmable divider (8-bit `CLKDIV` field) |
| Chip Select | Active-low (`cs_n`), asserted for the full transaction |
| Interface | Memory-mapped I/O, 4 × 32-bit registers |
| Transfer model | Polling (`BUSY` / `DONE` status bits) — **no interrupt support** |
| Bus protocol | Same `write_en` / `addr_off` / `w_data` / `r_data` convention as the existing GPIO IP |
| Verification | 3 independent loopback transfers (`0xA5`, `0xFA`, `0xBE`), all `PASS` |

**Known limitation**: single-channel, single-byte-per-transaction, no interrupt, no multi-slave chip-select decoding, no DMA. 
---

## Repository Structure

```
ip/spi_master/
├── README.md                  <-- you are here
├── rtl/
│   ├── spi_master.v           Top-level SPI Master (registers + FSM + glue)
│   ├── spi_clk_div.v          Programmable SPI clock generator
│   └── spi_shift.v            8-bit MSB-first TX/RX shift register
├── software/
│   ├── test_spi.c             Example / validation firmware
│   └── io.h                   Memory-mapped register offsets
├── docs/
│   ├── IP_User_Guide.md       What the IP is, how it behaves, limitations
│   ├── Register_Map.md        Complete register/bitfield reference
│   ├── Integration_Guide.md   How to wire this IP into a SoC
│   ├── Example_Usage.md       Full walkthrough of test_spi.c
└── images/                    Supporting screenshots referenced by the docs
```

---

## Quick Start

1. Copy the three files in `rtl/` into your SoC's RTL source tree.
2. Instantiate `spi_master` inside your SoC top module (`riscv.v` or equivalent) — see [`docs/Integration_Guide.md`](docs/Integration_Guide.md) for the exact wiring.
3. Add the four `IO_SPI_*` offsets from `software/io.h` to your firmware's I/O header.
4. Build and run `software/test_spi.c` (or adapt it) to validate the integration.
5. Expect to see `PASS` printed over UART when `RXDATA == TXDATA` in loopback mode.

```bash
# Typical simulation flow (Icarus Verilog)
cd RTL/
iverilog -DBENCH -o simv riscv.v
vvp simv
```

---

## Folder Description

| Folder | Contents | Who needs it |
|---|---|---|
| `rtl/` | Synthesizable Verilog for the IP itself | Hardware/RTL integrators |
| `software/` | Reference C firmware + register header | Firmware developers |
| `docs/` | Full commercial-style documentation set | Everyone — start here |
| `images/` | Screenshots of RTL, terminal logs, and simulation results referenced throughout `docs/` | Documentation readers |

---

## Documentation

| Document | Purpose |
|---|---|
| [`docs/IP_User_Guide.md`](docs/IP_User_Guide.md) | Purpose, applications, features, functional description, FSM, limitations |
| [`docs/Register_Map.md`](docs/Register_Map.md) | Complete register table, bitfields, reset values, read/write behaviour, examples |
| [`docs/Integration_Guide.md`](docs/Integration_Guide.md) | Step-by-step SoC integration: RTL instantiation, address decode, pin/software changes |
| [`docs/Example_Usage.md`](docs/Example_Usage.md) | Full explanation of `test_spi.c`, transfer flowchart, PASS condition |
---

## Example Output

Simulation log for a single transfer (`TX_VALUE = 0xBE`, loopback `MISO = MOSI`):

```
===== SPI MASTER TEST =====
SPI CTRL = 0x00000A01
TX DATA  = 0x000000BE
SPI START
SPI DONE
Transfer Started...
STATUS   = 0x00000002
RX DATA  = 0x000000BE
PASS
```

Three independent data patterns (`0xA5`, `0xFA`, `0xBE`) were verified.
---

## Future Work

-Transfer completion via interrupts (polling currently implemented only)
- Multi-byte transfer bursts (single-byte transfers using `START` currently)
- Multi-chip select slaves (`cs_n` pin current implementation)
- SPI Mode 1/2/3 support (variable `CPOL`/`CPHA`) 
- Board-level verification on VSDSquadron FPGA platform (simulation verification done)

---


