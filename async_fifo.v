`timescale 1ns/1ps

// Simple asynchronous FIFO.
// Data is written with wr_clk and read with rd_clk.
// Gray pointers cross clock domains through two flip-flops.
module async_fifo #(
    parameter DW = 8,
    parameter AW = 3
) (
    input  wire                  wr_clk,
    input  wire                  wr_rst,
    input  wire                  wr_en,
    input  wire [DW-1:0]         din,
    output reg                   full,

    input  wire                  rd_clk,
    input  wire                  rd_rst,
    input  wire                  rd_en,
    output reg  [DW-1:0]         dout,
    output reg                   empty
);
    // AW address bits create 2^AW storage locations.
    localparam DEPTH = (1 << AW);

    // Dual-clock storage: the write side stores din and the read side reads dout.
    reg [DW-1:0] memory [0:DEPTH-1];

    // Binary pointers address the memory.  The extra MSB records wraparound.
    // Gray pointers are the versions sent safely across the clock domains.
    reg [AW:0] wr_bin;
    reg [AW:0] wr_gray;
    reg [AW:0] rd_bin;
    reg [AW:0] rd_gray;

    // Two flip-flops reduce the chance that metastability reaches FIFO logic.
    // rd_gray is synchronized into wr_clk; wr_gray is synchronized into rd_clk.
    // (* ASYNC_REG = "TRUE" *) reg [AW:0] rd_gray_sync1;
    // (* ASYNC_REG = "TRUE" *) reg [AW:0] rd_gray_sync2;
    // (* ASYNC_REG = "TRUE" *) reg [AW:0] wr_gray_sync1;
    // (* ASYNC_REG = "TRUE" *) reg [AW:0] wr_gray_sync2;

    reg [AW:0] rd_gray_sync1;
    reg [AW:0] rd_gray_sync2;
    reg [AW:0] wr_gray_sync1;
    reg [AW:0] wr_gray_sync2;

    // Combinational values that will be stored on the next clock edge.
    wire [AW:0] wr_bin_next;
    wire [AW:0] rd_bin_next;
    wire [AW:0] wr_gray_next;
    wire [AW:0] rd_gray_next;
    wire full_next;
    wire empty_next;

    // Advance a pointer only when its operation is requested and allowed.
    // Otherwise its next value remains equal to its current value.
    assign wr_bin_next  = wr_bin + (wr_en && !full);
    assign rd_bin_next  = rd_bin + (rd_en && !empty);

    // Convert each next binary pointer to Gray code (only one bit changes).
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    // WRITE DOMAIN: update the write pointer and full flag on wr_clk.
    // The current wr_bin address is used for a write before the pointer advances.
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_bin  <= 0;
            wr_gray <= 0;
            full    <= 1'b0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
            full    <= full_next;

            if (wr_en && !full)
                memory[wr_bin[AW-1:0]] <= din;
        end
    end

    // READ DOMAIN: update the read pointer and empty flag on rd_clk.
    // The current rd_bin address is used for a read before the pointer advances.
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_bin   <= 0;
            rd_gray  <= 0;
            dout     <= 0;
            empty    <= 1'b1;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
            empty   <= empty_next;

            if (rd_en && !empty)
                dout <= memory[rd_bin[AW-1:0]];
        end
    end

    // Synchronize the read Gray pointer into the write-clock domain.
    // Write-side full detection must use the second (safer) stage.
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // Synchronize the write Gray pointer into the read-clock domain.
    // Read-side empty detection must use the second (safer) stage.
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    // FULL DETECTION (write-clock domain): after the possible next write,
    // full is true when the write pointer is one complete FIFO lap ahead.
    assign full_next = (wr_gray_next ==
                        {~rd_gray_sync2[AW:AW-1],
                          rd_gray_sync2[AW-2:0]});

    // EMPTY DETECTION (read-clock domain): after the possible next read,
    // empty is true when the read pointer equals the synchronized write pointer.
    assign empty_next = (rd_gray_next == wr_gray_sync2);
endmodule
