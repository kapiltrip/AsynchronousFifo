`timescale 1ns/1ps

// Simple asynchronous FIFO.
// Data is written with wr_clk and read with rd_clk.
// Gray pointers cross clock domains through two flip-flops.
module async_fifo #(
    parameter DATA_WIDTH    = 8,
    parameter ADDRESS_WIDTH = 3
) (
    input  wire                  wr_clk,
    input  wire                  wr_reset,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg                   full,

    input  wire                  rd_clk,
    input  wire                  rd_reset,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   empty
);
    localparam DEPTH = (1 << ADDRESS_WIDTH);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    reg [ADDRESS_WIDTH:0] wr_bin;
    reg [ADDRESS_WIDTH:0] wr_gray;
    reg [ADDRESS_WIDTH:0] rd_bin;
    reg [ADDRESS_WIDTH:0] rd_gray;

    // Two flip-flops make each Gray pointer safe to use in the other domain.
    (* ASYNC_REG = "TRUE" *) reg [ADDRESS_WIDTH:0] rd_gray_sync1;
    (* ASYNC_REG = "TRUE" *) reg [ADDRESS_WIDTH:0] rd_gray_sync2;
    (* ASYNC_REG = "TRUE" *) reg [ADDRESS_WIDTH:0] wr_gray_sync1;
    (* ASYNC_REG = "TRUE" *) reg [ADDRESS_WIDTH:0] wr_gray_sync2;

    wire write_allowed;
    wire read_allowed;
    wire [ADDRESS_WIDTH:0] wr_bin_next;
    wire [ADDRESS_WIDTH:0] rd_bin_next;
    wire [ADDRESS_WIDTH:0] wr_gray_next;
    wire [ADDRESS_WIDTH:0] rd_gray_next;
    wire full_next;
    wire empty_next;

    assign write_allowed = wr_en && !full;
    assign read_allowed  = rd_en && !empty;

    assign wr_bin_next  = wr_bin + write_allowed;
    assign rd_bin_next  = rd_bin + read_allowed;
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    // Full means the next write pointer is one complete FIFO depth ahead.
    assign full_next = (wr_gray_next ==
                        {~rd_gray_sync2[ADDRESS_WIDTH:ADDRESS_WIDTH-1],
                          rd_gray_sync2[ADDRESS_WIDTH-2:0]});

    // Empty means the next read pointer catches the synchronized write pointer.
    assign empty_next = (rd_gray_next == wr_gray_sync2);

    always @(posedge wr_clk or posedge wr_reset) begin
        if (wr_reset) begin
            wr_bin  <= 0;
            wr_gray <= 0;
            full    <= 1'b0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
            full    <= full_next;

            if (write_allowed)
                memory[wr_bin[ADDRESS_WIDTH-1:0]] <= data_in;
        end
    end

    always @(posedge rd_clk or posedge rd_reset) begin
        if (rd_reset) begin
            rd_bin   <= 0;
            rd_gray  <= 0;
            data_out <= 0;
            empty    <= 1'b1;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
            empty   <= empty_next;

            if (read_allowed)
                data_out <= memory[rd_bin[ADDRESS_WIDTH-1:0]];
        end
    end

    always @(posedge wr_clk or posedge wr_reset) begin
        if (wr_reset) begin
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    always @(posedge rd_clk or posedge rd_reset) begin
        if (rd_reset) begin
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end
endmodule
