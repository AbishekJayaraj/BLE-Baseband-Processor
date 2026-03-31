`timescale 1ns / 1ps

module gfsk_modulator_tb;

    // --- Simulation Configuration ---
    // Change these to test different "Math" scenarios
    parameter REAL_SYS_FREQ = 20_000_000; 
    parameter REAL_INT_MULT = 20;
    
    // Derived Timing for the Testbench Generator
    parameter SYS_PERIOD = 1000000000 / REAL_SYS_FREQ; // 50ns for 20MHz
    
    // --- Signals ---
    reg  ext_clk;
    reg  rst_n;
    reg  whitened_data_in;
    wire rf_modulated_out;

    // --- Instantiate the Agile Transmission Chain ---
    tx_modulator_clocks #(
        .SYS_CLK_FREQ(REAL_SYS_FREQ),
        .PLL_MULT(REAL_INT_MULT),
        .CARRIER_FREQ(100_000_000),
        .DEV_FREQ(10_000_000)
    ) uut (
        .ext_clk(ext_clk),
        .rst_n(rst_n),
        .whitened_data_in(whitened_data_in),
        .rf_modulated_out(rf_modulated_out)
    );

    // --- Clock Generation ---
    initial ext_clk = 0;
    always #(SYS_PERIOD/2) ext_clk = ~ext_clk;

    // --- Test Sequence ---
    initial begin
        // 1. Setup Waveform Dump
        $dumpfile("gfsk_math_test.vcd");
        $dumpvars(0, gfsk_modulator_tb);
        
        $display("--- Starting GFSK Math Engine Verification ---");
        $display("System Clock: %0d MHz | Target Bitrate: %0d Mbps", REAL_SYS_FREQ/1000000, REAL_SYS_FREQ/1000000);
        
        // 2. Reset Phase
        rst_n = 0;
        whitened_data_in = 0;
        #(SYS_PERIOD * 10);
        rst_n = 1;
        
        // Wait for Behavioral PLL to "Lock"
        wait(uut.locked == 1);
        $display("PLL Locked. Commencing Data Transmission...");

        // 3. Send Test Pattern: 10110
        // We change data on the falling edge of the system clock 
        // to ensure stable setup/hold for the modulator.
        
        send_bit(1);
        send_bit(0);
        send_bit(1);
        send_bit(1);
        send_bit(0);

        // 4. Final Observation Window
        #(SYS_PERIOD * 20);
        $display("--- Simulation Finished ---");
        $finish;
    end

    // --- Task: Send a single bit ---
    task send_bit(input bit_val);
        begin
            @(negedge ext_clk);
            whitened_data_in = bit_val;
            $display("[%0t] Input Bit: %b | Current Frequency Shift: %s", 
                     $time, bit_val, (bit_val ? "Rising/High" : "Falling/Low"));
        end
    endtask

endmodule