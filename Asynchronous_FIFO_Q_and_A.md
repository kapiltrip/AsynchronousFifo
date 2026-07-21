# Asynchronous FIFO — Deep Questions and Answers

This page records the questions that came up while building and understanding `async_fifo.v`. The answers use the names in the current design: `DW`, `AW`, `din`, `dout`, `wr_rst`, `rd_rst`, `wr_bin`, `rd_bin`, and the `*_next` signals.

## Quick index

1. [Why are there two clock domains?](#1-what-do-two-clock-domains-mean-in-practice)
2. [Why are Gray pointers synchronized through two flip-flops?](#2-why-do-gray-pointers-pass-through-two-flip-flops)
3. [Why is the pointer width `[AW:0]`?](#3-why-is-a-pointer-declared-as-aw0)
4. [Why are the `*_next` signals wires rather than registers?](#4-why-are-the-_next-signals-wires-rather-than-regs)
5. [What do `wr_bin` and `wr_bin_next` mean?](#5-what-do-wr_bin-and-wr_bin_next-mean)
6. [Why is `(wr_en && !full)` used?](#6-why-is-wr_en--full-used-in-the-write-pointer-equation)
7. [Why are the signals called `next`?](#7-why-are-the-signals-called-next)
8. [Why assign `empty_next` to `empty` in a clocked block?](#8-why-is-empty_next-assigned-to-empty-in-a-clocked-block)
9. [Why use current-state and next-state values together?](#9-why-use-current-state-and-next-state-values-together)
10. [Why does the FIFO need flip-flops?](#10-why-does-the-fifo-need-flip-flops)
11. [What do `full_next` and `empty_next` really predict?](#11-what-do-full_next-and-empty_next-really-predict)
12. [What does `ASYNC_REG` do?](#12-what-does-the-async_reg-attribute-do)

## 1. What do two clock domains mean in practice?

A clock domain is a group of flip-flops whose state is captured by the same clock. This FIFO contains two domains because it has two independent clocks:

```verilog
wr_clk  // controls the write side
rd_clk  // controls the read side
```

In the current testbench, `wr_clk` has a 10 ns period (100 MHz) and `rd_clk` has a 14 ns period (about 71.43 MHz), with an initial phase offset. Their rising edges do not occur together in a fixed pattern.

A practical example is a camera producing pixels with its own pixel clock while a processor consumes those pixels using a system clock. The producer writes whenever `wr_clk` permits; the consumer reads whenever `rd_clk` permits. The FIFO absorbs the temporary rate difference.

Different frequencies are a common reason for separate clock domains, but they are not the definition. Two clocks can have the same nominal frequency and still be asynchronous if their phase relationship is not guaranteed or if they come from separate oscillators. Conversely, two clocks derived from the same source can sometimes have a known synchronous relationship that timing tools can analyze.

In this design:

- The write domain owns `wr_bin`, `wr_gray`, `full`, and memory writes.
- The read domain owns `rd_bin`, `rd_gray`, `empty`, and `dout` updates.
- `rd_gray` crosses from the read domain to the write domain.
- `wr_gray` crosses from the write domain to the read domain.

The phrase “crossing a clock domain” means that a signal produced by flip-flops using one clock is observed by flip-flops using a different, unrelated clock.

## 2. Why do Gray pointers pass through two flip-flops?

The receiving clock can sample a changing pointer close to its active clock edge. That can violate the setup or hold requirement of the first receiving flip-flop and make it metastable: for a short, unpredictable time its internal voltage is not a valid logic 0 or 1.

The two stages are:

```text
asynchronous Gray pointer → sync1 → sync2 → local FIFO logic
```

The first stage is allowed to face the asynchronous transition. The second stage samples the first stage one destination-clock cycle later, giving the first stage additional time to settle. This does not make the probability of failure mathematically zero, but it reduces it dramatically.

The FIFO uses Gray code as well because adjacent Gray values change only one bit. A normal binary transition can change several bits, such as `0111 → 1000`. If those bits arrive with slightly different delays, the receiver can observe an incoherent value. Gray code limits a normal pointer increment to one changing bit, while the two-flop chain handles the metastability risk on that changing bit.

Only the second stage should feed `full` or `empty` detection:

```verilog
rd_gray_sync2  // used in the write domain
wr_gray_sync2  // used in the read domain
```

## 3. Why is a pointer declared as `[AW:0]`?

`[AW:0]` contains `AW + 1` bits. If `AW = 3`, the FIFO has eight memory locations and the pointer is four bits wide:

```text
Pointer bits: [3:0]
Address bits: [2:0]
Wrap bit:       [3]
```

The lower `AW` bits select a memory location:

```verilog
memory[wr_bin[AW-1:0]]
```

The extra most-significant bit records that the pointer has completed another lap through the memory. This distinction is necessary because the read and write address bits can be equal in two very different situations:

- Same position and same lap: the FIFO is empty.
- Same memory address but the write pointer is one complete lap ahead: the FIFO is full.

Without the extra wrap information, equal address bits alone could not distinguish full from empty.

## 4. Why are the `*_next` signals wires rather than regs?

The `*_next` signals are outputs of continuous combinational calculations:

```verilog
assign wr_bin_next  = wr_bin + (wr_en && !full);
assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
```

In Verilog, a signal driven by a continuous `assign` statement is a net, so it is declared as `wire`. These signals do not remember previous values. When one of their inputs changes, their calculated value changes after the combinational propagation delay.

The current-state signals are assigned inside clocked `always` blocks and therefore are declared as `reg` in plain Verilog:

```verilog
always @(posedge wr_clk)
    wr_bin <= wr_bin_next;
```

The important distinction is not simply “wire versus physical register.” In Verilog, `reg` is a language variable type used for procedural assignments; whether hardware becomes a flip-flop depends on the clocked behavior. In SystemVerilog, both kinds are commonly declared as `logic`, while the driving style still determines the hardware.

## 5. What do `wr_bin` and `wr_bin_next` mean?

`wr_bin` is the current binary write pointer stored in flip-flops. During an accepted write, its lower bits select the memory location used for that write:

```verilog
memory[wr_bin[AW-1:0]] <= din;
```

`wr_bin_next` is the pointer value that should exist after the upcoming write-clock edge. For example, assume:

```text
wr_bin = 3, wr_en = 1, full = 0
```

Before the clock edge, combinational logic calculates `wr_bin_next = 4`. At the clock edge, the old/current pointer still supplies memory address 3, while the pointer flip-flops capture 4:

```text
memory[3] receives din
wr_bin becomes 4
```

Therefore the precise meanings are:

```text
wr_bin      = current stored pointer and current accepted-write address
wr_bin_next = pointer state after the current write attempt
```

## 6. Why is `(wr_en && !full)` used in the write-pointer equation?

The equation is:

```verilog
assign wr_bin_next = wr_bin + (wr_en && !full);
```

`wr_bin` is not part of the condition. It is the current value from which the next value is calculated. The condition is only `(wr_en && !full)`.

Logical `&&` produces a one-bit result:

| `wr_en` | `full` | `(wr_en && !full)` | Pointer action |
|---:|---:|---:|---|
| 0 | 0 | 0 | Hold |
| 0 | 1 | 0 | Hold |
| 1 | 0 | 1 | Increment |
| 1 | 1 | 0 | Hold |

Consequently, the equation is equivalent to:

```verilog
assign wr_bin_next = (wr_en && !full)
                   ? wr_bin + 1'b1
                   : wr_bin;
```

`wr_en` expresses a request from the producer. `!full` expresses permission from the FIFO. Both must be true before data is accepted. The same condition guards the memory write, keeping pointer movement exactly aligned with accepted data:

```verilog
if (wr_en && !full)
    memory[wr_bin[AW-1:0]] <= din;
```

If the pointer advanced without a corresponding write, the FIFO would claim that nonexistent data had been stored. If it advanced while full, unread data could eventually be overwritten and the full/empty calculations would become incorrect.

## 7. Why are the signals called `next`?

`next` is a naming convention for a combinational value intended to become a register’s state at the next active clock edge:

```text
current Q output → combinational next-state logic → D input
     wr_bin                  wr_bin_next
```

The name is not caused by the physical order of statements in the source file. Verilog module-level `assign` and `always` blocks execute concurrently. The `empty_next` assignment can appear near the top or immediately before `endmodule` without changing the synthesized logic.

Not every combinational signal should be called `next`. A signal deserves that name when it is specifically calculated to be captured as the next state of a sequential register.

## 8. Why is `empty_next` assigned to `empty` in a clocked block?

`empty_next` predicts whether the FIFO will be empty after the possible read at the upcoming `rd_clk` edge:

```verilog
assign empty_next = (rd_gray_next == wr_gray_sync2);
```

`empty` is the registered current flag visible to the read interface:

```verilog
always @(posedge rd_clk or posedge rd_rst) begin
    if (rd_rst)
        empty <= 1'b1;
    else
        empty <= empty_next;
end
```

Consider a FIFO holding exactly one word. Before the edge, the current read pointer is one position behind the synchronized write pointer, so `empty = 0`. If `rd_en = 1`, `rd_bin_next` advances to the write position. Therefore `empty_next = 1` before the edge. At the edge, the final word is read, the read pointer advances, and `empty` captures 1 together.

If a registered flag were calculated only from the old `rd_gray`, it would still see the pre-read pointer at that edge and could assert one cycle late. Comparing the predicted `rd_gray_next` lets the final accepted read and the assertion of `empty` describe the same resulting FIFO state.

Registering `empty` in the read domain also keeps the interface flag synchronous to `rd_clk`; downstream read-domain logic does not have to react to an arbitrary combinational transition.

## 9. Why use current-state and next-state values together?

An FIFO must both remember its present state and decide what its state should become. These are different hardware jobs:

- Flip-flops hold the current state.
- Combinational logic calculates the next state from the current state and current inputs.
- The clock tells the flip-flops when to capture that next state.

You can write the calculation directly in a clocked block:

```verilog
wr_bin <= wr_bin + (wr_en && !full);
```

That removes the separately named `wr_bin_next` wire from the source, but it does not remove the combinational adder and enable logic from the hardware. The expression on the right-hand side still becomes logic feeding the flip-flop’s D input.

Named next-state signals are useful here because several values must describe the same predicted state. `wr_gray_next` must be generated from the pointer that will exist after the possible write, and `full_next` must compare that same next Gray pointer. Naming `wr_bin_next` prevents repeated expressions and avoids accidentally calculating `wr_gray` from the old pointer.

## 10. Why does the FIFO need flip-flops?

Combinational logic cannot remember where the FIFO was on the previous clock cycle. It only maps its current inputs to current outputs. The FIFO needs persistent state to remember:

- The current write position.
- The current read position.
- Pointer wraparound.
- The registered `full` and `empty` status.
- The most recently registered `dout` value.

The pointer flip-flops make a sequence such as `0 → 1 → 2 → 3` persist across clock cycles. Without them, the pointer would not be a counter with history.

The synchronizer flip-flops have a second role. They do not store FIFO occupancy directly; they allow an asynchronous Gray pointer to enter the destination domain with greatly reduced metastability risk.

The FIFO therefore contains three kinds of storage:

- Memory array: stores the actual data words.
- State flip-flops: store pointers and status flags.
- Synchronizer flip-flops: safely convey pointer state between domains.

## 11. What do `full_next` and `empty_next` really predict?

`full_next` asks:

> After the possible write represented by `wr_bin_next`, should the registered write-domain `full` flag become 1?

For an eight-entry FIFO containing seven words, an accepted eighth write makes `wr_gray_next` reach the Gray-code full relationship with the synchronized read pointer. `full_next` becomes 1 before the edge. At the edge, the eighth word is stored and `full` becomes 1 together.

`empty_next` asks:

> After the possible read represented by `rd_bin_next`, should the registered read-domain `empty` flag become 1?

When the final word is accepted for reading, `rd_gray_next` reaches `wr_gray_sync2`. `empty_next` becomes 1 and the registered flag asserts at that same read edge.

The flags are conservative across the clock-domain boundary because they use synchronized remote pointers. For example, after a write, the read domain may continue reporting `empty = 1` for a few `rd_clk` cycles while the new write pointer passes through its two synchronization stages. This latency is intentional: temporarily delaying permission is safe, whereas reading data before the write is safely visible is not.

## 12. What does the `ASYNC_REG` attribute do?

The commented declarations show the FPGA implementation attribute:

```verilog
// (* ASYNC_REG = "TRUE" *) reg [AW:0] rd_gray_sync1;
// (* ASYNC_REG = "TRUE" *) reg [AW:0] rd_gray_sync2;
```

The two sequential assignments create the synchronizer behavior. The attribute does not create synchronization by itself. Instead, it informs FPGA synthesis and implementation tools that these registers form an asynchronous synchronizer chain. A tool such as Vivado can preserve the chain, place its flip-flops close together, and handle it appropriately during timing and CDC analysis.

The ordinary `reg` declarations are currently active so the functional code can first be studied without tool-specific syntax. For a production FPGA implementation, the `ASYNC_REG` attributes should normally be restored along with proper clock and CDC constraints.

## Final mental model

```text
CURRENT STATE           COMBINATIONAL DECISION             NEXT CLOCK EDGE
wr_bin            →     wr_bin_next                  →      stored into wr_bin
wr_bin_next       →     wr_gray_next                 →      stored into wr_gray
wr_gray_next +
rd_gray_sync2     →     full_next                    →      stored into full

rd_bin            →     rd_bin_next                  →      stored into rd_bin
rd_bin_next       →     rd_gray_next                 →      stored into rd_gray
rd_gray_next +
wr_gray_sync2     →     empty_next                   →      stored into empty
```

The clock decides **when** state changes. The combinational logic decides **what** the new state will be. The flip-flops remember that state until the following clock edge.
