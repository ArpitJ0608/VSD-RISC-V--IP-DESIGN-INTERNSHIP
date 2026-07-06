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
