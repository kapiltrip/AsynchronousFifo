`timescale 1ns/1ps

module mealy_1101_detector_tb;

    reg  clk;
    reg  reset;
    reg  data_in;
    wire detected;

    integer error_count;
    integer bit_number;

    localparam S0 = 2'b00,
               S1 = 2'b01,
               S2 = 2'b10,
               S3 = 2'b11;

    mealy_1101_detector dut (
        .clk      (clk),
        .reset    (reset),
        .data_in  (data_in),
        .detected (detected)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_bit;
        input       stimulus_bit;
        input       expected_detected;
        input [1:0] expected_state_after_edge;
        begin
            // Change serial data halfway between active clock edges.
            @(negedge clk);
            data_in = stimulus_bit;
            bit_number = bit_number + 1;

            // A Mealy output reacts during the same cycle, before the edge.
            #1;
            if (detected !== expected_detected) begin
                $display("FAIL bit %0d at %0t: data=%b detected=%b expected=%b state=%b",
                         bit_number, $time, data_in, detected,
                         expected_detected, dut.current_state);
                error_count = error_count + 1;
            end

            // The state memory updates at the next rising edge.
            @(posedge clk);
            #1;
            if (dut.current_state !== expected_state_after_edge) begin
                $display("FAIL bit %0d at %0t: state=%b expected_state=%b",
                         bit_number, $time, dut.current_state,
                         expected_state_after_edge);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        $timeformat(-9, 0, " ns", 8);
        error_count = 0;
        bit_number  = 0;
        reset       = 1'b1;
        data_in     = 1'b0;

        // Prove the asynchronous reset does not need a clock edge.
        #2;
        if ((dut.current_state !== S0) || (detected !== 1'b0)) begin
            $display("FAIL asynchronous reset at %0t", $time);
            error_count = error_count + 1;
        end

        @(negedge clk);
        reset = 1'b0;

        // Non-matching prefix: 010.
        check_bit(1'b0, 1'b0, S0);
        check_bit(1'b1, 1'b0, S1);
        check_bit(1'b0, 1'b0, S0);

        // First exact match: 1101. Detection occurs on the fourth bit.
        check_bit(1'b1, 1'b0, S1);
        check_bit(1'b1, 1'b0, S2);
        check_bit(1'b0, 1'b0, S3);
        check_bit(1'b1, 1'b1, S1);

        // Continue with 101. Together with the previous final 1 this proves
        // overlapping matches in the stream 1101101.
        check_bit(1'b1, 1'b0, S2);
        check_bit(1'b0, 1'b0, S3);
        check_bit(1'b1, 1'b1, S1);

        // Extra leading ones: the detector retains the useful suffix 11.
        check_bit(1'b1, 1'b0, S2);
        check_bit(1'b1, 1'b0, S2);
        check_bit(1'b0, 1'b0, S3);
        check_bit(1'b1, 1'b1, S1);

        // Return to S0, then assert reset between clock edges once more.
        check_bit(1'b0, 1'b0, S0);
        #2 reset = 1'b1;
        #1;
        if ((dut.current_state !== S0) || (detected !== 1'b0)) begin
            $display("FAIL mid-cycle asynchronous reset at %0t", $time);
            error_count = error_count + 1;
        end
        #2 reset = 1'b0;

        if (error_count == 0)
            $display("PASS: all Mealy 1101 detector checks passed (%0d input bits)",
                     bit_number);
        else begin
            $display("FAIL: %0d checks failed", error_count);
            $fatal(1, "Self-checking testbench failed");
        end

        #5 $finish;
    end

endmodule
