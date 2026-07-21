`timescale 1ns/1ps

module mealy_1101_detector (
    input  wire clk,
    input  wire reset,
    input  wire data_in,
    output reg  detected
);

    // Each state records the longest suffix that is also a prefix of 1101.
    localparam S0 = 2'b00,  // No matching bits
               S1 = 2'b01,  // Received 1
               S2 = 2'b10,  // Received 11
               S3 = 2'b11;  // Received 110

    reg [1:0] current_state;
    reg [1:0] next_state;

    // State memory: reset is asynchronous and active high.
    always @(posedge clk or posedge reset) begin
        if (reset)
            current_state <= S0;
        else
            current_state <= next_state;
    end

    // Combinational next-state logic and Mealy output.
    always @(*) begin
        next_state = current_state;
        detected   = 1'b0;

        case (current_state)
            S0: begin
                if (data_in)
                    next_state = S1;
                else
                    next_state = S0;
            end

            S1: begin
                if (data_in)
                    next_state = S2;
                else
                    next_state = S0;
            end

            S2: begin
                if (data_in)
                    next_state = S2;   // The suffix 11 can begin a new match.
                else
                    next_state = S3;   // Received 110.
            end

            S3: begin
                if (data_in) begin
                    detected   = 1'b1; // Received 1101.
                    next_state = S1;   // Final 1 can begin an overlapping match.
                end
                else begin
                    next_state = S0;
                end
            end

            default: begin
                next_state = S0;
                detected   = 1'b0;
            end
        endcase
    end

endmodule
