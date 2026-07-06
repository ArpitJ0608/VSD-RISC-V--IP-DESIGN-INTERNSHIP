# SPI Master IP — User Guide

**IP Name:** SPI Master (Mode 0, 8-bit, Polling-Based)
**Platform:** VSDSquadron FPGA / RISC-V SoC
**Document Type:** IP User Guide

---

## Table of Contents

1. [Purpose](#purpose)
2. [Applications](#applications)
3. [Features](#features)
4. [Architecture Overview](#architecture-overview)
5. [Functional Description](#functional-description)
   - [SPI Protocol Overview](#spi-protocol-overview)
   - [State Machine](#state-machine)
   - [Clock Generation](#clock-generation)
   - [Shift Register Timing](#shift-register-timing)
   - [Clock Divider Behaviour](#clock-divider-behaviour)
6. [FSM Explanation](#fsm-explanation)
7. [Limitations](#limitations)
8. [Notes & Tips](#notes--tips)

---

## Purpose

This IP has a memory mapped SPI Master interface that allows an SPI transaction to be performed by a RISC-V core on the VSDSquadron SoC through purely register accesses; there is no need for any external SPI master controller, interrupts, nor bus protocols other than the existing peripheral bus.

It is assumed that the reader of this guide has never seen the **RTL code** before. Everything one needs to know about this IP without having to look at a single `*.v` file is available in this document and other related documents.

---

## Applications

- Running of SPI interface sensors (accelerometer, analog-to-digital converters, etc.)
- Communicating with SPI Flash/EEPROM components
- Driving SPI display or peripheral expanders
- Development of custom SPI slaves and their debugging according to the provided loopback example
- Applications that can be solved with a light-weight and poll-based SPI master-slave link (without DMA and interrupts)
---

## Features

| Category | Detail |
|---|---|
| SPI Mode | Mode 0 — `CPOL = 0`, `CPHA = 0` |
| Data width | 8 bits, MSB-first |
| Clock | Programmable divider, `SCLK` derived from system clock |
| Chip Select | Active-low `cs_n`, held low for the entire transaction |
| Transfer trigger | Software sets `START` bit; auto-clears |
| Completion signalling | `STATUS.DONE` (write-1-to-clear), `STATUS.BUSY` |
| Interrupts | **None** — polling only |
| Bus interface | 4 × 32-bit memory-mapped registers, same decode convention as the existing GPIO IP |
| Multi-slave support | **None** — single `cs_n` output |
| Burst transfers | **None** — one byte per `START` pulse |

---

## Architecture Overview

```
                +-----------------------------------------------+
                |                 spi_master.v                  |
                |                                                |
   CPU BUS  --->|  Register Decode  --->  FSM (IDLE/LOAD/        |
 write_en,      |  (CTRL/TXDATA/         TRANSFER/DONE)          |
 addr_off,      |   RXDATA/STATUS)            |                  |
 w_data    <----|                              |                 |
   r_data       |                    +---------+---------+       |
                |                    |                   |       |
                |            spi_clk_div.v         spi_shift.v   |
                |          (SCLK + tick gen)     (TX/RX shifter) |
                |                    |                   |       |
                +--------------------|-------------------|-------+
                                     v                   v
                                  sclk        mosi -----> (to slave)
                                  cs_n        miso <----- (from slave)
```


---

## Functional Description

### SPI Protocol Overview

This IP implements **SPI Mode 0**:
- **CPOL = 0** — the clock line idles **low** between transactions.
- **CPHA = 0** — data is sampled on the **first (rising) clock edge** of each bit period.

Each transaction is exactly **8 bits**, transmitted and received **simultaneously** (full-duplex), **MSB first**.

### State Machine

The IP is managed by a 4-state finite state machine:

| State | Explanation |
|---|---|
| `IDLE` | Awaiting command from software to initiate the transfer |
| `LOAD` | One cycle state: Loads TX byte into shifter, drives `cs_n` low |
| `TRANSFER` | The state where the actual shifting happens, triggered by `tick` of the clock divider |
| `DONE` | One cycle state: Latches the received byte, sets the `DONE` flag |

See [FSM Explanation](#fsm-explanation) below.

### Clock Generation

`SCLK` is **not** the system clock — it is generated internally by dividing the system clock according to the software-programmable `CLKDIV` field (`CTRL[15:8]`):

```
SCLK toggles every (CLKDIV + 1) system-clock cycles
```

`SCLK` only runs while a transfer is active (`state == TRANSFER`); it idles low the rest of the time, consistent with `CPOL = 0`.

### Shift Register Timing

Upon entering `LOAD`, the shift register gets loaded with the data byte in `TXDATA`. In every `tick` signal from the clock divider (on every edge of SCLK) while in `TRANSFER`:
- The TX shifter shifts **left** and feeds its MSB through `MOSI`.
- The RX shifter shifts **left** and loads the `MISO` bit into its LSB.

The RX shifter after 8 ticks will contain the received data byte, and the FSM switches to `DONE`.

### Clock Divider Behaviour

| `CLKDIV` value | SCLK period (in system-clock cycles) |
|---|---|
| `0` | 1 |
| `10` | 11 |
| `255` | 256 |

Choose `CLKDIV` so the resulting `SCLK` frequency is within the target SPI slave device's supported range.

---

## FSM Explanation

```
        reset
          |
          v
   +-------------+     EN & START      +-------+
   |    IDLE     |-------------------->| LOAD  |
   +-------------+                     +-------+
          ^                                |
          |                                | (1 cycle: load shifter,
          |                                |  cs_n = 0, BUSY = 1,
          |                                |  START auto-clears)
          |                                v
          |                          +-----------+
          |     bit_count==7 & tick  | TRANSFER  |
          |<-------------------------|           |
          |                          +-----------+
          |                                |
          |                                v
          |                          +-----------+
          +--------------------------|   DONE    |
                (1 cycle: BUSY=0,     +-----------+
                 DONE=1, latch RX)
```

- **IDLE → LOAD**: requires both `CTRL.EN` (bit 0) and `CTRL.START` (bit 1) to be `1`.
- **LOAD → TRANSFER**: unconditional, one cycle after entering `LOAD`.
- **TRANSFER → DONE**: when `bit_count == 7` and a `tick` has occurred (8th bit shifted).
- **DONE → IDLE**: unconditional, one cycle after entering `DONE`.

---

## Limitations

- **No interrupts supported.** Completion is determined by polling `STATUS.DONE`.
- **Byte transfers only.** A single `START` triggers exactly 8 bits of transfer; no burst or multi-byte modes.
- **Single chip-select line.** A single `cs_n` output is available; no internal multi-slave decoding.
- **Mode 0 only.** `CPOL`/`CPHA` are not configurable in software in this revision.
- **No DMA.** Data transfer is via CPU register I/O only.
- **`CLKDIV` divider range.** An 8-bit field; therefore the maximum divider ratio is 256 times the system clock.

---

## Notes & Tips

- The `CLKDIV` register should always be programmed first and `EN = 1` should be done **before** `START` – otherwise, writing `CTRL` with `START` will have no effect because the FSM checks `START` and `EN` together in `IDLE` state.
- The `START` flag clears automatically – you don’t need to (and cannot) clear it by yourself.
- The `DONE` flag is **write-1-to-clear**. Reading `STATUS` doesn’t clear `DONE` – only write-back of bit 1 clears it.
- To perform fast hardware test without an attached SPI peripheral just connect `MISO` to `MOSI` (loopback), as in simulation.