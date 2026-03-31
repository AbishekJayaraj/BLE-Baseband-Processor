`timescale 1ns / 1ps

module tb_data_whitener;

    // --- Inputs ---
    reg        clk;
    reg        rst_n;
    reg        lfsr_load;
    reg        enable;
    reg [5:0]  channel_index;
    reg        data_in;

    // --- Outputs ---
    wire       whitened_data_out;

    // --- Instantiate the Unit Under Test (UUT) ---
    data_whitener uut (
        .clk(clk),
        .rst_n(rst_n),
        .lfsr_load(lfsr_load),
        .enable(enable),
        .channel_index(channel_index),
        .data_in(data_in),
        .whitened_data_out(whitened_data_out)
    );

    // --- Clock Generator (20MHz -> 50ns period) ---
    parameter CLK_PERIOD = 50;
    always begin
        clk = 0; #(CLK_PERIOD / 2);
        clk = 1; #(CLK_PERIOD / 2);
    end

    // --- Test Sequence ---
    initial begin
        // 1. Setup Waveform Dump
        $dumpfile("whitener_wave.vcd");
        $dumpvars(0, tb_data_whitener);

        // 2. Initialization & Reset
        $display("Starting Data Whitener Simulation...");
        rst_n = 0;
        lfsr_load = 0;
        enable = 0;
        channel_index = 0;
        data_in = 0;
        #(CLK_PERIOD * 2);
        
        rst_n = 1;
        #(CLK_PERIOD);

        // 3. Load Channel Index 37 (6'b100101)
        // This should result in LFSR being loaded with 7'b1001010
        @(negedge clk);
        channel_index = 6'b100101;
        lfsr_load = 1;
        @(posedge clk);
        #1 lfsr_load = 0;
        $display("Channel 37 loaded. LFSR should be 7'h4A.");

        // 4. Send a stream of 10 Zeros
        // Since data_in is 0, whitened_data_out will exactly match the LFSR sequence
        $display("Sending 10 zeros. Output should be the scrambling sequence:");
        
        repeat (10) begin
            @(negedge clk);
            enable = 1;
            data_in = 1; 
            @(posedge clk);
            #1; // Wait for logic to settle
            $display("Input: %b | Whitened Output: %b | LFSR State: %b", data_in, whitened_data_out, uut.lfsr);
        end

        enable = 0;
        #(CLK_PERIOD * 5);

        $display("Simulation Complete.");
        $finish;
    end

endmodule