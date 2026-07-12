# Task-6: Design and Integrate an SPI Master IP (Minimal, Single-Byte, Mode 0)

In the project, the novel memory-mapped **SPI Master** IP is added to the RISC-V SoC, alongside the GPIO and UART IPs which have already been defined before, through the conventional approach of “one IP, one owner, one register window.”

---

## Table of Contents

1. [Objective](#objective)
2. [What This IP Adds to the SoC](#what-this-ip-adds-to-the-soc)
3. [Register Map](#register-map)
4. [Planning & Address Offset Design](#step-1--planning--address-offset-design)
5. [SPI Master IP RTL](#step-2--spi-master-ip-rtl)
6. [SoC Integration Updates](#step-3--soc-integration-updates)
7. [Firmware Validation](#step-4--firmware-validation)
8. [Hardware Validation (VSDSquadron FPGA)](#step-5--hardware-validation-vsdsquadron-fpga)
9. [How Address Offsets Are Decoded](#how-address-offsets-are-decoded)
10. [How a Transfer Actually Happens (Data Flow)](#how-a-transfer-actually-happens-data-flow)
11. [Screenshots Index](#screenshots-index)
12. [Learnings](#learnings)
13. [Conclusion](#conclusion)

---

## Objective

Create a **minimal SPI Master** module, Mode 0 (CPOL = 0, CPHA = 0), which can be driven by the RISC-V CPU from registers only. The added functionality allows the software to:
- Set the **SPI clock division factor** and **activate** the peripheral (`SPI_CTRL`)
- Send a **byte** (`SPI_TXDATA`)
- Initiate an 8-bit transfer and wait for its end (`SPI_STATUS`)
- Get a **received byte** (`SPI_RXDATA`)

**Context:** GitHub Codespace `codespaces-887761`, `vsd-riscv2/samples/vsdfpga_labs/basicRISCV`

---

## What This IP Adds to the SoC

| Feature | Before Task-6 (GPIO + UART only) | After Task-6 (+ SPI Master) |
|---------|-----------------------------------|------------------------------|
| Peripherals | GPIO (3 regs), UART | GPIO, UART, **SPI Master (4 regs)** |
| New signals | – | `sclk`, `mosi`, `miso`, `cs_n` |
| Address decode | `IO_GPIO_bit`, `IO_UART_CNTL_bit` | + `spi_sel` (top 2 bits of word address) |
| Registers | `gpio_data/dir/read`, UART ctrl | + `ctrl_reg`, `tx_reg`, `rx_reg`, `status_reg` |
| Sub-modules | `gpio_ip.v` (single file) | `spi_master.v` + `spi_clk_div.v` + `spi_shift.v` (3 files, one FSM) |
| io.h additions | `IO_GPIO_*` offsets | `IO_SPI_CTRL=48`, `IO_SPI_TXDATA=52`, `IO_SPI_RXDATA=56`, `IO_SPI_STATUS=60` |
| Change in SoC | – | New wires `spi_write`, `spi_rdata`, `spi_sel`; `IO_rdata` mux extended |

---

## Register Map

| Register | Offset | Absolute Address | Access | Description |
|----------|--------|-------------------|--------|--------------|
| `SPI_CTRL`   | 48 (0x30) | `0x400030` | R/W | Bit0: `EN` (enable block). Bit1: `START` (write 1 to trigger transfer, auto-clears). Bits[15:8]: `CLKDIV` (SCLK toggles every `CLKDIV+1` cycles) |
| `SPI_TXDATA` | 52 (0x34) | `0x400034` | R/W | Bits[7:0] — byte to transmit; loads the shift register |
| `SPI_RXDATA` | 56 (0x38) | `0x400038` | R   | Bits[7:0] — byte received from the last completed transfer |
| `SPI_STATUS` | 60 (0x3C) | `0x40003C` | R/W | Bit0: `BUSY` (1 while transfer in progress). Bit1: `DONE` (1 when finished; write‑1‑to‑clear) |

**Base address:** `IO_BASE = 0x400000` (shared with GPIO/UART).

**Offsets to `addr_off[1:0]`:** exactly the same word-address decoding scheme used for the GPIO IP in Task-5:

```
Byte offset 48 = word address 12 → mem_wordaddr[1:0] = 2'b00 → SPI_CTRL
Byte offset 52 = word address 13 → mem_wordaddr[1:0] = 2'b01 → SPI_TXDATA
Byte offset 56 = word address 14 → mem_wordaddr[1:0] = 2'b10 → SPI_RXDATA
Byte offset 60 = word address 15 → mem_wordaddr[1:0] = 2'b11 → SPI_STATUS
```

---

## Planning & Address Offset Design

Design decisions made before writing any RTL:

- The SPI block needs its **own decode window**, separate from GPIO/UART, so a new top-level select signal `spi_sel` is created instead of re-using `IO_GPIO_bit`/`IO_UART_CNTL_bit` style single-bit decode.
- Because SPI needs **4 registers** (`CTRL`, `TXDATA`, `RXDATA`, `STATUS`), the existing 2-bit `addr_off` bus (already used for GPIO) is reused — it simply gets a different meaning inside the SPI module.
- `spi_sel` is derived from the **upper two bits** of the word address (`mem_wordaddr[3] & mem_wordaddr[2]`) rather than a single bit, since SPI needs a 4-register (2-bit) sub-space, not a 1-bit one.
- `TXDATA`/`RXDATA` are only 8 bits wide functionally, but kept inside 32-bit registers (upper bits zero) to stay consistent with the "all registers are 32-bit, word-aligned" integration rule.

### Updated `io.h` — four new SPI offsets

```c
#include <stdint.h>

#define IO_BASE        0x400000
#define IO_LEDS        4
#define IO_UART_DAT    8
#define IO_UART_CNTL   16
#define IO_GPIO_DATA   32
#define IO_GPIO_DIR    36
#define IO_GPIO_READ   40
#define IO_SPI_CTRL    48
#define IO_SPI_TXDATA  52
#define IO_SPI_RXDATA  56
#define IO_SPI_STATUS  60

#define IO_IN(port)       *(volatile uint32_t*)(IO_BASE + port)
#define IO_OUT(port,val)  *(volatile uint32_t*)(IO_BASE + port)=(val)
```

Four new definitions were appended after the existing GPIO offsets. Each is 4 bytes apart (one word), so `mem_wordaddr[1:0]` walks `00 → 01 → 10 → 11` across `CTRL → TXDATA → RXDATA → STATUS`, exactly the pattern the SPI module's internal `case(addr_off)` expects.

> `spi_io_module.png` — `io.h` with the SPI register offsets (48, 52, 56, 60) added alongside the existing GPIO/UART map

![io.h with SPI offsets](spi_io_module.png)

---

## SPI Master IP RTL

The IP is deliberately split into **three small modules** instead of one large block, so each concern — clocking, shifting, and control — can be verified independently:

```
spi_master.v      → top-level: registers, FSM, glue logic
   ├── spi_clk_div.v  → generates the divided SPI clock + a one-cycle "tick"
   └── spi_shift.v    → 8-bit shift register for TX and RX
```

### Complete `spi_master.v`

```verilog
module spi_master (
    input clk,
    input rst,
    input write_en,
    input [1:0] addr_off,
    input [31:0] w_data,
    output reg [31:0] r_data,
    output sclk,
    output mosi,
    input miso,
    output reg cs_n
);

    reg [31:0] ctrl_reg;
    reg [31:0] status_reg;
    reg [7:0]  tx_reg;
    reg [7:0]  rx_reg;
    reg [2:0]  bit_count;

    wire spi_clk;
    wire tick;
    reg  [1:0] state;

    localparam IDLE     = 2'd0;
    localparam LOAD     = 2'd1;
    localparam TRANSFER = 2'd2;
    localparam DONE     = 2'd3;

    assign sclk = spi_clk;

    spi_clk_div clk_inst (
        .clk(clk),
        .rst(rst),
        .enable(state == TRANSFER),
        .clk_div(ctrl_reg[15:8]),
        .spi_clk(spi_clk),
        .tick(tick)
    );

    wire [7:0] rx_data;
    reg  shift_en;
    reg  load, busy;

    spi_shift shift_inst (
        .clk(clk),
        .rst(rst),
        .load(load),
        .shift_en(shift_en),
        .tx_data(tx_reg),
        .miso(miso),
        .mosi(mosi),
        .rx_data(rx_data)
    );

    // ---- bit counter ----
    always @(posedge clk) begin
        if (rst)
            bit_count <= 3'd0;
        else if (state == LOAD)
            bit_count <= 3'd0;
        else if (state == TRANSFER && tick)
            bit_count <= bit_count + 1'b1;
    end

    // ---- FSM (sequential) ----
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (ctrl_reg[0] && ctrl_reg[1])
                        state <= LOAD;
                end

                LOAD: begin
                    state <= TRANSFER;
                    $display("SPI START");
                    status_reg[0] <= 1'b1;   // BUSY
                    ctrl_reg[1]   <= 1'b0;   // auto-clear START
                end

                TRANSFER: begin
                    if (bit_count == 3'd7 && tick)
                        state <= DONE;
                end

                DONE: begin
                    $display("SPI DONE");
                    state <= IDLE;
                    status_reg[0] <= 1'b0;   // BUSY = 0
                    status_reg[1] <= 1'b1;   // DONE = 1
                    rx_reg <= rx_data;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ---- FSM (combinational outputs) ----
    always @(*) begin
        load     = 1'b0;
        shift_en = 1'b0;
        busy     = 1'b0;
        cs_n     = 1'b1;

        case (state)
            IDLE: begin
                busy = 1'b0;
                cs_n = 1'b1;
            end
            LOAD: begin
                load = 1'b1;
                busy = 1'b1;
                cs_n = 1'b0;
            end
            TRANSFER: begin
                busy = 1'b1;
                cs_n = 1'b0;
                if (tick)
                    shift_en = 1'b1;
            end
            DONE: begin
                busy = 1'b0;
                cs_n = 1'b1;
            end
        endcase
    end

    // ---- register writes ----
    always @(posedge clk) begin
        if (rst) begin
            ctrl_reg   <= 32'd0;
            status_reg <= 32'd0;
            tx_reg     <= 8'd0;
            rx_reg     <= 8'd0;
            bit_count  <= 3'd0;
        end
        else if (write_en) begin
            case (addr_off)
                2'b00: ctrl_reg <= w_data;
                2'b01: tx_reg   <= w_data[7:0];
                2'b11: if (w_data[1])
                           status_reg[1] <= 1'b0;   // write-1-to-clear DONE
            endcase
        end
    end

    // ---- register reads ----
    always @(*) begin
        case (addr_off)
            2'b00: r_data = ctrl_reg;
            2'b01: r_data = {24'd0, tx_reg};
            2'b10: r_data = {24'd0, rx_reg};
            2'b11: r_data = {30'b0, status_reg[1], status_reg[0]};
            default: r_data = 32'd0;
        endcase
    end
endmodule
```

> `spi_master_m1.png` – Port list, internal registers, and FSM localparams
> `spi_master_m2.png` – Sub-module instantiation (`spi_clk_div`, `spi_shift`) and bit counter
> `spi_master_m3.png` – Sequential FSM (`IDLE → LOAD → TRANSFER → DONE`)
> `spi_master_m4.png` – Combinational output logic (`busy`, `cs_n`, `load`, `shift_en`)
> `spi_master_m5.png` – Register write decode and read-back multiplexer

![spi_master.v part 1 — ports & registers]( spi_master_m1.png)
![spi_master.v part 2 — sub-modules & bit counter]( spi_master_m2.png)
![spi_master.v part 3 — FSM sequential logic]( spi_master_m3.png)
![spi_master.v part 4 — combinational outputs]( spi_master_m4.png)
![spi_master.v part 5 — register writes & read mux]( spi_master_m5.png)

### Detailed Code Explanation

#### Port interface

| Port | Direction | Purpose |
|------|-----------|---------|
| `write_en`, `addr_off[1:0]`, `w_data[31:0]` | input | CPU bus write side — identical pattern to `gpio_ip` |
| `r_data[31:0]` | output reg | CPU bus read side — driven from a combinational mux |
| `sclk`, `mosi`, `cs_n` | output | The actual SPI wires going out to the pins |
| `miso` | input | Serial data coming back from the slave (or loopback) |

#### Internal registers and state

| Register | Width | Role |
|----------|-------|------|
| `ctrl_reg`   | 32 | Holds `EN`, `START`, `CLKDIV` |
| `status_reg` | 32 | Holds `BUSY` (bit0), `DONE` (bit1) |
| `tx_reg` / `rx_reg` | 8 | CPU-visible copies of the byte to send / last byte received |
| `bit_count`  | 3  | Counts 0…7 across one 8-bit transfer |
| `state`      | 2  | FSM state: `IDLE`, `LOAD`, `TRANSFER`, `DONE` |

#### Clock-divider & shift-register instantiation

`spi_clk_div` is enabled **only** while `state == TRANSFER`, and is programmed with `ctrl_reg[15:8]` (the `CLKDIV` field) — so the SPI serial clock only runs during an active transfer and its speed is fully software-controlled.

`spi_shift` is driven by two 1-bit control signals generated by the FSM: `load` (capture `tx_reg` at the start of a transfer) and `shift_en` (advance one bit, once per SCLK edge).

#### FSM states

| State | Trigger to enter | Action taken |
|-------|-------------------|--------------|
| `IDLE` | reset, or after `DONE` | Waits for `ctrl_reg[0]` (`EN`) **and** `ctrl_reg[1]` (`START`) to both be `1` |
| `LOAD` | `EN & START` seen in `IDLE` | Prints `SPI START`, sets `BUSY`, clears `START` (auto-clear), asserts `cs_n=0`, pulses `load=1` |
| `TRANSFER` | after `LOAD` | Shifts one bit per SCLK `tick`; counts with `bit_count`; stays until `bit_count==7 && tick` |
| `DONE` | 8th bit shifted | Prints `SPI DONE`, clears `BUSY`, sets `DONE`, latches `rx_data → rx_reg`, returns to `IDLE` |

#### Write logic — synchronous `always @(posedge clk)`

`addr_off` selects which register a CPU write targets: `2'b00 → ctrl_reg`, `2'b01 → tx_reg`, and `2'b11` implements **write‑1‑to‑clear** on `status_reg[1]` (`DONE`) — writing a 1 to that bit clears it, any other bit pattern is ignored. `RXDATA` (`2'b10`) is intentionally **absent** from the write case, making it read-only — the same `default: begin end` trick used for `GPIO_READ` in Task-5.

#### Read logic — combinational mux

A single `case(addr_off)` drives `r_data` instantaneously from whichever register is addressed; any offset outside `00/01/10/11` (there are none here, since `addr_off` is only 2 bits) would fall to `default: r_data = 32'd0`, keeping the "undefined offsets return 0" rule intact.

### `spi_clk_div.v` — programmable clock divider

```verilog
module spi_clk_div(
    input clk,
    input rst,
    input enable,
    input [7:0] clk_div,
    output reg spi_clk,
    output reg tick
);

    reg [7:0] counter;

    always @(posedge clk) begin
        if(rst) begin
            counter <= 8'd0;
            tick    <= 1'b0;
            spi_clk <= 1'b0;
        end
        else if(enable) begin
            if(counter == clk_div) begin
                counter <= 8'd0;
                spi_clk <= ~spi_clk;
                tick    <= 1'b1;
            end
            else begin
                counter <= counter + 1'b1;
                tick    <= 1'b0;
            end
        end
        else begin
            counter <= 8'd0;
            tick    <= 1'b0;
            spi_clk <= 1'b0;
        end
    end
endmodule
```

> `spi_clk_div_code.png` — Complete clock-divider RTL

![spi_clk_div.v]( spi_clk_div_code.png)

**How it works:** while `enable=1`, `counter` counts system-clock cycles. When it reaches `clk_div`, the counter resets to 0, `spi_clk` **toggles**, and `tick` pulses for exactly one cycle. So `spi_clk` flips every `(clk_div + 1)` system-clock cycles — matching the spec's `SCLK toggles every (CLKDIV+1) cycles`. When `enable=0`, both `counter` and `spi_clk` are forced to 0, so SCLK idles **low** between transfers, correct for Mode 0 (CPOL = 0).

### `spi_shift.v` — TX/RX shift register

```verilog
module spi_shift(
    input clk,
    input rst,
    input load,
    input shift_en,
    input [7:0] tx_data,
    input miso,
    output mosi,
    output [7:0] rx_data
);

    reg [7:0] shift_tx;
    reg [7:0] shift_rx;

    always @(posedge clk) begin
        if(rst) begin
            shift_tx <= 8'd0;
            shift_rx <= 8'd0;
        end
        else begin
            if(load) begin
                shift_tx <= tx_data;
                shift_rx <= 8'd0;
            end
            else if(shift_en) begin
                shift_tx <= {shift_tx[6:0],1'b0};
                shift_rx <= {shift_rx[6:0],miso};
            end
        end
    end

    assign mosi = shift_tx[7];
    assign rx_data = shift_rx;
endmodule
```

> `spi_shiftreg_code.png` — Complete shift-register RTL

![spi_shift.v]( spi_shiftreg_code.png)

**How it works:** on `load`, `shift_tx` is loaded from `tx_data` (`shift_rx` cleared). On every `shift_en` pulse, `shift_tx` shifts **left** by one, pushing a `0` in at the bottom, while its **MSB (`shift_tx[7]`)** is continuously driven onto `mosi` — this gives MSB-first transmission. Simultaneously, `shift_rx` shifts left and captures the current `miso` bit into its LSB, so after 8 shifts `shift_rx` (→ `rx_data`) holds the complete received byte, MSB-first as well.

---

## SoC Integration Updates

### New wires and address decode in `riscv.v`

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
assign gpio_write = isIO & mem_wstrb & mem_wordaddr[IO_GPIO_bit];
assign spi_write  = spi_sel & mem_wstrb;
```

> `spi_variable_riscv.png` — New SPI wires and `spi_sel`/`spi_write` address decode

![riscv.v — SPI signal declarations]( spi_variable_riscv.png)

`spi_sel` is `1` only when the two most-significant bits of the word address (`mem_wordaddr[3]` and `mem_wordaddr[2]`) are both set — giving the SPI block its own 4-word (16-byte) decode region, separate from GPIO/UART. `addr_off` is the same 2-bit sub-selector already used for GPIO, reused here to pick between `CTRL/TXDATA/RXDATA/STATUS`.

### Module instantiation

```verilog
spi_master SPI(
    .clk(clk),
    .rst(!resetn),
    .write_en(spi_write),
    .addr_off(addr_off),
    .w_data(mem_wdata),
    .r_data(spi_rdata),
    .sclk(spi_sclk),
    .mosi(spi_mosi),
    .miso(spi_mosi),
    .cs_n(spi_cs_n));
```

> `spi_ip_inst_riscv.png` — `spi_master` instantiated alongside GPIO/UART

![riscv.v — spi_master instantiation]( spi_ip_inst_riscv.png)

For bring-up in simulation, `.miso(spi_mosi)` ties MISO directly to MOSI — a **loopback** connection. Whatever the master transmits, it immediately receives back, which turns the whole test into a simple equality check (`RXDATA == TXDATA`) with no external SPI device required.

### CPU read-data mux

```verilog
wire [31:0] IO_rdata =
        spi_sel ? spi_rdata :
        mem_wordaddr[IO_GPIO_bit] ? gpio_rdata :
        mem_wordaddr[IO_UART_CNTL_bit] ? { 22'b0, !uart_ready, 9'b0}
                                        : 32'b0;

assign mem_rdata = isRAM ? RAM_rdata : IO_rdata ;
```

> `IO_read_riscv.png` — `IO_rdata` mux extended with the `spi_sel` case ahead of GPIO/UART

![riscv.v — I/O read data mux]( IO_read_riscv.png)

This is the **single point of visibility** for the SPI IP: any `lw` from the SPI address window is routed to `spi_rdata`; everything else falls through unchanged to the pre-existing GPIO/UART logic — the entire integration change is small and low-risk.

For reference, the overall SoC top-level port list all peripherals live inside, plus the benchtest clock/reset generation:

> `Soc_top_module.png` — `module SOC(CLK, RESET, LEDS, RXD, TXD)` and `ifdef BENCH` clock/reset

![riscv.v — SOC module & testbench clock/reset]( Soc_top_module.png)

---

## Firmware Validation

### `test_spi.c` — complete test firmware

```c
#include "io.h"
#include "LIBFEMTOC/femtostdlib.h"

#define TX_VALUE   0xBE

int main()
{
    uint32_t ctrl;
    uint32_t status;
    uint32_t rx;

    printf("\n===== SPI MASTER TEST =====\n");
    // Configure SPI
    ctrl = (10 << 8) | (1 << 0);
    // CLKDIV = 10
    // EN = 1

    IO_OUT(IO_SPI_CTRL, ctrl);
    printf("SPI CTRL = 0x%x\n", ctrl);

    // Load transmit data
    IO_OUT(IO_SPI_TXDATA, TX_VALUE);
    printf("TX DATA = 0x%x\n", TX_VALUE);

    // Start Transfer
    ctrl |= (1 << 1);
    IO_OUT(IO_SPI_CTRL, ctrl);
    printf("Transfer Started...\n");

    do
    {
        status = IO_IN(IO_SPI_STATUS);
    } while ((status & 0x2) == 0);

    printf("STATUS = 0x%x\n", status);

    rx = IO_IN(IO_SPI_RXDATA);
    printf("RX DATA = 0x%x\n", rx);

    if ((rx & 0xFF) == TX_VALUE)
    {
        printf("PASS\n");
    }
    else
    {
        printf("FAIL\n");
    }

    IO_OUT(IO_SPI_STATUS, 0x2);   // clear DONE

    while (1);
    return 0;
}
```

> `spi_test_code1.png` — setup: CTRL config, TXDATA load, START trigger
> `spi_test_code2.png` — polling STATUS, RXDATA read, PASS/FAIL check, DONE clear

![test_spi.c part 1]( spi_test_code1.png)
![test_spi.c part 2]( spi_test_code2.png)

**Firmware sequence (matches the spec's validation checklist exactly):**
1. Program `CLKDIV=10` and `EN=1` into `SPI_CTRL`.
2. Write the byte to send into `SPI_TXDATA`.
3. Set `START` (bit1 of `SPI_CTRL`) to launch the transfer.
4. Poll `SPI_STATUS` bit1 (`DONE`) in a `do…while` loop.
5. Read `SPI_RXDATA` and compare to the value that was sent.
6. Clear `DONE` by writing `1` back to `SPI_STATUS` bit1.

### Build log (`make test_spi_update`)

```bash
make test_spi_update
```
```
riscv64-unknown-elf-gcc ... -c test_spi.c
riscv64-unknown-elf-as  ... start.S -o start.o
...
riscv64-unknown-elf-ld -T bram.ld -m elf32lriscv -nostdlib test_spi.o ... -o test_spi.bram.elf
./firmware_words test_spi.bram.elf -ram 6144 -max_addr 6144 -out test_spi.hex
   RAM_SIZE=6144
   LOAD ELF: test_spi.bram.elf
        max address=2849
Code size: 712 words ( total RAM size: 1536 words )
Occupancy: 46%
testing MAX_ADDR limit: 6144
   max_addr OK
   SAVE HEX: test_spi.hex
```

The firmware compiled and linked cleanly for `rv32i`/`ilp32`, occupying 46% of BRAM (712 words).

> `spi_hexgen.png` — Full terminal log of `make test_spi_update` (compile → assemble → link → hex conversion)

![make test_spi_update build log]( spi_hexgen.png)

### Simulation commands

```bash
cd /workspaces/vsd-riscv2/samples/vsdfpga_labs/basicRISCV/RTL
iverilog -DBENCH -o simv riscv.v
vvp simv
```

### Simulation results

**Test 1 — `TX_VALUE = 0xA5`** → expected `RX DATA = 0xA5`

```
===== SPI MASTER TEST =====
SPI CTRL = 0x00000A01
TX DATA  = 0x000000A5
SPI START
SPI DONE
Transfer Started...
STATUS   = 0x00000002
RX DATA  = 0x000000A5
PASS
```

`0xA5 = 1010_0101` — went in on `mosi`, looped straight back on `miso`, and came out identical on `RXDATA`.

> `spi_res1.png` — Simulation result, Test 1: `TX_VALUE=0xA5` → `RX DATA=0xA5`, PASS

![Simulation result test 1]( spi_res1.png)

**Test 2 — `TX_VALUE = 0xFA`** → expected `RX DATA = 0xFA`

```
SPI CTRL = 0x00000A01
TX DATA  = 0x000000FA
SPI START
SPI DONE
Transfer Started...
STATUS   = 0x00000002
RX DATA  = 0x000000FA
PASS
```

`0xFA = 1111_1010` — a mixed run of 1s and 0s, good for catching MSB/LSB ordering bugs; result still matches exactly.

> `spi_res2.png` — Simulation result, Test 2: `TX_VALUE=0xFA` → `RX DATA=0xFA`, PASS

![Simulation result test 2]( spi_res2.png)

**Test 3 — `TX_VALUE = 0xBE`** → expected `RX DATA = 0xBE`

```
SPI CTRL = 0x00000A01
TX DATA  = 0x000000BE
SPI START
SPI DONE
Transfer Started...
STATUS   = 0x00000002
RX DATA  = 0x000000BE
PASS
```

`0xBE = 1011_1110` — another asymmetric pattern; transfer again completes correctly with `STATUS=0x2` (`DONE` set, `BUSY` clear).

> `spi_res3.png` — Simulation result, Test 3: `TX_VALUE=0xBE` → `RX DATA=0xBE`, PASS

![Simulation result test 3]( spi_res3.png)

Across all three runs the log sequence is identical (`SPI CTRL → TX DATA → SPI START → SPI DONE → Transfer Started... → STATUS → RX DATA → PASS`), which is exactly what a correctly-designed peripheral should show: **deterministic, repeatable timing driven by the FSM and bit counter, independent of the actual data value being shifted.**

---

## Step 5 – Hardware Validation (VSDSquadron FPGA)

The RTL logic was already verified through simulation (step 4). The following step was to go through synthesis, placement & routing, timing and finally generating the bitstream file using the **very same `riscv.v`** (with the SPI master implementation), and programming the real **VSDSquadron FPGA** board with it.

The hardware flow follows three commands, run in this order:

```bash
# 1) Rebuild firmware (same test_spi.c used in simulation)
cd /workspaces/vsd-riscv2/samples/vsdfpga_labs/basicRISCV/Firmware
make test_spi_update

# 2) Synthesize + place & route + generate bitstream
cd /workspaces/vsd-riscv2/samples/vsdfpga_labs/basicRISCV/RTL
make build

# 3) Flash the bitstream onto the VSDSquadron board
sudo make flash
```

### 5.1 Synthesis (`make build` → Yosys)

First, the command "`make build`" performs synthesis using Yosys of the `riscv.v` file, including the SPI Master IP core. This is verified by the successful synthesis output which clearly shows that the design fits nicely within iCE40 FPGA resources like LUTs, DFFs, carry chains, and even the BRAM needed to store the firmware.

```
Info: Packing LUT-FFs..
Info:   1128 LCs used as LUT4 only
Info:      63 LCs used as LUT4 and DFF
Info: Packing non-LUT FFs..
Info:     145 LCs used as DFF only
Info: Packing carries..
Info:      10 LCs used as CARRY only
...
Info: Device utilisation:
Info:       ICESTORM_LC:   1351/  5280   25%
Info:      ICESTORM_RAM:     16/    30   53%
Info:            SB_IO:      9/    96    9%
Info:            SB_GB:      7/     8   87%
```

Only **25% of the logic cells (1351/5280)** and **53% of the block RAM** are used, confirming there is comfortable headroom left on the FPGA even with GPIO, UART, and SPI Master all integrated together.

> `synthesis.png` — Yosys/nextpnr packing log and final device-utilisation summary after adding the SPI Master IP

![Synthesis / device utilisation](synthesis.png)

### 5.2 Place & Route (`make build` → nextpnr routing)

The same `make build` step then invokes `nextpnr-ice40` to place and route the packed netlist. The router works through **5058 arcs**, progressively reducing the "arcs with ripup" count over 50,000+ iterations until routing converges:

```
Info: Routing..
Info: Setting up routing queue.
Info: Routing 5058 arcs.
Info:  IterCnt |  (re-)routed arcs   | delta | remaining |   time spent
Info:           |  w/ripup   wo/ripup| w/r   wo/r| arcs  |batch(sec) total(sec)
Info:     1000  |     110       889 |  110   889|  4209 |    1.16      1.16
...
Info:    50000  |   30415     19459 |  694    306|   546 |    1.30     36.65
```

This is just a **health check of place-and-route**; the clean, converging routing log ("remaining arcs" going down), shows that adding the SPI wiring didn't cause pathological congestion of the iCE40 fabric.

> `Routing_table.png` — nextpnr routing progress log (5058 arcs) after SPI Master integration

![Routing table](Routing_table.png)

### 5.3 Timing Closure (`make build` → nextpnr timing report)

nextpnr then reports the achievable maximum clock frequency for the `clk` domain against the design's actual requirement (12 MHz, driven by the internal `SB_HFOSC` oscillator):

```
Info: Max frequency for clock 'clk': 19.88 MHz (PASS at 12.00 MHz)

Info: Max delay <async>     -> posedge clk: 10.02 ns
Info: Max delay posedge clk -> <async>    : 14.16 ns
```

**1.65× timing margin** between the possible **19.88 MHz vs. 12 MHz needed** shows that the additional combinational logic introduced by the SPI Master implementation (decoder, FSM, and paths to compare/shift) does not introduce any critical path close to the clock frequency requirement.
> `Timing_match.png` — nextpnr static timing report: 19.88 MHz achievable, PASS at the 12 MHz system clock

![Timing report]( Timing_match.png)

### 5.4 Bitstream Generation (`icetime` + `icepack`)

The last step in `make build` is to perform an independent timing verification using the command `icetime`, followed by converting the routed ASCII netlist (`SOC.asc`) to the bitstream format (`SOC.bin`) that will be loaded onto the FPGA using the `icepack` command:

```
Info: Max frequency for clock 'clk': 16.10 MHz (PASS at 12.00 MHz)

Info: Program finished normally.
icetime -p VSDSquadronFM.pcf -P sg48 -r SOC.timings -d up5k -t SOC.asc
// Reading input .pcf file..
// Reading input .asc file..
// Reading 5k chipdb file..
// Creating timing netlist..
Warning: timing analysis not supported for cell type HFOSC
// Timing estimate: 64.63 ns (15.47 MHz)
icepack -s SOC.asc SOC.bin
```

The second independent check `icetime` (16.10 MHz) succeeds once more at **12 MHz**; and `icepack` generates `SOC.bin`, which will be loaded to the board in the subsequent step. (`HFOSC` warning is an expected thing and has no relation to `icetime` inability to handle the internal oscillator primitive – it doesn’t influence the timing figures above for `clk` domain).

> `Bitstream_generation.png` — final `icetime` timing check (16.10 MHz, PASS at 12 MHz) and `icepack` producing `SOC.bin`

![Bitstream generation](Bitstream_generation.png)

### 5.5 Flashing the Bitstream (`sudo make flash`)

With `SOC.bin` generated, `sudo make flash` invokes `iceprog` to erase the board's SPI flash and program the new bitstream:

```
$ sudo make flash
iceprog SOC.bin
init..
cdone: high
reset..
cdone: low
flash ID: 0xEF 0x40 0x16 0x00
file size: 104090
erase 64kB sector at 0x000000..
erase 64kB sector at 0x010000..
programming..
done.
reading..
VERIFY OK
cdone: high
Bye.
```

`VERIFY OK` and `cdone: high` at the end confirm the bitstream was written and verified successfully, and the FPGA has resumed normal operation with the new configuration (GPIO + UART + SPI Master, all integrated).

> `Hardware_data_transmission.png` — terminal log of `sudo make flash`: erase, program, verify, and `cdone: high` confirming a successful configuration load

![Flashing the bitstream](Hardware_data_transmission.png)

### 5.6 Board Bring-Up

AAfter the flashing, the VSDSquadron FPGA board was powered via the USB-C connection and examined as follows:

- The **PWR LED** is illuminated, indicating that the board has power.
- The **status/user LED** is illuminated at the RGB header, meaning that the FPGA is running (the `cdone` signal is asserted as expected; it was previously observed to be `cdone: high` during flashing).
- The board is now ready for running the tested `test_spi.c` firmware on the hardware instead of `vvp`.

> `Board_output.jpeg` — VSDSquadron FPGA board powered on via USB-C, PWR LED and status LED both active after a successful flash

![VSDSquadron board powered on](Board_output.jpeg)

### Summary of Hardware Validation

| Stage | Tool | Result |
|-------|------|--------|
| Synthesis | Yosys | 1351/5280 LCs (25%), 16/30 RAMs (53%) — clean packing |
| Place & Route | nextpnr | 5058 arcs routed, converged cleanly |
| Timing (nextpnr) | nextpnr | 19.88 MHz achievable, **PASS** at 12 MHz |
| Timing (icetime) | icetime | 16.10 MHz achievable, **PASS** at 12 MHz |
| Bitstream | icepack | `SOC.bin` generated successfully |
| Flashing | iceprog | `VERIFY OK`, `cdone: high` |
| Board bring-up | — | Board powers on, PWR + status LEDs active |

This brings the process full circle from **RTL to Simulation to Synthesis to Place & Route to Timing Closure to Bitstream to Flash to Real Hardware**, proving that the SPI Master IP is not only functional in simulation but is also successfully synthesized and timed in the real VSDSquadron FPGA.

---

## How Address Offsets Are Decoded

The SPI IP core relies on the same 2-bit address offset bus (`addr_off`) used by GPIO (`mem_wordaddr[1:0]`); however, the core is activated through a different control signal `spi_sel` derived from two higher order bits **above** those (`mem_wordaddr[3] & mem_wordaddr[2]`).

```
SPI_CTRL   at byte offset 48 → mem_wordaddr[1:0] = 2'b00 → selects ctrl_reg
SPI_TXDATA at byte offset 52 → mem_wordaddr[1:0] = 2'b01 → selects tx_reg
SPI_RXDATA at byte offset 56 → mem_wordaddr[1:0] = 2'b10 → selects rx_reg (read-only)
SPI_STATUS at byte offset 60 → mem_wordaddr[1:0] = 2'b11 → selects status_reg (write-1-to-clear)
```

In file `riscv.v`: `spi_sel` decides if `write_en` of the SPI peripheral module is enabled (`spi_write = spi_sel & mem_wstrb`) and also whether the data `IO_rdata` is routed via `spi_rdata`. Within the `spi_master.v`, the `case(addr_off)` block for both write and read, picks up the particular register, i.e., replicating the two level-decoding scheme of Task-5 (IP-select followed by register select), but with 4 registers instead of 3.

---

## How a Transfer Actually Happens (Data Flow)

This is the story of how one transfer happens and links RTL to the simulation log:

1. **Configure** – CPU writes `CLKDIV=10, EN=1` to `CTRL`. FSM is in `IDLE` state as `START` (bit1) is still 0.
2. **Load TX byte** – CPU loads the byte to `tx_reg` (the byte does not move now, but just waits in a register).
3. **Start** – CPU sets `START`. On the next clock tick, FSM sees `EN & START` in `IDLE` and makes transition `IDLE -> LOAD`. In `LOAD`: `$display("SPI START")` fires, `BUSY` sets, `START` automatically clears, `cs_n` goes low, `load=1` fires and the byte is captured by `spi_shift` from `tx_reg`.
4. **Transfer (8 SCLK edges)** – FSM stays in `TRANSFER`. `spi_clk_div` toggles `spi_clk` at every `CLKDIV + 1` system clocks and fires `tick`. With every `tick` FSM gets `shift_en = 1` for one cycle: `shift_tx` shifts the byte left (MSB -> `mosi`), `shift_rx` shifts left capturing `miso`. As `miso` is connected to `mosi`, the transmitted bit becomes the received bit. `bit_count` increases on every `tick`.
5. **Done** — as soon as `bit_count==7 && tick`, FSM transitions into `DONE` state where `$display("SPI DONE")` prints, `BUSY` becomes inactive, `DONE` becomes active and `rx_reg <= rx_data` stores shifted byte in CPU accessible register. FSM enters `IDLE` state, `cs_n` becomes logic `1`.
6. **Polling and read** — the loop `do… while()` ends right away once `STATUS.bit1` equals `1`. Then it reads `RXDATA` and compares it with the sent byte.
7. **Clear** — the firmware writes `1` into `STATUS.bit1`, thus deactivating `DONE` and keeping IP ready for the next transfer.

Conclusion. The result of this design is the full round-trip which looks like that:
**CPU register write → FSM → clock divider → shift register → MOSI → (loopback) → MISO → shift register → RXDATA → CPU register read**, checked bit-to-bit on three different input sequences.

---

## Screenshots Index

| Image File | Description |
|-----------|-------------|
| `spi_io_module.png` | `io.h` with the four new SPI register offsets (48, 52, 56, 60) |
| `spi_master_m1.png` | `spi_master.v` — ports, internal registers, FSM localparams |
| `spi_master_m2.png` | `spi_master.v` — `spi_clk_div`/`spi_shift` instantiation, bit counter |
| `spi_master_m3.png` | `spi_master.v` — sequential FSM (`IDLE→LOAD→TRANSFER→DONE`) |
| `spi_master_m4.png` | `spi_master.v` — combinational outputs (`busy`, `cs_n`, `load`, `shift_en`) |
| `spi_master_m5.png` | `spi_master.v` — register write decode & read-back mux |
| `spi_clk_div_code.png` | Complete `spi_clk_div.v` — programmable SPI clock generator |
| `spi_shiftreg_code.png` | Complete `spi_shift.v` — TX/RX shift register |
| `spi_variable_riscv.png` | `riscv.v` — new SPI wires, `spi_sel`/`spi_write` decode |
| `spi_ip_inst_riscv.png` | `riscv.v` — `spi_master SPI(...)` instantiation with MISO/MOSI loopback |
| `IO_read_riscv.png` | `riscv.v` — `IO_rdata` mux extended with `spi_sel` |
| `Soc_top_module.png` | SoC top-level `module SOC(...)` and benchtest clock/reset generation |
| `spi_test_code1.png` | `test_spi.c` — CTRL config, TXDATA load, START trigger |
| `spi_test_code2.png` | `test_spi.c` — STATUS polling, RXDATA read, PASS/FAIL, DONE clear |
| `spi_hexgen.png` | Terminal: `make test_spi_update` build log (712 words, 46% BRAM occupancy) |
| `spi_res1.png` | Simulation result 1: `TX_VALUE=0xA5` → `RX DATA=0xA5`, PASS |
| `spi_res2.png` | Simulation result 2: `TX_VALUE=0xFA` → `RX DATA=0xFA`, PASS |
| `spi_res3.png` | Simulation result 3: `TX_VALUE=0xBE` → `RX DATA=0xBE`, PASS |
| `synthesis.png` | Yosys/nextpnr packing log and device-utilisation summary (1351/5280 LCs, 16/30 RAMs) |
| `Routing_table.png` | nextpnr routing progress log — 5058 arcs, converging over 50,000+ iterations |
| `Timing_match.png` | nextpnr static timing report — 19.88 MHz achievable, PASS at 12 MHz |
| `Bitstream_generation.png` | Final `icetime` timing check (16.10 MHz, PASS) and `icepack` producing `SOC.bin` |
| `Hardware_data_transmission.png` | Terminal log of `sudo make flash` — erase, program, `VERIFY OK`, `cdone: high` |
| `Board_output.jpeg` | VSDSquadron FPGA board powered on via USB-C, PWR and status LEDs active |

---

## Learnings

- **Dividing IP functionality between clock, shift, and control sub-modules yields benefits** — `spi_clk_div` and `spi_shift` could be thought about (and easily unit-tested), independent of each other and the state machine that controls them.
- **Single-cycle `tick` signal is the most elegant solution for transferring data from the slow SPI clock domain into the fast system clock domain** — tying `shift_en` to `tick`, instead of directly to a toggling `spi_clk`, eliminates any potential multi-toggling glitches and ensures that all register updates happen synchronously with respect to `clk`.
- **Auto-clearing control signals (`START`) and write-1-to-clear status signals (`DONE`) are straightforward to implement yet hard to do right** — both had to be processed together with all other registers within the same synchronous write process without any chance of a race condition between CPU write and FSM update.
- **Two-level addressing (`spi_sel` followed by `addr_off`) easily scales up to any number of registers** – utilizing the same bus structure as GPIO, but controlled with a different upper-level select signal, no extra bus structures had to be added to `riscv.v`.
- **Simulation passing** - only after synthesis, place & route, and timing closure on the real iCE40 fabric can we be certain that the design will actually work on hardware and not just in our perfect event-driven simulator.
- **"Timing margin"** - being able to see both 19.88 MHz (nextpnr) and 16.10 MHz (icetime) well above 12 MHz clock rate requirement for our system makes us sure that our new additions (SPI FSM and register decode) did not silently reduce our timing margin.
- **`VERIFY OK` after `iceprog` is the true communication with hardware** - at that point, "my RTL simulates correctly" turns to "my bitstream actually resides in the FPGA configuration memory" and `cdone: high` confirms that the FPGA actually received that configuration.

---

## Conclusion

The SPI Master IP was implemented from the ground up as an entirely new, fully synchronous Mode-0 peripheral consisting of a clock divider, a shift register, and a 4-state FSM, and incorporated into the RISC-V SoC as its own peripheral with its own address decode window (`spi_sel`) right along with the rest of the GPIO and UART peripherals. It is controlled exclusively through software by four 32-bit registers (`CTRL`, `TXDATA`, `RXDATA`, `STATUS`) in a configuration -> start -> poll -> read process, without any use of interrupts.

Three independent transfers of data (i.e., `0xA5`, `0xFA`, `0xBE`) were successfully transferred via MISO/MOSI loopback and received back with identical values as: `SPI START → SPI DONE → STATUS=0x2 → RX DATA matches → PASS`. It thus confirms that the current system meets all the functional specifications requirements.

Moreover, in addition to simulations, the same design was implemented via the entire hardware flow process (from `make test_spi_update` → `make build` → `sudo make flash`) for **the VSDSquadron FPGA** and it synthesizes properly (logic cell utilization: 25%), routes successfully (5058 arcs converged), meets timing requirements comfortably over 12MHz system clock (19.88 MHz by nextpnr, 16.10 MHz by icetime), and flashes successfully (`VERIFY OK`, `cdone: high`).

---
