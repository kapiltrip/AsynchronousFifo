`timescale 1ns/1ps

// Five basic tests for the asynchronous FIFO.
module async_fifo_tb;
    reg wr_clk;
    reg rd_clk;
    reg wr_reset;
    reg rd_reset;
    reg wr_en;
    reg rd_en;
    reg [7:0] data_in;

    wire full;
    wire empty;
    wire [7:0] data_out;

    integer errors;
    integer i;
    integer round;
    reg [3:0] saved_pointer;

    async_fifo #(
        .DATA_WIDTH(8),
        .ADDRESS_WIDTH(3)
    ) dut (
        .wr_clk(wr_clk),
        .wr_reset(wr_reset),
        .wr_en(wr_en),
        .data_in(data_in),
        .full(full),
        .rd_clk(rd_clk),
        .rd_reset(rd_reset),
        .rd_en(rd_en),
        .data_out(data_out),
        .empty(empty)
    );

    // Write clock: 10 ns period.
    initial begin
        wr_clk = 0;
        forever #5 wr_clk = ~wr_clk;
    end

    // Read clock: 14 ns period, with a 2 ns starting delay.
    initial begin
        rd_clk = 0;
        #2;
        forever #7 rd_clk = ~rd_clk;
    end

    task reset_fifo;
        begin
            wr_en = 0;
            rd_en = 0;
            data_in = 0;
            wr_reset = 1;
            rd_reset = 1;
            #20;
            @(negedge wr_clk);
            wr_reset = 0;
            @(negedge rd_clk);
            rd_reset = 0;
        end
    endtask

    task write_byte;
        input [7:0] value;
        begin
            @(negedge wr_clk);
            data_in = value;
            wr_en = 1;
            @(negedge wr_clk);
            wr_en = 0;
        end
    endtask

    task read_byte;
        input [7:0] expected;
        begin
            wait (!empty);
            @(negedge rd_clk);
            rd_en = 1;
            @(posedge rd_clk);
            #1;
            if (data_out !== expected) begin
                errors = errors + 1;
                $display("FAIL: expected %02h, got %02h", expected, data_out);
            end
            @(negedge rd_clk);
            rd_en = 0;
        end
    endtask

    initial begin
        errors = 0;
        wr_reset = 1;
        rd_reset = 1;
        wr_en = 0;
        rd_en = 0;
        data_in = 0;

        // TEST 1: reset values and empty-read protection.
        $display("TEST 1: reset and empty read");
        reset_fifo;

        if (empty !== 1 || full !== 0 || data_out !== 0) begin
            errors = errors + 1;
            $display("FAIL: wrong reset values");
        end

        saved_pointer = dut.rd_bin;
        @(negedge rd_clk);
        rd_en = 1;
        @(negedge rd_clk);
        rd_en = 0;

        if (dut.rd_bin !== saved_pointer) begin
            errors = errors + 1;
            $display("FAIL: empty read moved the read pointer");
        end

        // TEST 2: write A5 and read A5.
        $display("TEST 2: one write and one read");
        reset_fifo;
        write_byte(8'hA5);
        read_byte(8'hA5);

        if (empty !== 1) begin
            errors = errors + 1;
            $display("FAIL: FIFO should be empty after the read");
        end

        // TEST 3: values must come out in the same order.
        $display("TEST 3: FIFO order");
        reset_fifo;
        for (i = 0; i < 4; i = i + 1)
            write_byte(8'h10 + i);
        for (i = 0; i < 4; i = i + 1)
            read_byte(8'h10 + i);

        // TEST 4: fill the FIFO and block one extra write.
        $display("TEST 4: full and overflow protection");
        reset_fifo;
        for (i = 0; i < 8; i = i + 1)
            write_byte(8'h80 + i);

        if (full !== 1) begin
            errors = errors + 1;
            $display("FAIL: full did not become 1");
        end

        saved_pointer = dut.wr_bin;
        write_byte(8'hEE);

        if (dut.wr_bin !== saved_pointer) begin
            errors = errors + 1;
            $display("FAIL: extra write changed the write pointer");
        end

        for (i = 0; i < 8; i = i + 1)
            read_byte(8'h80 + i);

        // TEST 5: two full rounds make both pointers wrap to zero.
        $display("TEST 5: pointer wraparound");
        reset_fifo;
        for (round = 0; round < 2; round = round + 1) begin
            for (i = 0; i < 8; i = i + 1)
                write_byte((round * 8) + i);
            for (i = 0; i < 8; i = i + 1)
                read_byte((round * 8) + i);
        end

        if (dut.wr_bin !== 0 || dut.rd_bin !== 0) begin
            errors = errors + 1;
            $display("FAIL: pointers did not wrap to zero");
        end

        #20;
        if (errors == 0) begin
            $display("ASYNC_FIFO_TESTS: PASS");
            $display("All 5 basic tests passed");
            $finish;
        end else begin
            $display("ASYNC_FIFO_TESTS: FAIL");
            $fatal(1, "FIFO test failed");
        end
    end
endmodule
