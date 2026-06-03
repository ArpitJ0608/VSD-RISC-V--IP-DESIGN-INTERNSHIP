# RISC-V Lab – Sum 1 to N (C + RISC-V Toolchain)

> **Revision Task 1** – Create GitHub repo · Install RISC-V toolchain · Compile C code · Generate RISC-V Object Dump

---

## 📋 Table of Contents

1. [Task Overview](#task-overview)
2. [Tools & Environment](#tools--environment)
3. [C Source Code](#c-source-code)
4. [Compiling with GCC (x86)](#compiling-with-gcc-x86)
5. [Compiling with RISC-V Toolchain](#compiling-with-risc-v-toolchain)
6. [Object Dump – `-O1` Optimization](#object-dump----o1-optimization)
7. [Object Dump – `-Ofast` Optimization](#object-dump----ofast-optimization)
8. [Comparison: `-O1` vs `-Ofast`](#comparison--o1-vs--ofast)
9. [Screenshots](#screenshots)
10. [Learnings](#learnings)
11. [Conclusion](#conclusion)

---

## Task Overview

The goal of this task is to:

- Write a simple C program that calculates the **sum from 1 to N**
- Compile and run it on a **standard GCC** compiler
- Cross-compile it using the **RISC-V GCC toolchain** (`riscv64-unknown-elf-gcc`) with two different optimization levels: `-O1` and `-Ofast`
- Inspect the generated **RISC-V assembly** using `objdump`
- Understand how compiler optimizations affect the number of instructions

---

## Tools & Environment

| Tool | Purpose |
|------|---------|
| `gedit` | GUI text editor used to write/edit the C source file |
| `gcc` | Standard GNU C Compiler for x86 (host machine testing) |
| `riscv64-unknown-elf-gcc` | RISC-V cross-compiler for generating RISC-V object files |
| `riscv64-unknown-elf-objdump` | Disassembler to view RISC-V assembly from object files |
| `less` | Pager utility to scroll through long objdump output |

**Working Directory:** `/workspaces/vsd-riscv2/samples`

---

## C Source Code

The file `sum1ton.c` computes the sum of all integers from 1 to `n`.

```c
#include <stdio.h>

int main(){
    int i, sum=0, n=50;
    for(i=1;i<=n;i++)
        sum = sum + i;
    printf("Sum from 1 to %d is %d \n", n, sum);
    return 0;
}
```

**Screenshot – Source code in gedit (n=100) and terminal `cat` output (n=50):**

> 📸 `sum-1ton_c-code.png` – Source code viewed in gedit editor  
> 📸 `sum-1ton_cat.png` – Source code viewed via `cat sum1ton.c` in terminal

---

## Compiling with GCC (x86)

### Commands Used

```bash
# Navigate to working directory
cd /workspaces/vsd-riscv2/samples

# Open file in gedit editor (GUI)
gedit sum1ton.c

# Compile with standard GCC
gcc sum1ton.c

# Run the output
./a.out
```

### Explanation

| Command | Description |
|---------|-------------|
| `cd /workspaces/vsd-riscv2/samples` | Navigate to the project directory |
| `gedit sum1ton.c` | Open the file in the GUI text editor for editing |
| `gcc sum1ton.c` | Compile the C file using the host GCC (produces `a.out` by default) |
| `./a.out` | Execute the compiled binary |

### Output

- With `n=100`: `Sum from 1 to 100 is 5050`
- With `n=50`: `Sum from 1 to 50 is 1275`

> 📸 `result-1_sum.png` – Terminal showing compile + run with n=100, output: 5050  
> 📸 `result-2_sum.png` – Terminal showing compile + run with n=50, output: 1275

---

## Compiling with RISC-V Toolchain

### Command for `-O1`

```bash
riscv64-unknown-elf-gcc -O1 -mabi=lp64 -march=rv64i -o sum1ton.o sum1ton.c
```

### Command for `-Ofast`

```bash
riscv64-unknown-elf-gcc -Ofast -mabi=lp64 -march=rv64i -o sum1ton.o sum1ton.c
```

### Flag Explanations

| Flag | Meaning |
|------|---------|
| `riscv64-unknown-elf-gcc` | RISC-V 64-bit cross-compiler targeting bare-metal ELF binaries |
| `-O1` | Basic optimizations — reduces code size and improves speed with minimal compile time |
| `-Ofast` | Aggressive optimizations — enables all `-O3` optimizations plus potentially non-standard behavior (e.g., loop unrolling, constant folding) |
| `-mabi=lp64` | Specifies the ABI: **L**ong and **P**ointers are **64**-bit wide |
| `-march=rv64i` | Target architecture: RISC-V 64-bit with the base Integer instruction set only |
| `-o sum1ton.o` | Name the output file `sum1ton.o` |
| `sum1ton.c` | Input C source file |

---

## Object Dump – `-O1` Optimization

### Command

```bash
riscv64-unknown-elf-objdump -d sum1ton.o | less
```

### Explanation

| Part | Description |
|------|-------------|
| `riscv64-unknown-elf-objdump` | RISC-V disassembler tool |
| `-d` | Disassemble all executable sections of the object file into human-readable assembly |
| `sum1ton.o` | The compiled RISC-V ELF object file |
| `\| less` | Pipe through `less` pager to scroll the long output interactively |

### 📐 Instruction Count Calculation (`-O1`)

From the objdump screenshot, the `<main>` function occupies the following address range:

```
<main>  starts at : 0x10184
<atexit> starts at : 0x101bc   ← this is where the next function begins
```

Since in RISC-V each instruction is exactly **4 bytes** wide:

```
Number of bytes  = 0x101bc − 0x10184
               = 0x38
               = 56 (decimal)

Number of instructions = 56 ÷ 4 = 14 instructions
```

> ✅ **`main` compiled with `-O1` uses exactly 14 instructions.**

### Instruction-by-Instruction Walkthrough (`-O1`)

| Address | Hex Encoding | Instruction | Explanation |
|---------|-------------|-------------|-------------|
| `10184` | `ff010113` | `addi sp,sp,-16` | Prologue: allocate 16 bytes on the stack for the stack frame |
| `10188` | `00113423` | `sd ra,8(sp)` | Save return address register `ra` onto the stack |
| `1018c` | `03200793` | `li a5,50` | Load immediate: set loop counter `a5 = 50` (value of `n`) |
| `10190` | `fff7879b` | `addiw a5,a5,-1` | Decrement loop counter: `a5 = a5 - 1` (32-bit word operation) |
| `10194` | `fe079ee3` | `bnez a5,10190` | Branch if `a5 ≠ 0` → jump back to `10190` (this is the loop) |
| `10198` | `4fb00613` | `li a2,1275` | Load the **pre-computed sum** `1275` into `a2` (3rd printf arg) |
| `1019c` | `03200593` | `li a1,50` | Load `n=50` into `a1` (2nd printf arg: `%d` = n) |
| `101a0` | `00021537` | `lui a0,0x21` | Load upper 20 bits of printf format string address into `a0` |
| `101a4` | `18050513` | `addi a0,a0,384` | Add lower 12 bits → complete the format string address in `a0` |
| `101a8` | `26c000ef` | `jal ra,10414 <printf>` | Call `printf` — jump and link (saves return address in `ra`) |
| `101ac` | `00000513` | `li a0,0` | Load return value `0` into `a0` (for `return 0`) |
| `101b0` | `00813083` | `ld ra,8(sp)` | Restore return address from stack |
| `101b4` | `01010113` | `addi sp,sp,16` | Epilogue: deallocate the 16-byte stack frame |
| `101b8` | `00008067` | `ret` | Return to caller (jumps to address in `ra`) |

### Key Insights (`-O1`)

- The **loop body is present** but it's a counting-down loop — the compiler transformed `for(i=1;i<=50;i++)` into a decrement loop (`a5` counts 50 → 0)
- **Constant folding happened partially**: the loop runs but the sum `1275` is already precomputed and loaded directly via `li a2,1275` — the loop is effectively a no-op dummy countdown
- The `sd ra,8(sp)` / `ld ra,8(sp)` pair shows a proper **stack frame** is set up and torn down (function call convention preserved)
- `jal` is a **Jump And Link** instruction — it saves the return address in `ra` before jumping to `printf`

> 📸 `objdump_sum_o1.png` – Full objdump output with `-O1`

![O1 Objdump](objdump_sum_o1.png)

---

## Object Dump – `-Ofast` Optimization

### Command

```bash
riscv64-unknown-elf-objdump -d sum1ton.o | less
```

*(Same command; the object file was recompiled with `-Ofast` before running this)*

### 📐 Instruction Count Calculation (`-Ofast`)

From the objdump screenshot, the `<main>` function occupies the following address range:

```
<main>           starts at : 0x100b0
<register_fini>  starts at : 0x100dc   ← this is where the next function begins
```

Since in RISC-V each instruction is exactly **4 bytes** wide:

```
Number of bytes  = 0x100dc − 0x100b0
               = 0x2c
               = 44 (decimal)

Number of instructions = 44 ÷ 4 = 11 instructions
```

> ✅ **`main` compiled with `-Ofast` uses exactly 11 instructions — 3 fewer than `-O1`.**

### Instruction-by-Instruction Walkthrough (`-Ofast`)

| Address | Hex Encoding | Instruction | Explanation |
|---------|-------------|-------------|-------------|
| `100b0` | `00021537` | `lui a0,0x21` | Load upper 20 bits of format string address into `a0` |
| `100b4` | `ff010113` | `addi sp,sp,-16` | Prologue: allocate 16-byte stack frame |
| `100b8` | `4fb00613` | `li a2,1275` | Directly load **compile-time constant** `1275` into `a2` — loop eliminated entirely! |
| `100bc` | `03200593` | `li a1,50` | Load `n=50` into `a1` (2nd printf argument) |
| `100c0` | `18050513` | `addi a0,a0,384` | Complete the format string address in `a0` (lower 12 bits) |
| `100c4` | `00113423` | `sd ra,8(sp)` | Save return address register `ra` onto the stack |
| `100c8` | `340000ef` | `jal ra,10408 <printf>` | Call `printf` |
| `100cc` | `00813083` | `ld ra,8(sp)` | Restore return address from stack |
| `100d0` | `00000513` | `li a0,0` | Load return value `0` into `a0` |
| `100d4` | `01010113` | `addi sp,sp,16` | Epilogue: deallocate the 16-byte stack frame |
| `100d8` | `00008067` | `ret` | Return to caller |

### Key Insights (`-Ofast`)

- **The entire loop is gone** — there is no `addiw`, no `bnez`, no loop counter register. The compiler determined the result at compile time
- `li a2,1275` appears as the **very first data-loading instruction** — the sum `1+2+...+50 = 1275` is a compile-time constant folded at `-Ofast`
- The `lui a0,0x21` / `addi a0,a0,384` pair constructs the printf format string address — this is a **2-instruction PC-relative address load** pattern common in RISC-V
- Notice the `sd ra,8(sp)` (save `ra`) is reordered to appear **after** the `li` instructions — this is **instruction scheduling** by the compiler to avoid pipeline stalls
- The `printf` call target is `10408` here vs `10414` in `-O1` — the function starts at a slightly different address because the binary layout changed

> 📸 `objdump_sum_ofast.png` – Full objdump output with `-Ofast`

![Ofast Objdump](objdump_sum_ofast.png)

---

## Comparison: `-O1` vs `-Ofast`

| Aspect | `-O1` | `-Ofast` |
|--------|-------|---------|
| **`main` start address** | `0x10184` | `0x100b0` |
| **Next function address** | `0x101bc` (`<atexit>`) | `0x100dc` (`<register_fini>`) |
| **Bytes in `main`** | `0x101bc − 0x10184 = 0x38 = 56 bytes` | `0x100dc − 0x100b0 = 0x2c = 44 bytes` |
| **Instruction count** | **56 ÷ 4 = 14 instructions** | **44 ÷ 4 = 11 instructions** |
| **Loop present?** | ✅ Yes (`addiw` + `bnez` countdown loop) | ❌ No (fully eliminated) |
| **Sum computed at** | Runtime (loop runs, but sum preloaded separately) | Compile time (constant folding) |
| **`li a2` value** | `1275` (precomputed alongside the loop) | `1275` (only instruction for sum) |
| **Instruction scheduling** | Sequential, standard order | Reordered (`sd ra` moved after `li` instructions) |
| **Stack frame** | Standard prologue/epilogue | Same, but instructions reordered |
| **`printf` call target** | `10414` | `10408` |
| **Binary size (main only)** | 56 bytes | 44 bytes |

### Address Calculation Summary

```
-O1 :  0x101bc - 0x10184 = 0x38 = 56 bytes → 56 / 4 = 14 instructions
-Ofast: 0x100dc - 0x100b0 = 0x2c = 44 bytes → 44 / 4 = 11 instructions

Reduction: 14 - 11 = 3 fewer instructions with -Ofast (≈ 21% reduction)
```

### Key Insight

Even at `-O1`, GCC already does **constant folding** — it knows `1+2+...+50 = 1275` at compile time and embeds that directly. However, `-O1` still emits the loop structure as "dead" counting code. `-Ofast` is aggressive enough to **completely delete the loop**, resulting in a leaner 11-instruction `main`.

---

## Screenshots

| Image | Description |
|-------|-------------|
| `sum-1ton_c-code.png` | C source code (`n=100`) open in `gedit` editor |
| `sum-1ton_cat.png` | C source code (`n=50`) displayed via `cat sum1ton.c` |
| `result-1_sum.png` | GCC compile + run with `n=100`, output: `Sum from 1 to 100 is 5050` |
| `result-2_sum.png` | GCC compile + run with `n=50`, output: `Sum from 1 to 50 is 1275` |
| `objdump_sum_o1.png` | RISC-V objdump of binary compiled with `-O1` — 14 instructions in `main` |
| `objdump_sum_ofast.png` | RISC-V objdump of binary compiled with `-Ofast` — 11 instructions in `main` |

> ⬆️ All images are in the same folder as this README.

---

## Learnings

### 1. Cross-Compilation Concept
A **cross-compiler** like `riscv64-unknown-elf-gcc` runs on one architecture (x86 host) but generates machine code for a completely different target (RISC-V 64-bit). This is essential in embedded systems and VLSI design where the target hardware may not have enough resources to run a compiler itself.

### 2. RISC-V is a Fixed-Width ISA
Every RISC-V instruction in the base `rv64i` ISA is exactly **4 bytes (32 bits)** wide. This makes instruction counting trivially easy:
```
instruction_count = (end_address − start_address) / 4
```
This is a major architectural advantage over variable-width ISAs like x86 where instruction sizes vary from 1–15 bytes.

### 3. How to Read `objdump` Output
- The **first column** is the memory address (hex) of the instruction
- The **second column** is the raw hex encoding of the instruction (machine code)
- The **third column** is the mnemonic (human-readable assembly)
- The **fourth column** is the operands
- The **next function label** in the dump marks the end of the current function — subtract start from it to get size

### 4. Compiler Optimizations — Constant Folding
Both `-O1` and `-Ofast` performed **constant folding** on this program. Since `n=50` is a compile-time constant, the compiler calculates `sum = 1+2+...+50 = 1275` during compilation and directly encodes the result as `li a2,1275`, completely bypassing any runtime computation.

### 5. `-O1` vs `-Ofast` — What's Different
| Optimization | `-O1` | `-Ofast` |
|---|---|---|
| Constant folding | ✅ Yes | ✅ Yes |
| Dead code / loop elimination | ❌ No (loop kept) | ✅ Yes (loop removed) |
| Instruction scheduling | ❌ Minimal | ✅ Yes (reorders for pipeline) |
| IEEE floating point compliance | ✅ Maintained | ❌ May break (allows unsafe math) |

### 6. ABI and Architecture Flags Matter
- `-mabi=lp64` tells the compiler how to pass arguments and what register widths to assume (Long=64-bit, Pointer=64-bit)
- `-march=rv64i` constrains the compiler to only use the base integer instruction set — no hardware floating-point, no multiplication extensions
- Changing these flags would produce entirely different assembly

### 7. RISC-V Calling Convention
From the objdump, you can see the **RISC-V ABI** in action:
- `a0` = first argument to a function / return value
- `a1` = second argument
- `a2` = third argument
- `ra` = return address (must be saved/restored if you call another function)
- `sp` = stack pointer (must be 16-byte aligned)

### 8. The Role of `objdump`
`objdump -d` is an essential tool in embedded/VLSI workflows for:
- Verifying that the compiler generated the expected assembly
- Counting instructions to estimate execution time (in cycle-accurate simulators)
- Debugging issues that only appear at the assembly level
- Checking that unused code was eliminated by the optimizer

---

## Conclusion

This lab successfully demonstrated the complete workflow of writing, compiling, and analyzing a C program targeting the **RISC-V 64-bit architecture**.

**What was accomplished:**

1. A simple C program (`sum1ton.c`) was written to compute the sum from 1 to N and verified correct on the host machine using `gcc` — producing outputs `5050` (N=100) and `1275` (N=50)

2. The same program was cross-compiled for RISC-V using `riscv64-unknown-elf-gcc` with two optimization levels, and the resulting ELF binaries were disassembled using `objdump`

3. **Address-based instruction counting** confirmed:
   - `-O1` → `0x101bc − 0x10184 = 56 bytes → **14 instructions**`
   - `-Ofast` → `0x100dc − 0x100b0 = 44 bytes → **11 instructions**`

4. The key takeaway is that **compiler optimizations are powerful and measurable** — `-Ofast` reduced the instruction count by 21% (3 instructions) compared to `-O1` for this simple program, primarily through aggressive loop elimination and instruction scheduling

5. This exercise reinforces a foundational skill in RISC-V / VLSI design: **reading and interpreting assembly output** to understand what the hardware will actually execute, not just what the C source says

> The ability to cross-compile C code and inspect the resulting RISC-V assembly using `objdump` is a core competency in embedded systems, RTL verification, and custom processor design.

---

## References

- [C Based Lab Video](https://1drv.ms/v/s!Ai4WW_jutenghrYpUsL_MLKJDSLVyg?e=gdA9TW)
- [RISC-V Based Lab Video](https://1drv.ms/v/s!Ai4WW_jutengg7dbp9XlZXjJmxogBw?e=ycX4fO)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
