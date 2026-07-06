# SPI Master IP — Register Map

**Base address:** `IO_BASE = 0x400000` (shared with GPIO/UART peripherals on this SoC)

---

## Table of Contents

1. [Register Summary](#register-summary)
2. [CTRL Register (0x30 / offset 48)](#ctrl-register-0x30--offset-48)
3. [TXDATA Register (0x34 / offset 52)](#txdata-register-0x34--offset-52)
4. [RXDATA Register (0x38 / offset 56)](#rxdata-register-0x38--offset-56)
5. [STATUS Register (0x3C / offset 60)](#status-register-0x3c--offset-60)
6. [Word-Address Decoding](#word-address-decoding)
7. [Programming Notes](#programming-notes)
8. [Example Register Writes](#example-register-writes)
9. [Example Register Reads](#example-register-reads)

---

## Register Summary

| Register | Byte Offset | Absolute Address | Access | Reset Value | Description |
|---|---|---|---|---|---|
| `SPI_CTRL`   | 48 (`0x30`) | `0x400030` | R/W | `0x0000_0000` | Enable, Start, Clock Divider |
| `SPI_TXDATA` | 52 (`0x34`) | `0x400034` | R/W | `0x0000_0000` | Byte to transmit data |
| `SPI_RXDATA` | 56 (`0x38`) | `0x400038` | R   | `0x0000_0000` | Last byte received |
| `SPI_STATUS` | 60 (`0x3C`) | `0x40003C` | R/W | `0x0000_0000` | Busy / Done flags status |

All registers are 32 bits wide, word-aligned, and accessed as 32-bit CPU loads/stores, consistent with the rest of the SoC's peripheral bus convention.

---

## CTRL Register (0x30 / offset 48)

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 0 | `EN` | R/W | 0 | Enables SPI peripheral. Together with `START`, needs to be `1` for transfer to occur. |
| 1 | `START` | R/W (auto-clear) | 0 | Setting bit to `1` starts the transfer, which is then auto-cleared by hardware on entering `LOAD` phase. |
| 7:2 | Reserved | — | 0 | Reserved; write `0`. |
| 15:8 | `CLKDIV` | R/W | 0 | SPI clock divider, which means that the SCLK is toggled every `(CLKDIV + 1)` system clock ticks. |
| 31:16 | Reserved | — | 0 | Reserved; write `0`. |

```
 31            16 15         8 7        2  1      0
+----------------+-----------+----------+------+----+
|   Reserved     |  CLKDIV   | Reserved |START | EN |
+----------------+-----------+----------+------+----+
```

**Read behavior:** provides the present value of `ctrl_reg`, with `START` included (and that will return to `0` almost immediately after setting it due to hardware auto-clearing).

**Write behavior:** a full 32-bit write overwrites the complete register (`ctrl_reg <= w_data`). It is up to the software to combine `EN`, `START`, and `CLKDIV` into one write operation.

---

## TXDATA Register (0x34 / offset 52)

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 7:0 | `TXDATA` | R/W | 0 | Byte to be transmitted on the next transfer. |
| 31:8 | Reserved | — | 0 | Always reads as 0. |

**Read operation:** yields `{24'b0, tx_reg}` — the most recently written byte.

**Write operation:** captures only the lower 8 bits (`w_data[7:0]`) into `tx_reg`. It is clocked into the shift register once the FSM reaches the `LOAD` state (as soon as `START` becomes active).

> **Note:** make sure to load `TXDATA` **before** activating `START` to capture the proper byte at `LOAD` cycle.
---

## RXDATA Register (0x38 / offset 56)

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 7:0 | `RXDATA` | **R (read-only)** | 0 | Byte received during the last completed transfer. |
| 31:8 | Reserved | — | 0 | Always reads as 0. |

**Read operation:** results in `{24'b0, rx_reg}`. The `rx_reg` value changes only one time, when the FSM moves into the `DONE` state (after having all 8 bits shifted in).

**Write operation:** the register is **read-only**. In fact, it was purposely not included in the case statements for the write decode stage, which means that any write from the CPU to this offset would be ignored.

---

## STATUS Register (0x3C / offset 60)

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 0 | `BUSY` | R | 0 | `1` while a transfer is in progress (`LOAD` or `TRANSFER` state). Read-only from software's perspective. |
| 1 | `DONE` | R/W1C | 0 | `1` when a transfer has completed. **Write `1` to clear.** |
| 31:2 | Reserved | — | 0 | Always reads as 0. |

```
 31                        2   1      0
+---------------------------+------+-----+
|         Reserved          | DONE | BUSY|
+---------------------------+------+-----+
```

**Read operation:** results in `{30'b0, status_reg[1], status_reg[0]}`.

**Write operation:** Only the second bit (`DONE`) can be written to by writing **write-1-to-clear**; `w_data[1] = 1` means `status_reg[1]` is cleared to `0`, and writing `0` to the second bit does nothing. The first bit (`BUSY`) is not writeable
---

## Word-Address Decoding

SPI Block:
The SPI block occupies a 4-word (16-byte) decode window, whose top 2 bits select the internal word address while bottom 2 bits select the register; same as the decode structure used in the GPIO IP but with its own `spi_sel` signal at the top level.

```
Byte offset 48 → word address 12 → mem_wordaddr[1:0] = 2'b00 → SPI_CTRL
Byte offset 52 → word address 13 → mem_wordaddr[1:0] = 2'b01 → SPI_TXDATA
Byte offset 56 → word address 14 → mem_wordaddr[1:0] = 2'b10 → SPI_RXDATA
Byte offset 60 → word address 15 → mem_wordaddr[1:0] = 2'b11 → SPI_STATUS
```

`spi_sel = isIO & mem_wordaddr[3] & mem_wordaddr[2]` gates whether this IP is being addressed at all; `addr_off = mem_wordaddr[1:0]` then picks the specific register inside it. See [`Integration_Guide.md`](Integration_Guide.md) for the full decode logic.

---

## Programming Notes

- Write `CTRL` with **both** `EN` and `CLKDIV` set **before or along with** `START`, because the FSM exits the `IDLE` state only when it sees both `EN & START` high within the same cycle.
- Write `TXDATA` before or at the same time that you write `START`, as the shifter grabs it during the `LOAD` cycle right after.
- Loop checking `STATUS` until you find it; you cannot hardcode any cycle count for the data transfer completion, as the ratio between CPU and SPI clocks is programmable through `CLKDIV`.
- Don’t forget to clear the `DONE` status bit by writing `0x2` to `STATUS` once you read `RXDATA`.
---

## Example Register Writes

```c
// Configure: CLKDIV = 10, EN = 1
uint32_t ctrl = (10 << 8) | (1 << 0);
IO_OUT(IO_SPI_CTRL, ctrl);

// Load the byte to transmit
IO_OUT(IO_SPI_TXDATA, 0xBE);

// Trigger the transfer (set START, bit 1)
ctrl |= (1 << 1);
IO_OUT(IO_SPI_CTRL, ctrl);

// Clear DONE after reading RXDATA
IO_OUT(IO_SPI_STATUS, 0x2);
```

## Example Register Reads

```c
// Poll until DONE (bit 1) is set
uint32_t status;
do {
    status = IO_IN(IO_SPI_STATUS);
} while ((status & 0x2) == 0);

// Read the received byte
uint32_t rx = IO_IN(IO_SPI_RXDATA);
```
