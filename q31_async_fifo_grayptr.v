module asyncFifo #(
    parameter dw = 8,
    parameter aw = 4
) (
    input  wire           rdclk,
    input  wire           wrclk,
    input  wire           rdrst,
    input  wire           wrrst,
    input  wire           rden,
    input  wire           wren,
    input  wire [dw-1:0]  din,
    output reg  [dw-1:0]  dout,
    output wire           empty,
    output wire           full
);
    localparam depth = (1 << aw);

    // FIFO storage
    reg [dw-1:0] mem [0:depth-1];

    // Read and write binary pointers (extra MSB tracks wraparound)
    reg [aw:0] rdptrbin;
    reg [aw:0] wrptrbin;
    reg [aw:0] rdptrbin_next;
    reg [aw:0] wrptrbin_next;

    // Read and write Gray pointers
    reg [aw:0] rdptrgray;
    reg [aw:0] wrptrgray;
    reg [aw:0] rdptrgray_next;
    reg [aw:0] wrptrgray_next;

    // Synchronized Gray pointers crossing between domains
    reg [aw:0] rdptrgray1;
    reg [aw:0] rdptrgray2;
    reg [aw:0] wrptrgray1;
    reg [aw:0] wrptrgray2;

    function [aw:0] binary2gray;
        input [aw:0] bin;
        begin
            binary2gray = bin ^ (bin >> 1);
        end
    endfunction

    // Next-state logic for read pointer
    always @(*) begin
        rdptrbin_next = rdptrbin;
        if (rden && !empty)
            rdptrbin_next = rdptrbin + 1'b1;
    end

    // Next-state logic for write pointer
    always @(*) begin
        wrptrbin_next = wrptrbin;
        if (wren && !full)
            wrptrbin_next = wrptrbin + 1'b1;
    end

    // Convert next binary pointers to Gray pointers
    always @(*) begin
        rdptrgray_next = binary2gray(rdptrbin_next);
        wrptrgray_next = binary2gray(wrptrbin_next);
    end

    // Write-domain logic
    always @(posedge wrclk or posedge wrrst) begin
        if (wrrst) begin
            wrptrbin  <= {(aw+1){1'b0}};
            wrptrgray <= {(aw+1){1'b0}};
        end else begin
            wrptrbin  <= wrptrbin_next;
            wrptrgray <= wrptrgray_next;
            if (wren && !full)
                mem[wrptrbin[aw-1:0]] <= din;
        end
    end

    // Read-domain logic
    always @(posedge rdclk or posedge rdrst) begin
        if (rdrst) begin
            rdptrbin  <= {(aw+1){1'b0}};
            rdptrgray <= {(aw+1){1'b0}};
            dout      <= {dw{1'b0}};
        end else begin
            rdptrbin  <= rdptrbin_next;
            rdptrgray <= rdptrgray_next;
            if (rden && !empty)
                dout <= mem[rdptrbin[aw-1:0]];
        end
    end

    // Synchronize read pointer into write domain
    always @(posedge wrclk or posedge wrrst) begin
        if (wrrst) begin
            rdptrgray1 <= {(aw+1){1'b0}};
            rdptrgray2 <= {(aw+1){1'b0}};
        end else begin
            rdptrgray1 <= rdptrgray;
            rdptrgray2 <= rdptrgray1;
        end
    end

    // Synchronize write pointer into read domain
    always @(posedge rdclk or posedge rdrst) begin
        if (rdrst) begin
            wrptrgray1 <= {(aw+1){1'b0}};
            wrptrgray2 <= {(aw+1){1'b0}};
        end else begin
            wrptrgray1 <= wrptrgray;
            wrptrgray2 <= wrptrgray1;
        end
    end

    // Full when next write pointer matches synchronized read pointer
    // with the top two bits inverted.
    assign full = (wrptrgray_next == {~rdptrgray2[aw:aw-1], rdptrgray2[aw-2:0]});

    // Empty when next read pointer matches synchronized write pointer.
    assign empty = (rdptrgray_next == wrptrgray2);
endmodule
