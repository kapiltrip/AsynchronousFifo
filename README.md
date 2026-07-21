# Asynchronous FIFO — RTL, Learning Notes, Q&A, and Verification

This repository is a practical learning project for a parameterized asynchronous FIFO written in plain Verilog. It connects a producer in the `wr_clk` domain to a consumer in the independent `rd_clk` domain while preserving data order and safely transferring FIFO-pointer information between the two domains.

## Repository page

| Section | Open | What it contains |
|---|---|---|
| RTL design | [`async_fifo.v`](./async_fifo.v) | FIFO memory, binary/Gray pointers, synchronizers, and registered `full`/`empty` flags |
| Testbench | [`async_fifo_tb.v`](./async_fifo_tb.v) | Five self-checking baseline tests with unrelated write/read clocks |
| Deep Q&A | [`Asynchronous_FIFO_Q_and_A.md`](./Asynchronous_FIFO_Q_and_A.md) | Detailed answers to the exact questions asked while learning this design |
| Handwritten notes | [`handwritten/README.md`](./handwritten/README.md) | Index and placement guide for future photographed or scanned notes |
| Excel verification plan | [`Asynchronous_FIFO_Test_Cases.xlsx`](./Asynchronous_FIFO_Test_Cases.xlsx) | Executed test cases, expected/observed results, and timing explanations |
| Word guide | [`Asynchronous_FIFO_Guide.docx`](./Asynchronous_FIFO_Guide.docx) | Editable design and waveform explanation |
| PDF revision guide | [`Asynchronous_FIFO_Verification_and_Signal_Guide.pdf`](./Asynchronous_FIFO_Verification_and_Signal_Guide.pdf) | Printable verification and signal reference |
| Vivado project | [`vivado/async_fifo_vivado.xpr`](./vivado/async_fifo_vivado.xpr) | Reopenable Vivado project |
| Saved waveform | [`vivado/async_fifo_waveform.wcfg`](./vivado/async_fifo_waveform.wcfg) | Prepared XSim waveform configuration |

## Recommended learning order

