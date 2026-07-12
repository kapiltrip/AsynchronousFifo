# Simple Asynchronous FIFO

This folder intentionally keeps only the files needed to understand, test, and reopen the design.

## Main files

- `async_fifo.v` - the FIFO design, written in plain Verilog.
- `async_fifo_tb.v` - one beginner-readable testbench containing only 5 basic test cases.
- `Asynchronous_FIFO_Test_Cases.xlsx` - test cases, expected results, observed Vivado results, and timing notes.
- `Asynchronous_FIFO_Guide.docx` - simple explanation of the design, timing, causes, waveform phases, and Vivado verification.
- `Asynchronous_FIFO_Verification_and_Signal_Guide.pdf` - polished revision guide covering the five completed tests, every current FIFO signal, and the next verification targets.
- `vivado/async_fifo_vivado.xpr` - the Vivado 2024.1 project.
- `vivado/async_fifo_waveform.wcfg` - the saved clean waveform view.

## How to verify

1. Open `vivado/async_fifo_vivado.xpr` in Vivado.
2. Click **Run Simulation > Run Behavioral Simulation**.
3. Run the simulation to completion.
4. The Tcl/XSim output must show `ASYNC_FIFO_TESTS: PASS` and no `FAIL` line.
5. Use the saved waveform view to inspect clocks, resets, enables, data, `full`, `empty`, and the binary/Gray pointers.

The default FIFO is 8 entries x 8 bits. The write clock period is 10 ns. The read clock period is 14 ns with a 2 ns starting offset, so the two clock domains never depend on a fixed phase relationship.

## How the HD waveform images were created

The waveform pictures in `Asynchronous_FIFO_Guide.docx` were made from the **actual Vivado XSim simulation data**. They were not guessed or manually drawn.

### 1. Export the real waveform data from Vivado

After opening the behavioral simulation, these commands were entered in the Vivado Tcl Console:

```tcl
open_vcd [file normalize [file join [get_property DIRECTORY [current_project]] .. async_fifo.vcd]]
log_vcd [get_objects -r /async_fifo_tb/*]
restart
run all
close_vcd
```

This reruns the five tests and saves every signal change with its exact simulation time in `async_fifo.vcd`. The VCD time resolution was 1 ps, while the report explains the important events in ns.

### 2. Select the useful test intervals

The complete run is 0 to 1590 ns. Four views were prepared:

- Complete five-test overview: 0 to 1590 ns.
- One write and one read: 58 to 156 ns.
- Full FIFO and blocked extra write: 366 to 786 ns.
- Two pointer-wraparound rounds: 786 to 1590 ns.

### 3. Draw clean high-resolution pictures

A small Python script read the VCD timestamps and signal values. Pillow was used to draw the clocks, enables, data, pointers, `full`, and `empty` as 3200-pixel-wide PNG images at 300 DPI. Important events were labelled using the times measured from the VCD file.

This produces cleaner report figures than normal screen captures while still using the real Vivado values. The pictures are only a visual explanation; the self-checking Verilog testbench is what decides `PASS` or `FAIL`.

### 4. Add them to the Word report

The PNG files were embedded directly in the Word document. Each picture was followed by four simple explanations:

- **What** happened.
- **When** it happened.
- **Cause** of the signal change.
- **Why** the timing is correct for an asynchronous FIFO.

The temporary VCD, PNG files, and image-generation script were removed after the pictures were embedded, keeping this project folder simple. To create them again, repeat the same VCD export and plotting process above. The editable Vivado signal view remains saved in `vivado/async_fifo_waveform.wcfg`.

## Future Work

Keep the current version as the simple learning baseline. Possible improvements later are:

- Add `almost_full` and `almost_empty` warning flags.
- Add a fill-level counter in each clock domain.
- Add formal assertions for overflow, underflow, and data ordering.
- Add FPGA clock/reset constraints and run a focused CDC report.
- Test the FIFO on a real FPGA board with two independent clocks.
- Infer block RAM for a deeper FIFO after the basic register-memory version is understood.
- Add randomized stress testing only after the five basic tests are easy to explain.
