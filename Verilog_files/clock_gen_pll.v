`timescale 1ns / 1ps

module clock_gen_pll (
    input  wire clk_in,    // 20 MHz Input
    input  wire reset,     // Active High Reset
    output reg  clk_out,   // 400 MHz Output
    output reg  locked     // Status signal
);

    // Initial states
    initial begin
        clk_out = 0;
        locked = 0;
    end

    // PLL Locking Logic
    // In an ASIC, the analog loop takes time to stabilize.
    always @(posedge clk_in or posedge reset) begin
        if (reset) begin
            locked <= 0;
        end else begin
            // Simulate a lock time of 200ns
            #200 locked <= 1;
        end
    end

    // 400 MHz Clock Generation
    // Period = 2.5ns. Half-period = 1.25ns.
    always begin
        #1.25 clk_out = ~clk_out;
    end

endmodule