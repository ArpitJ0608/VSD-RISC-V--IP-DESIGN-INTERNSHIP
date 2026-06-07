# RISC-V Lab – Task 2: SPIKE Simulation & Factorial Program Example

> **Task 2** – SPIKE Simulation · Observation with `-O1` and `-Ofast` · Factorial C Program Example · Debugger Walkthrough
---

## Table of Contents

1. [Task Overview](#task-overview)
2. [Tools & Environment](#tools--environment)
3. [Part A – Sum 1 to N (With SPIKE)](#part-a--sum-1-to-n-with-spike)
   - [Source Code](#part-a-source-code)
   - [GCC Compilation & Result](#part-a-gcc-complation--result)
   - [RISC-V Compilation & Commands](#part-a-risc-v-compilation-commands)
   - [SPIKE Simulation – Run](#part-a-spike-simulation--run)
   - [Objdump `-O1`](#part-a-objdump--o1)
   - [Objdump `-Ofast`](#part-a-objdump--ofast)
   - [SPIKE Debugger ](#part-a-spike-debugger)
4. [Part B – Factorial Program (Custom Application)](#part-b--factorial-program-custom-application)
   - [Source Code](#part-b-source-code)
   - [GCC Compilation & Result](#part-b-gcc-complation--result)
   - [RISC-V Compilation Commands](#part-b-risc-v-compilation-commands)
   - [SPIKE Simulation – Run](#part-b-spike-simulation--run)
   - [Objdump `-O1`](#part-b-objdump--o1)
   - [Objdump `-Ofast`](#part-b-objdump--ofast)
   - [SPIKE Debugger ](#part-b-spike-debugger)
5. [Comparison Table](#Comparison-table)
6. [Screenshots Index](#screenshots-index)
7. [Learnings](#learnings)
8. [Conclusion](#conclusion)

---

## Task Overview

This task is the extended version of Task 1 with the following important additions:

1. **SPIKE simulation** of RISC-V ELF binaries in the Spike ISA simulator with the help of proxy kernel ("pk"), ensuring that cross-compiled binaries work as expected and generate the same output as the native GCC
2. **Development of Custom C program (Factorial)** by writing `nfact.c` and computing the factorial of N by using gcc and spike, cross-compiling using `-O1` and `-Ofast`, viewing assembly by using `objdump`, and debugging the process with spike interactive debugger (`spike -d`)

Steps followed by both `sum1ton.c` and `nfact.c` are:

```
C Code Write → gcc → riscv-gcc (-O1 / -Ofast) → objdump → spike pk → spike -d
```

---

## Tools & Environment

| Tool | Description |
|------|-------------|
| `gedit` | GUI text editor used for editing C source code and text files |
| `gcc` | Host GCC Compiler (x86) for preliminary verification |
| `riscv64-unknown-elf-gcc` | RISC-V 64-bit Cross Compiler |
| `riscv64-unknown-elf-objdump` | RISC-V Disassembler used for viewing assembly instructions |
| `spike pk` | Spike RISC-V Instruction Set Architecture Simulator with Proxy Kernel – runs RISC-V ELF binaries |
| `spike -d pk` | Spike in **Debug Mode** (single step, register inspection, memory dump) |
| `less` | Page viewer used for compacting `objdump` outputs |

**Working Directory:** `/workspaces/vsd-riscv2/samples`

---

## Part A – Sum 1 to N (With SPIKE)

### Part A: Source Code

```c
#include <stdio.h>

int main(){
    int i, sum=0, n=100;
    for(i=1;i<=n;i++)
        sum = sum + i;
    printf("Sum from 1 to %d is %d \n", n, sum);
    return 0;
}
```

> `sum-1ton_c-code.png` – Source code 

![Sum Source Code](sum-1ton_c-code.png)

---

### Part A: GCC Compilation & Result

```bash
gcc sum1ton.c
./a.out
```

**Output:** `Sum from 1 to 100 is 5050`

> `result-1_sum.png` – GCC compile and run output, output is sum from 1 to 100 is 5050

![Sum GCC Result](result-1_sum.png)

---

### Part A: RISC-V Compilation Commands

```bash
# Compile with -O1
riscv64-unknown-elf-gcc -O1 -mabi=lp64 -march=rv64i -o sum1ton.o sum1ton.c

# Compile with -Ofast
riscv64-unknown-elf-gcc -Ofast -mabi=lp64 -march=rv64i -o sum1ton.o sum1ton.c
```

> `objdump_sum_o1_cmd.png` – Terminal showing RISC-V compile + objdump command for `-O1`

![Sum O1 Command](objdump_sum_o1_cmd.png)

> `objdump_sum_ofast_cmd.png` – Terminal showing RISC-V compile + objdump command for `-Ofast`

![Sum Ofast Command](objdump_sum_ofast_cmd.png)

---

### Part A: SPIKE Simulation – Run

```bash
# Run the RISC-V binary using Spike + proxy kernel
spike pk sum1ton.o
```

|Command| Description|
|------|------------|
|`spike`| SPIKE is a simulator for RISC-V instructions set architecture(RISCV) that provides hardware support for RV64I|
|`pk`| The proxy kernel is an OS wrapper that takes care of system calls such as `printf` and hence helps in running the elf binary|
|`sum1ton.o`| The RISCV ELF Binary that is being simulated|
**Output:** `bbl loader` then `Sum from 1 to 100 is 5050` (matches GCC output exactly)

> `riscv_result-n100_spike.png` – Spike simulation output: Sum from 1 to 100 is 5050

![Sum Spike n100](riscv_result-n100_spike.png)

> `riscv_result-n50_spike.png` – Spike simulation output: Sum from 1 to 50 is 1275

![Sum Spike n50](riscv_result-n50_spike.png)

---

### Part A: Objdump `-O1`

```bash
riscv64-unknown-elf-objdump -d sum1ton.o | less
```

#### Instruction Count Calculation (`sum1ton` `-O1`)

From the objdump screenshot:

```
<main>   starts at : 0x10184
<atexit> starts at : 0x101c0   ← first instruction of next function

Bytes  = 0x101c0 − 0x10184 = 0x3c = 60 decimal
Count  = 60 ÷ 4 = 15 instructions
```

> **`sum1ton` with `-O1` uses 15 instructions in `main`**

#### Instruction-by-Instruction Walkthrough

| Address | Hex | Instruction | Explanation |
|---------|-----|-------------|-------------|
| `10184` | `ff010113` | `addi sp,sp,-16` | Allocate 16-byte stack frame |
| `10188` | `00113423` | `sd ra,8(sp)` | Save return address onto stack |
| `1018c` | `06400793` | `li a5,100` | Load loop counter: `a5 = 100` (value of `n`) |
| `10190` | `fff7879b` | `addiw a5,a5,-1` | Decrement loop counter by 1 (32-bit) |
| `10194` | `fe079ee3` | `bnez a5,10190` | Loop back if `a5 ≠ 0` — this is the counting loop |
| `10198` | `00001637` | `lui a2,0x1` | Load upper bits of sum into `a2` |
| `1019c` | `3ba60613` | `addi a2,a2,954` | Complete sum: `0x1000 + 954 = 0x13ba = 5050` loaded into `a2` |
| `101a0` | `06400593` | `li a1,100` | Load `n=100` into `a1` (printf 2nd arg) |
| `101a4` | `00021537` | `lui a0,0x21` | Load upper bits of format string address |
| `101a8` | `19050513` | `addi a0,a0,400` | Complete format string address in `a0` |
| `101ac` | `26c000ef` | `jal ra,10418 <printf>` | Call printf |
| `101b0` | `00000513` | `li a0,0` | Load return value 0 |
| `101b4` | `00813083` | `ld ra,8(sp)` | Restore return address from stack |
| `101b8` | `01010113` | `addi sp,sp,16` | Deallocate stack frame |
| `101bc` | `00008067` | `ret` | Return to caller |

> `objdump_sum_o1.png` – Full objdump of sum1ton compiled with `-O1`

![Sum O1 Objdump](objdump_sum_o1.png)

---

### Part A: Objdump `-Ofast`

#### Instruction Count Calculation (`sum1ton` `-Ofast`)

```
<main>            starts at : 0x100b0
<register_fini>   starts at : 0x100e0

Bytes  = 0x100e0 − 0x100b0 = 0x30 = 48 decimal
Count  = 48 ÷ 4 = 12 instructions
```

> **`sum1ton` with `-Ofast` uses 12 instructions in `main`**

#### Instruction-by-Instruction Walkthrough

| Address | Hex | Instruction | Explanation |
|---------|-----|-------------|-------------|
| `100b0` | `00001637` | `lui a2,0x1` | Load upper bits for sum constant |
| `100b4` | `00021537` | `lui a0,0x21` | Load upper bits for format string address |
| `100b8` | `ff010113` | `addi sp,sp,-16` | Allocate stack frame |
| `100bc` | `3ba60613` | `addi a2,a2,954` | Complete sum `5050 = 0x13ba` in `a2` — **entire loop eliminated** |
| `100c0` | `06400593` | `li a1,100` | Load `n=100` into `a1` |
| `100c4` | `18050513` | `addi a0,a0,384` | Complete format string address |
| `100c8` | `00113423` | `sd ra,8(sp)` | Save return address|
| `100cc` | `340000ef` | `jal ra,1040c <printf>` | Call printf |
| `100d0` | `00813083` | `ld ra,8(sp)` | Restore return address |
| `100d4` | `00000513` | `li a0,0` | Load return value 0 |
| `100d8` | `01010113` | `addi sp,sp,16` | Deallocate stack frame |
| `100dc` | `00008067` | `ret` | Return to caller |

> `objdump_sum_ofast.png` – Full objdump of sum1ton compiled with `-Ofast`

![Sum Ofast Objdump](objdump_sum_ofast.png)

---

### Part A: SPIKE Debugger Walkthrough

```bash
spike -d pk sum1ton.o
(spike) until pc 0 10184     # Auto run till 10184 to start of main
(spike) reg 0 sp             # Inspect stack pointer register
(spike) [Enter]              # Run next instruction
(spike) reg 0 a5             # inspect a5 after li a5,100
```

| Debugger Command | Description |
|------------------|-------------|
| `spike -d pk sum1ton.o` | Load Spike in interactive debugging mode |
| `until pc 0 10184` | Silent Auto-Run until program counter of core 0 is at address `0x10184` (start of `main`) |
| `reg 0 sp` | Get value of register `sp` for core 0 |
| `reg 0 a5` | Get value of register `a5` for core 0 |
| `mem 0 7f7e9b48` | Get value of memory cell at address `0x7f7e9b48` for core 0 |
| `[Enter]` | Step over: run single instruction and move to next |

**Debugger findings:**
- `after addi sp,sp,-16`: register `sp` gets changed from `0x7f7e9b50` → `0x7f7e9b40` (value is decremented by 16)
- `after li a5,100`: value of register `a5 = 0x0000000000000064` (decimal 100)
- `after addiw a5,a5,-1`: value of register `a5 =
> `debugger_o1.png` – Spike `-d` debugger stepping through sum1ton `-O1`

![Sum Debugger O1](debugger_o1.png)

> `debugger_ofast.png` – Spike `-d` debugger stepping through sum1ton `-Ofast`

![Sum Debugger Ofast](debugger_ofast.png)

---

## Part B – Factorial Program (Custom Application)

### Part B: Source Code

The problem `nfact.c` computes the factorial of N using a countdown for loop.

```c
#include <stdio.h>

int main(){
    int n=5, i;
    int fact = 1;

    for(i=n; i>0; i--)
    {
        fact = fact*i;
    }
    printf("The factorial of %d is %d\n", n, fact);
}
```

**How it works:** Starting `i = n`, the loop multiplies `fact` by `i` and decrements `i` until `i = 0`. This computes `n! = n × (n-1) × ... × 1`.

**Expected results:**
- `n=5` → `5! = 120`
- `n=10` → `10! = 3628800`

> `c-code_fact.png` – `nfact.c` source code open in gedit editor

![Factorial Source Code](c-code_fact.png)

---

### Part B: GCC Compilation & Result

```bash
gedit nfact.c          # open in editor
gcc nfact.c            # compile with host GCC
./a.out                # run
```

**Output:** `The factorial of 5 is 120` ✅

> `result_gcc_n5_fact.png` – Host GCC compile and run: The factorial of 5 is 120

![Factorial GCC Result](result_gcc_n5_fact.png)

---

### Part B: RISC-V Compilation Commands

```bash
# Compile with -O1
riscv64-unknown-elf-gcc -O1 -mabi=lp64 -march=rv64i -o nfact.o nfact.c

# Then objdump
riscv64-unknown-elf-objdump -d nfact.o |less
```

```bash
# Compile with -Ofast
riscv64-unknown-elf-gcc -Ofast -mabi=lp64 -march=rv64i -o nfact.o nfact.c

# Then objdump
riscv64-unknown-elf-objdump -d nfact.o |less
```

> `objdump_fact_o1_cmd.png` – Terminal showing RISC-V compile + objdump command for factorial `-O1`

![Factorial O1 Command](objdump_fact_o1_cmd.png)

> `objdump_fact_ofast_cmd.png` – Terminal showing RISC-V compile + objdump command for factorial `-Ofast`

![Factorial Ofast Command](objdump_fact_ofast_cmd.png)

---

### Part B: SPIKE Simulation – Run

```bash
spike pk nfact.o
```

**Results verified on SPIKE:**

| n | Expected | SPIKE Output |
|---|----------|--------------|
| 5 | 120 | `The factorial of 5 is 120`  |
| 10 | 3628800 | `The factorial of 10 is 3628800` |

> `riscv_result-n5_fact_spike.png` – Spike run for factorial n=5: output 120

![Factorial Spike n5](riscv_result-n5_fact_spike.png)

> `riscv_result-n10_fact_spike.png` – Spike run for factorial n=10: output 3628800

![Factorial Spike n10](riscv_result-n10_fact_spike.png)

---

### Part B: Objdump `-O1`

```bash
riscv64-unknown-elf-gcc -O1 -mabi=lp64 -march=rv64i -o nfact.o nfact.c
riscv64-unknown-elf-objdump -d nfact.o | less
```

#### Instruction Count Calculation (`nfact` `-O1`)

From the objdump screenshot:

```
<main>   starts at : 0x10184
<atexit> starts at : 0x101b0   ← first instruction of next function

Bytes  = 0x101b0 − 0x10184 = 0x2c = 44 decimal
Count  = 44 ÷ 4 = 11 instructions
```

> **`nfact` with `-O1` uses 11 instructions in `main`**

#### Instruction-by-Instruction Walkthrough

| Address | Hex | Instruction | Explanation |
|---------|-----|-------------|-------------|
| `10184` | `ff010113` | `addi sp,sp,-16` | Allocate 16-byte stack frame |
| `10188` | `00113423` | `sd ra,8(sp)` | Save return address onto the stack |
| `1018c` | `07800613` | `li a2,120` | Load **pre-computed factorial result** `120` into `a2` — compiler folded `5!` at compile time! |
| `10190` | `00500593` | `li a1,5` | Load `n=5` into `a1` (printf 2nd arg) |
| `10194` | `00021537` | `lui a0,0x21` | Load upper 20 bits of format string address |
| `10198` | `18050513` | `addi a0,a0,384` | Complete format string address → `a0 = 0x21180` |
| `1019c` | `26c000ef` | `jal ra,10408 <printf>` | Call printf |
| `101a0` | `00000513` | `li a0,0` | Load return value 0 |
| `101a4` | `00813083` | `ld ra,8(sp)` | Restore return address from stack |
| `101a8` | `01010113` | `addi sp,sp,16` | Deallocate stack frame |
| `101ac` | `00008067` | `ret` | Return to caller |

**Key insight:** Even at `-O1`, the compiler does **constant folding**. It knows that `n=5` is a compile-time constant and calculates `5!=120` during compilation, thus generating code `li a2,120`. The whole `for` loop disappears even at `-O1`!

> `objdump_fact_o1.png` – Full objdump of nfact compiled with `-O1`

![Factorial O1 Objdump](objdump_fact_o1.png)

---

### Part B: Objdump `-Ofast`

```bash
riscv64-unknown-elf-gcc -Ofast -mabi=lp64 -march=rv64i -o nfact.o nfact.c
riscv64-unknown-elf-objdump -d nfact.o | less
```

#### Instruction Count Calculation (`nfact` `-Ofast`)

From the objdump screenshot:

```
<main>            starts at : 0x100b0
<register_fini>   starts at : 0x100dc   

Bytes  = 0x100dc − 0x100b0 = 0x2c = 44 decimal
Count  = 44 ÷ 4 = 11 instructions
```

> **`nfact` with `-Ofast` uses 11 instructions in `main`**

#### Instruction-by-Instruction Walkthrough

| Address | Hex | Instruction | Explanation |
|---------|-----|-------------|-------------|
| `100b0` | `00021537` | `lui a0,0x21` | Load upper 20 bits of format string address — instruction reordered |
| `100b4` | `ff010113` | `addi sp,sp,-16` | Allocate stack frame |
| `100b8` | `07800613` | `li a2,120` | Load pre-computed `5! = 120` directly (constant folding) |
| `100bc` | `00500593` | `li a1,5` | Load `n=5` into `a1` |
| `100c0` | `18050513` | `addi a0,a0,384` | Complete format string address |
| `100c4` | `00113423` | `sd ra,8(sp)` | Save `ra` — reordered by instruction scheduler |
| `100c8` | `340000ef` | `jal ra,10408 <printf>` | Call printf |
| `100cc` | `00813083` | `ld ra,8(sp)` | Restore return address |
| `100d0` | `00000513` | `li a0,0` | Load return value 0 |
| `100d4` | `01010113` | `addi sp,sp,16` | Deallocate stack frame |
| `100d8` | `00008067` | `ret` | Return to caller |

**The key point is that** `-Ofast` generates **the exact same 11 instructions** as `-O1`, due to the optimization performed by `-O1` using constant folding, which eliminates the loop. The only difference lies in the order of instruction execution**, where `-Ofast` rearranges `lui a0` and `sd ra`.

> `objdump_fact_ofast.png` – Full objdump of nfact compiled with `-Ofast`

![Factorial Ofast Objdump](objdump_fact_ofast.png)

---

### Part B: SPIKE Debugger

```bash
# Debug with -O1 binary (run from start of main)
spike -d pk nfact.o
(spike) until pc 0 10184
(spike) reg 0 sp
(spike)                      # press Enter to step
(spike) reg 0 a2             # should show 0x78 = 120 after li a2,120
(spike) reg 0 a1             # should show 0x5 after li a1,5
(spike) reg 0 a0             # should show 0x21180 after address construction
```

```bash
# Debug with -Ofast binary
spike -d pk nfact.o
(spike) until pc 0 100b0
(spike) reg 0 a0
(spike)
(spike) reg 0 sp
```

**Observed register values in debugger (`-O1`):**

| After Instruction      | Register | Value                   | Meaning                                    |
|-----------------------|----------|-------------------------|-------------------------------------------|
| `addi sp,sp,-16`      | `sp`     | `0x7f7e9b40`           | Stack pointer decremented by 16           |
| `sd ra,8(sp)`         | `mem[sp+8]` | `0x000...0100fc`     | Saved return address                      |
| `li a2,120`          | `a2`     | `0x0000000000000078`   | `0x78 = 120 = 5!`                        |
| `li a1,5`            | `a1`     | `0x0000

> `debugger_fact_o1.png` – Spike `-d` debugger stepping through factorial `-O1`, showing `li a2,120` and register values

![Factorial Debugger O1](debugger_fact_o1.png)

> `debugger_fact_ofast.png` – Spike `-d` debugger stepping through factorial `-Ofast`, showing instruction reordering

![Factorial Debugger Ofast](debugger_fact_ofast.png)

---

## Master Comparison Table

### Instruction Count Summary (All Programs × All Optimizations)

| Program | Optimization | `main` Start | Next Function Start | Bytes | Instructions |
|---------|-------------|--------------|---------------------|-------|--------------|
| `sum1ton` | `-O1` | `0x10184` | `0x101c0` (`<atexit>`) | `0x3c = 60` | **15** |
| `sum1ton` | `-Ofast` | `0x100b0` | `0x100e0` (`<register_fini>`) | `0x30 = 48` | **12** |
| `nfact` | `-O1` | `0x10184` | `0x101b0` (`<atexit>`) | `0x2c = 44` | **11** |
| `nfact` | `-Ofast` | `0x100b0` | `0x100dc` (`<register_fini>`) | `0x2c = 44` | **11** |

### Address Calculation Recap

```
sum1ton -O1  :  0x101c0 − 0x10184 = 0x3c  = 60  bytes → 60 ÷ 4 = 15 instructions
sum1ton -Ofast: 0x100e0 − 0x100b0 = 0x30  = 48  bytes → 48 ÷ 4 = 12 instructions

nfact   -O1  :  0x101b0 − 0x10184 = 0x2c  = 44  bytes → 44 ÷ 4 = 11 instructions
nfact   -Ofast: 0x100dc − 0x100b0 = 0x2c  = 44  bytes → 44 ÷ 4 = 11 instructions
```

### Key Behavioral Differences

| Feature | `sum1ton -O1` | `sum1ton -Ofast` | `nfact -O1` | `nfact -Ofast` |
|---------|--------------|-----------------|-------------|----------------|
| Loop present | Yes (countdown) | No | No | No |
| Constant folding | Partial | Full | Full | Full |
| Result pre-loaded | `5050` via `lui+addi` pair | `5050` via `lui+addi` pair | `120` via `li a2,120` | `120` via `li a2,120` |
| Instruction scheduling | Sequential | Reordered | Sequential | Reordered |
| Instruction count | 15 | 12 | 11 | 11 |

---

## Screenshots Index

| Image File | Description |
|-----------|-------------|
| File Name | Description |
| --- | --- |
| `sum-1ton_c-code.png` | `sum1ton.c` source code in gedit (n=100) |
| `result-1_sum.png` | GCC compile+run for sum1ton: output 5050 |
| `objdump_sum_o1_cmd.png` | Terminal: RISC-V compile + objdump command for sum1ton `-O1` |
| `objdump_sum_ofast_cmd.png` | Terminal: RISC-V compile + objdump command for sum1ton `-Ofast` |
| `objdump_sum_o1.png` | Objdump disassembly of sum1ton `-O1` — 15 instructions |
| `objdump_sum_ofast.png` | Objdump disassembly of sum1ton `-Ofast` — 12 instructions |
| `riscv_result-n100_spike.png` | Spike simulation of sum1ton: `Sum from 1 to 100 is 5050` |
| `riscv_result-n50_spike.png` | Spike simulation of sum1ton: `Sum from 1 to 50 is 1275` |
| `debugger_o1.png` | Spike `-d` debugger session for sum1ton `-O1` |
| `debugger_ofast.png` | Spike `-d` debugger session for sum1ton `-Ofast` |
| `c-code_fact.png` | `nfact.c` source code in gedit (n=5) |
| `result_gcc_n5_fact.png` | GCC compile+run for nfact: output 120 |
| `objdump_fact_o1_cmd.png` | Terminal: RISC-V compile + objdump command for nfact `-O1` |
| `objdump_fact_ofast_cmd.png` | Terminal: RISC-V compile + objdump command for nfact `-Ofast` |
| `objdump_fact_o1.png` | Objdump disassembly of nfact `-O1` — 11 instructions |
| `objdump_fact_ofast.png` | Objdump disassembly of nfact `-Ofast` — 11 instructions |
| `riscv_result-n5_fact_spike.png` | Spike simulation of nfact n=5: output 120 |
| `riscv_result-n10_fact_spike.png` | Spike simulation of nfact n=10: output 3628800 |
| `debugger_fact_o1.png` | Spike `-d` debugger session for nfact `-O1` |
| `debugger_fact_ofast.png` | Spike `-d` debugger session for nfact `-Ofast` |

---

## Learnings

### 1. What Is SPIKE and Proxy Kernel?
**SPIKE** is a simulator tool that simulates RISC-V ISA references.  Spike is a simulator that emulates a full 64-bit RISC-V processor. RISC-V binary files do not work natively on the x86 architecture, so Spike is required to run them.

The **Proxy Kernel (pk)** is a simple operating system that handles system calls like write (which is internally called by printf ) and forwards the call to the underlying operating system of the host machine. Otherwise the bare metal code will not work properly because there is no operating system to handle the print call.

```
[Your C Program] --> printf() --> syscall --> pk catches --> calls on host Linux --> prints
```

### 2. Functioning of Spike `-d` (Debugger Mode)
The `-d` flag invokes Spike into a state wherein it acts as an **interactive debugger** similar to GDB but for the RISC-V simulation environment:

| Command         | Functionality                                       |
| --------------- | -------------------------------------------------- |
| `until pc 0 ADDR`     | Executes without printing until the PC of core 0 reaches `ADDR` |
| `reg 0 REGNAME`       | Shows the value in the register `REGNAME` of core 0         |
| `mem 0 ADDR`          | Prints memory contents `ADDR` of core 0 (8 bytes)            |
| `[Enter key]`         | Executes an instruction, prints next one                    |
| `q`                   | Quit debugger mode                                  |

### 3. Constant Folding in Factorial Program
We can see that in the factorial program **constant folding** takes place because both `n=5` and `fact=1` are constants at compile time, thus, the whole loop can be evaluated by the compiler at compile time, therefore, it gives:
``` fact = 1 * 5 * 4 * 3 * 2 * 1 = 120 ```
Thus output is just a single line of code i.e. `li a2,120`, so there is no difference in the number of `nfact` instructions between `-O1` and `-Ofast` (11).

### 4. Why Does `sum1ton` Produce a Loop But `nfact` Doesn’t?
- `sum1ton -O1`: In spite of the compiler preserving the loop, which contains two instructions (`addiw` and `bnez`), it still succeeds in computing the constant. It is strange because the loop is executed, but it doesn't influence the number to be printed (`li a2,5050`); nevertheless, at `-Ofast`, the compiler succeeds in eliminating the loop
- `nfact -O1`: As far as the computation is concerned, it involves multiplying constants; accordingly, constant folding takes place much more extensively compared to the previous case; accordingly, the loop can be eliminated by `-O1` optimization level
- Thus, it becomes obvious that **optimization depends on computations being performed**

### 5. Instruction Reordering via `-Ofast`
By comparing instruction optimizations using `-O1` and `-Ofast`, `-Ofast` applies the technique known as **instruction reordering** to increase the efficiency of the pipeline:
- With `-O1`, `addi sp,sp,-16` (adjusting the stack pointer) comes first, and then `sd ra,8(sp)` (storing of the ra register)
- However, when `-Ofast` is applied, `-Ofast` puts an independent instruction `lui a0,0x21` ahead of adjusting the stack pointer to prevent the loading/storing pipeline from being stalled by the process

### 6. `bbl loader` Message
The `bbl loader` message comes at the start of each Spike + pk program run. The source of this message is none other than the **Berkeley Boot Loader**, announcing its activation in Spike's setup process.
### 7. Verification: Host GCC vs. SPIKE Must Match
A critical check is that the output of `gcc` on the host must equal the output of `spike pk` on the RISC-V binary:

| Program | GCC (x86) | Spike (RISC-V) | Match? |
|---------|-----------|----------------|--------|
| sum1ton (n=100) | `5050` | `5050` | Yes |
| sum1ton (n=50) | `1275` | `1275` | Yes|
| nfact (n=5) | `120` | `120` | Yes|
| nfact (n=10) | `3628800` | `3628800` | Yes|

---

## Conclusion

Task 2 illustrated how to completely simulate and debug RISC-V program using Spike ISA simulator.

### What Was Accomplished

**For `sum1ton.c` (Spike):**
- Correctness of RISC-V binary proven by `spike pk sum1ton.o`, which showed `5050` when n=100 and `1275` when n=50, similar to GCC
- Addressing proved by checking number of instructions: **15 instructions** for `-O1`, and **12 instructions** (20% less than `-O1`) for `-Ofast`
- Checked with `spike -d`, addresses of numbers in register `a5` shown: `100 -> 99 ->...-> 0`

**For `nfact.c` (custom application):**
- Factorials of 5 and 10 equal 120 and 3628800 respectively confirmed in both GCC and Spike simulators
- Addressing confirmed by checking number of instructions: `-O1` and `-Ofast` produce **11 instructions** each
- Factoring loop removed by implementing **constant folding** technique, even under `-O1` optimization flag
- Only difference is scheduling of operations; `-O1` and `-Ofast` produce the same output
- Confirmed by debugging, where `li a2,120` leads to `0x78` which equals `1
### Final Instruction Count Summary

```
sum1ton -O1  :  0x101c0 − 0x10184 = 60 bytes →  15 instructions
sum1ton -Ofast: 0x100e0 − 0x100b0 = 48 bytes →  12 instructions  (20% reduction)

nfact   -O1  :  0x101b0 − 0x10184 = 44 bytes →  11 instructions
nfact   -Ofast: 0x100dc − 0x100b0 = 44 bytes →  11 instructions  (0% reduction — already optimal)
```
---