1. Read the [design interface and architecture](#design-interface-and-architecture) below.
2. Open [`async_fifo.v`](./async_fifo.v) and follow its comments from declarations to full/empty detection.
3. Read the [deep Q&A page](./Asynchronous_FIFO_Q_and_A.md), which explains the current/next-state model, clock domains, pointer conditions, wires, flip-flops, and synchronizers.
4. Read [`async_fifo_tb.v`](./async_fifo_tb.v) beside the Excel verification plan.
5. Run the testbench and inspect the saved Vivado waveform.

## Design interface and architecture

The default configuration is eight entries of eight bits each:

| Parameter | Default | Meaning |
|---|---:|---|
| `DW` | 8 | Width of each stored data word |
| `AW` | 3 | Number of RAM address bits |
| `DEPTH` | `2^AW = 8` | Number of FIFO storage locations |

The binary and Gray pointers are `[AW:0]`, so each pointer has one more bit than the memory address. The lower `AW` bits select a memory location; the extra bit records pointer wraparound for full/empty detection.

### Ports

| Port | Direction | Clock domain | Purpose |
|---|---|---|---|
| `wr_clk` | Input | Write | Captures write-side state |
| `wr_rst` | Input | Write | Asynchronously resets write pointer and `full` |
| `wr_en` | Input | Write | Requests a write |
| `din[DW-1:0]` | Input | Write | Data presented for writing |
| `full` | Output | Write | Blocks writes when all locations are occupied |
| `rd_clk` | Input | Read | Captures read-side state |
| `rd_rst` | Input | Read | Asynchronously resets read pointer, `dout`, and `empty` |
| `rd_en` | Input | Read | Requests a read |
| `dout[DW-1:0]` | Output | Read | Most recently accepted read value |
| `empty` | Output | Read | Blocks reads when no valid word is available |

### Two practical clock domains

```text
Producer / write domain                         Consumer / read domain

din, wr_en, wr_clk                              rd_en, rd_clk, dout
        │                                                ▲
        ▼                                                │
  write pointer ───────► FIFO memory ─────────────► read pointer
        │                                                │
        └─ Gray pointer ── 2-FF synchronizer ───────────►│
        │◄────────────── 2-FF synchronizer ── Gray pointer
        │                                                │
      full                                             empty
```

The testbench deliberately uses a 100 MHz write clock and an approximately 71.43 MHz read clock. Their edges have no fixed alignment, so pointer information cannot be consumed directly in the opposite domain.

### Current state and next state

The design separates stored state from combinationally predicted state:

```text
Current flip-flop value → combinational calculation → value captured next edge

wr_bin                 → wr_bin_next              → wr_bin
wr_bin_next            → wr_gray_next             → wr_gray
wr_gray_next           → full_next                → full

rd_bin                 → rd_bin_next              → rd_bin
rd_bin_next            → rd_gray_next             → rd_gray
rd_gray_next           → empty_next               → empty
```

The clock determines **when** state changes. Combinational logic determines **what** value the flip-flops capture.

### Accepted write and read conditions

```verilog
wr_en && !full   // write request plus available space
rd_en && !empty  // read request plus available data
```

The pointer moves only when the matching memory operation is accepted. This keeps pointer state aligned with the number of data words actually added or removed.

### Clock-domain crossing

Only Gray-coded pointers cross between the domains:

```text
rd_gray → rd_gray_sync1 → rd_gray_sync2 → write-side full detection
wr_gray → wr_gray_sync1 → wr_gray_sync2 → read-side empty detection
```

The first destination-domain flip-flop can encounter metastability. The second stage gives it additional settling time. Gray code limits a normal pointer step to one changing bit, preventing multi-bit binary transitions from appearing as incoherent pointer values.

> Learning baseline: the tool-specific `ASYNC_REG` attributes are currently commented out in `async_fifo.v`. The two sequential synchronizer stages remain functionally present. Restore the attributes and add proper clock/CDC constraints before treating this as production FPGA CDC implementation.

## Current verification status

The self-checking testbench currently executes five baseline scenarios:

| ID | Scenario | Main requirement | Status |
|---|---|---|---|
| T01 | Reset and empty-read protection | Reset values are correct and an empty read cannot move `rd_bin` | PASS |
| T02 | One write and one read | `8'hA5` is returned and `empty` reasserts after the read | PASS |
| T03 | FIFO ordering | `10, 11, 12, 13` are read in the original order | PASS |
| T04 | Full and overflow protection | Eighth write asserts `full`; extra `8'hEE` write is blocked | PASS |
| T05 | Pointer wraparound | Two fill/drain rounds preserve data and return both extended pointers to zero | PASS |

The detailed expected results and timing reasons are in the [Excel verification plan](./Asynchronous_FIFO_Test_Cases.xlsx).

### Next verification targets

The baseline tests prove the main functional path, but a complete verification campaign should add:

- Continuous simultaneous reads and writes with independent clocks.
- Several fast-write/slow-read and slow-write/fast-read ratios.
- Resetting only one domain during traffic, with an explicitly defined reset contract.
- Randomized bursts checked by a scoreboard.
- Parameter tests for multiple `DW` and `AW` values.
- Assertions that pointers never advance on blocked operations.
- Assertions that accepted reads match accepted writes in order.
- CDC analysis, timing constraints, and restored `ASYNC_REG` attributes.
- Synthesis checks for the intended FPGA memory implementation.

## Run the self-checking simulation

With Icarus Verilog:

```powershell
iverilog -g2012 -o async_fifo_tb_test async_fifo.v async_fifo_tb.v
vvp async_fifo_tb_test
```

The final output must contain:

```text
ASYNC_FIFO_TESTS: PASS
All 5 basic tests passed
```

With Vivado:

1. Open [`vivado/async_fifo_vivado.xpr`](./vivado/async_fifo_vivado.xpr).
2. Select **Run Simulation → Run Behavioral Simulation**.
3. Run until the testbench calls `$finish`.
4. Confirm the Tcl/XSim console contains `ASYNC_FIFO_TESTS: PASS` and no `FAIL` message.
5. Open [`vivado/async_fifo_waveform.wcfg`](./vivado/async_fifo_waveform.wcfg) to inspect clocks, enables, data, flags, and pointers.

## Deep Q&A from the design session

The complete answers are kept on one focused page: [Asynchronous FIFO — Deep Questions and Answers](./Asynchronous_FIFO_Q_and_A.md).

It covers:

- What two clock domains mean practically.
- Why Gray pointers cross through two flip-flops.
- Why pointers contain an extra wrap bit.
- Why `*_next` values are combinational wires.
- The exact distinction between `wr_bin` and `wr_bin_next`.
- Why `(wr_en && !full)` and `(rd_en && !empty)` are required.
- Why `empty_next` is captured into `empty` at an `rd_clk` edge.
- Why a clock cannot replace next-state combinational logic.
- Why the FIFO needs both state flip-flops and synchronizer flip-flops.

## Study artifacts

- [`Asynchronous_FIFO_Guide.docx`](./Asynchronous_FIFO_Guide.docx) is the editable long-form explanation.
- [`Asynchronous_FIFO_Verification_and_Signal_Guide.pdf`](./Asynchronous_FIFO_Verification_and_Signal_Guide.pdf) is the printable revision version.
- [`handwritten/README.md`](./handwritten/README.md) is the index for future handwritten pages so each image can remain beside its explanation.

## Design limitations and future improvements

This repository intentionally remains a beginner-readable baseline. Future versions can add `almost_full`, `almost_empty`, occupancy estimates in both domains, randomized verification, formal properties, FPGA clock/reset constraints, CDC reports, block-RAM inference, and hardware testing with truly independent clocks.
