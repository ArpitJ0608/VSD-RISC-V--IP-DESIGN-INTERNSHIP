# SPI Master IP — Example Usage

**File under discussion:** `software/test_spi.c`
**Purpose:** ready-to-run C firmware that initializes the SPI Master IP, transmits one byte, and validates it comes back correctly via loopback.

---

## Table of Contents

1. [Overview](#overview)
2. [Step-by-Step Explanation](#step-by-step-explanation)
   - [Initialization](#initialization)
   - [Transfer](#transfer)
   - [Polling](#polling)
   - [Read & Verification](#read--verification)
   - [PASS Condition](#pass-condition)
3. [Full Source Listing](#full-source-listing)
4. [Flowchart](#flowchart)
5. [Adapting This Example](#adapting-this-example)

---

## Overview

`test_spi.c` demonstrates the complete, minimal software sequence required to drive one SPI transfer through this IP:

```
Configure  →  Load TX byte  →  Start  →  Poll DONE  →  Read RX byte  →  Compare  →  Clear DONE
```

It runs on the VSDSquadron RISC-V system and prints its progress and result over UART.

> `spi_test_code1.png` — setup half of `test_spi.c` (CTRL config, TXDATA load, START trigger)
> `spi_test_code2.png` — completion half of `test_spi.c` (STATUS polling, RXDATA read, PASS/FAIL, DONE clear)

![test_spi.c part 1](..Task-6/spi_test_code1.png)
![test_spi.c part 2](..Task-6/spi_test_code2.png)

---

## Step-by-Step Explanation

### Initialization

```c
uint32_t ctrl = (10 << 8) | (1 << 0);
// CLKDIV = 10, EN = 1
IO_OUT(IO_SPI_CTRL, ctrl);
```

This sets the clock divider to `10` (SCLK toggles every 11 system-clock cycles) and enables the SPI block (`EN = 1`). `START` (bit 1) is deliberately **not** set yet.

```c
IO_OUT(IO_SPI_TXDATA, TX_VALUE);
```

The byte to be transmitted (`TX_VALUE`, e.g. `0xBE`) is loaded into `TXDATA` before starting the transfer.

### Transfer

```c
ctrl |= (1 << 1);          // set START
IO_OUT(IO_SPI_CTRL, ctrl);
```

If bit 1 is set in the *same* `ctrl` variable (whose `EN` and `CLKDIV` values are still valid from previous iterations) and written back, the FSM will be triggered: Both `EN & START` become `1`, resulting in the IP being moved through `IDLE → LOAD → TRANSFER`.

### Polling

```c
do {
    status = IO_IN(IO_SPI_STATUS);
} while ((status & 0x2) == 0);
```

This polling loop for the `STATUS` is performed continuously until the FSM transitions to the `DONE` state and bit 1 is set; no time interval or number of iterations is considered as it is dependent on the value of the `CLKDIV`.

### Read & Verification

```c
rx = IO_IN(IO_SPI_RXDATA);

if ((rx & 0xFF) == TX_VALUE) {
    printf("PASS\n");
} else {
    printf("FAIL\n");
}
```

The received byte is read back and compared against the byte that was transmitted. Because this reference setup uses a **loopback connection** (`MISO` tied to `MOSI` at the SoC level), a correct implementation will always receive exactly what it sent.

### PASS Condition

`The condition `PASS` will print if, and only if, `RXDATA == TXDATA` is true after the completion of a transfer. The above condition is the sole and only success criteria in this example – no additional SPI slave or any other testing device is required.

Last but not the least, the done bit is cleared by the firmware so that IP can perform another transfer.

```c
IO_OUT(IO_SPI_STATUS, 0x2);   // clear DONE
```

---

## Full Source Listing

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

---

## Flowchart

```
        +-------------------------+
        |   Print test banner     |
        +-------------------------+
                     |
                     v
        +-------------------------+
        | Write CTRL: EN=1,       |
        | CLKDIV=10               |
        +-------------------------+
                     |
                     v
        +-------------------------+
        | Write TXDATA = 0xBE     |
        +-------------------------+
                     |
                     v
        +-------------------------+
        | Set START, write CTRL   |
        +-------------------------+
                     |
                     v
        +-------------------------+
        |  Poll STATUS.DONE       |<---+
        +-------------------------+    |
                     |                 |
             DONE==0 |                 |
                     +-----------------+
                     | DONE==1
                     v
        +-------------------------+
        |  Read RXDATA            |
        +-------------------------+
                     |
                     v
        +-------------------------+
        | RXDATA == TXDATA ?      |
        +-------------------------+
              /            \
          yes/              \no
            v                v
      +-----------+    +-----------+
      |  PASS     |    |  FAIL     |
      +-----------+    +-----------+
              \            /
               v          v
        +-------------------------+
        | Clear DONE (write 0x2)  |
        +-------------------------+
                     |
                     v
        +-------------------------+
        |     Halt (while(1))     |
        +-------------------------+
```

---

## Adapting This Example

For using this code with a **true SPI slave module** (as opposed to the internal simulation loopback):

1. Make sure that `.miso(...)` in `spi_master` is connected to a proper board pin, not a `mosi` (see [Integration_Guide.md](Integration_Guide.md)).
2. Select a `CLKDIV` suitable for your slave device's maximum SPI clock rate.
3. Substitute `TX_VALUE` and the `PASS`/`FAIL` condition with an expected reply from your slave (such as reading a device ID register), as a true slave would not just return a transmitted byte back.
4. The `Configure → Load → Start → Poll → Read → Clear` routine remains the same – it is necessary regardless of the device you connect.
