# SPI Master IP — Integration Guide

**Objective**: to explain how to "connect this IP to my VSDSquadron SoC" - based on the understanding that you know about the VSDSquadron FPGA / RISC-V SoC, but not about this IP inside out.

---

## Table of Contents

1. [Required RTL Files](#required-rtl-files)
2. [Where to Instantiate the IP](#where-to-instantiate-the-ip)
3. [Address Decoder Modifications](#address-decoder-modifications)
4. [Memory-Mapped Interface](#memory-mapped-interface)
5. [CPU / Read-Data Connections](#cpu--read-data-connections)
6. [Pin Descriptions (Board-Level)](#pin-descriptions-board-level)
7. [Software Changes](#software-changes)
8. [Compilation](#compilation)
9. [Simulation](#simulation)

---

## Required RTL Files

Copy all three files from `rtl/` into your SoC's RTL source directory:

| File | Role |
|---|---|
| `spi_master.v` | Top-level module — instantiate **this one** in your SoC |
| `spi_clk_div.v` | Instantiated internally by `spi_master.v` |
| `spi_shift.v` | Instantiated internally by `spi_master.v` |

You only need to instantiate `spi_master` at the SoC level — `spi_clk_div` and `spi_shift` are internal sub-modules.

> `spi_master_m1.png` … `spi_master_m5.png` — full annotated source of `spi_master.v`
> `spi_clk_div_code.png` — full source of `spi_clk_div.v`
> `spi_shiftreg_code.png` — full source of `spi_shift.v`

![spi_master.v ports & registers](/Task-6/spi_master_m1.png)
![spi_clk_div.v](/Task-6/spi_clk_div_code.png)
![spi_shift.v](/Task-6/spi_shiftreg_code.png)

---

## Where to Instantiate the IP

Instantiate `spi_master` inside your SoC top-level module, alongside your existing GPIO/UART peripheral instances:

```verilog
// Spi module Instantiation
spi_master SPI(
    .clk(clk),
    .rst(!resetn),
    .write_en(spi_write),
    .addr_off(addr_off),
    .w_data(mem_wdata),
    .r_data(spi_rdata),
    .sclk(spi_sclk),
    .mosi(spi_mosi),
    .miso(spi_mosi),   // loopback for bring-up; replace with a real MISO pin on hardware
    .cs_n(spi_cs_n)
);
```

> `spi_ip_inst_riscv.png` — `spi_master` instantiated alongside GPIO/UART in `riscv.v`

![spi_master instantiation](/Task-6/spi_ip_inst_riscv.png)

> **Important:** `.miso(spi_mosi)` above is a **simulation loopback** connection used for bring-up and self-checking tests For real hardware, `.miso(...)` must be connected to the SPI slave device's `MISO`/`SDO` line via a board pin, not tied to `MOSI`.

---

## Address Decoder Modifications

Add the following wires and decode logic to your SoC's top-level module, at the same place where GPIO/UART decode signals are declared:

```verilog
wire spi_write;
wire [31:0] spi_rdata;
wire spi_sclk;
wire spi_mosi;
wire spi_cs_n;
wire [1:0] addr_off;
wire spi_sel; // to select bit from wordaddress

assign spi_sel   = isIO & mem_wordaddr[3] & mem_wordaddr[2];
assign addr_off  = mem_wordaddr[1:0];
assign spi_write = spi_sel & mem_wstrb;
```

> `spi_variable_riscv.png` — new SPI wires and `spi_sel` / `spi_write` decode logic

![SPI wires and address decode](Task-6/spi_variable_riscv.png)

**Why this works:** The signal `spi_sel` asserts a 4-word (16-byte) address window based on the top 2 bits of the word address, irrespective of the 1-bit decode used for the GPIO/UART. The `addr_off` (same 2-bit bus used by the GPIO) is repurposed in this case for the `spi_master`.

---

## Memory-Mapped Interface

| Signal | Direction (from IP) | Connect to |
|---|---|---|
| `write_en` | input | `spi_write` (derived from `spi_sel & mem_wstrb`) |
| `addr_off[1:0]` | input | SoC's shared 2-bit register sub-selector (`mem_wordaddr[1:0]`) |
| `w_data[31:0]` | input | SoC's shared CPU write-data bus (`mem_wdata`) |
| `r_data[31:0]` | output | Feed into the SoC's `IO_rdata` read mux, gated by `spi_sel` |
| `sclk` | output | SPI clock pin |
| `mosi` | output | SPI MOSI pin |
| `miso` | input | SPI MISO pin (or loopback, for bring-up only) |
| `cs_n` | output | SPI chip-select pin (active low) |

---

## CPU / Read-Data Connections

Extend your SoC's `IO_rdata` read-back multiplexer to route reads through `spi_rdata` whenever `spi_sel` is asserted:

```verilog
wire [31:0] IO_rdata =
        spi_sel ? spi_rdata :
        mem_wordaddr[IO_GPIO_bit] ? gpio_rdata :
        mem_wordaddr[IO_UART_CNTL_bit] ? { 22'b0, !uart_ready, 9'b0}
                                        : 32'b0;

assign mem_rdata = isRAM ? RAM_rdata : IO_rdata ;
```

> `IO_read_riscv.png` — `IO_rdata` mux extended with the `spi_sel` case

![IO_rdata mux extended for SPI](/Task-6/IO_read_riscv.png)

Place the `spi_sel` check **first** in the priority chain (as shown above) so it takes precedence over the GPIO/UART checks whenever the SPI address window is active.

For reference, the overall SoC top-level module and its benchtest clock/reset generation:

> `Soc_top_module.png` — `module SOC(CLK, RESET, LEDS, RXD, TXD)` port list and benchtest clock/reset

![SOC top-level module](/Task-6/Soc_top_module.png)

---

## Pin Descriptions (Board-Level)

| Signal   | FPGA pin use                  | Comments                             |
|----------|-------------------------------|--------------------------------------|
| `sclk`   | SPI Clock output              | Connect to the target SPI Slave `SCLK`/`SCK` pin       |
| `mosi`   | SPI data output               | Connect to the target SPI Slave `MOSI`/`SDI` pin       |
| `miso`   | SPI data input                | Connect to the target SPI Slave `MISO`/`SDO` pin       |
| `cs_n`   | Chip select output (active low)| Connect to the target SPI Slave `CS`/`SS` pin         |

Update your board's constraint file (`.pcf`, `.xdc`, etc.) with these four signal names and assign them to the header pins that you are using for your SPI Slave target device.

---

## Software Changes

1. Copy `software/io.h` offsets into your firmware's I/O header (or merge the four `IO_SPI_*` `#define`s into your existing `io.h`):

```c
#define IO_SPI_CTRL    48
#define IO_SPI_TXDATA  52
#define IO_SPI_RXDATA  56
#define IO_SPI_STATUS  60
```

2. Use `software/test_spi.c` as a starting template for your own SPI application code — see [`Example_Usage.md`](Example_Usage.md) for a full walkthrough.

---

## Compilation

Using the existing VSDSquadron firmware build flow (`riscv64-unknown-elf-gcc` toolchain):

```bash
cd Firmware/
make test_spi_update
```

Expected build output includes:

```
riscv64-unknown-elf-gcc ... -c test_spi.c
riscv64-unknown-elf-as  ... start.S -o start.o
...
riscv64-unknown-elf-ld -T bram.ld -m elf32lriscv -nostdlib test_spi.o ... -o test_spi.bram.elf
./firmware_words test_spi.bram.elf -ram 6144 -max_addr 6144 -out test_spi.hex
Code size: 712 words ( total RAM size: 1536 words )
Occupancy: 46%
```

> `spi_hexgen.png` — full terminal log of `make test_spi_update`

![Build log](/Task-6/spi_hexgen.png)

---

## Simulation

```bash
cd RTL/
iverilog -DBENCH -o simv riscv.v
vvp simv
```

Expected console output (loopback test, `TX_VALUE = 0xBE`):

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
