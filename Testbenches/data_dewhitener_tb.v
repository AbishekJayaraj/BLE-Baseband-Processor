`timescale 1ns / 1ps

module data_dewhitener_tb;

    // --- Inputs ---
    reg        clk;
    reg        rst_n;
    reg        lfsr_load;
    reg        enable;
    reg [5:0]  channel_index;
    reg        data_in;

    // --- Outputs ---
    wire       dewhitened_data_out;
    wire       whitened_data_ref;

    // --- The "Golden Model" (Shadow LFSR) ---
    reg [6:0]  tb_lfsr;
    reg        expected_dewhitened;

    // --- Test Variables ---
    reg [39:0] test_pattern;
    integer i;

    // --- Instantiate the Dewhitener ---
    data_dewhitener uut_dewhitener (
        .clk(clk),
        .rst_n(rst_n),
        .lfsr_load(lfsr_load),
        .enable(enable),
        .channel_index(channel_index),
        .data_in(data_in),
        .dewhitened_data_out(dewhitened_data_out)
    );

    // --- Instantiate a whitener for loopback comparison ---
    data_whitener uut_whitener (
        .clk(clk),
        .rst_n(rst_n),
        .lfsr_load(lfsr_load),
        .enable(enable),
        .channel_index(channel_index),
        .data_in(dewhitened_data_out), 
        .whitened_data_out(whitened_data_ref)
    );

    // --- Clock Generator (20MHz -> 50ns period) ---
    parameter CLK_PERIOD = 50;
    always begin
        clk = 0; #(CLK_PERIOD / 2);
        clk = 1; #(CLK_PERIOD / 2);
    end

    // =========================================================
    // SMART TASKS FOR AUTOMATED TESTING
    // =========================================================

    // Task 1: Load Channel into Hardware and Shadow LFSR
    task load_channel(input [5:0] ch);
        begin
            @(negedge clk);
            channel_index = ch;
            lfsr_load = 1;
            
            // Seed the testbench's shadow LFSR identical to the hardware
            tb_lfsr = {ch, 1'b0}; 
            
            @(posedge clk);
            #1 lfsr_load = 0;
            $display("\n>>> Loaded Channel Index: %0d (Seed: %b) <<<", ch, tb_lfsr);
        end
    endtask

    // Task 2: Feed data, auto-calculate, and verify
    task feed_and_check(input reg test_bit);
        begin
            @(negedge clk);
            data_in = test_bit;
            enable  = 1;

            // Wait 1ns for the hardware's combinational XOR to settle
            #1; 

            // 1. Calculate the expected answer using the CURRENT LFSR state
            expected_dewhitened = test_bit ^ tb_lfsr[0];

            // 2. Automated Comparison (BEFORE the clock edge shifts the hardware)
            if ((dewhitened_data_out === expected_dewhitened) && (whitened_data_ref === test_bit)) begin
                $display("[PASS] In: %b | Dewhitened: %b (Expected: %b) | Re-Whitened Loopback: %b", 
                         test_bit, dewhitened_data_out, expected_dewhitened, whitened_data_ref);
            end else begin
                $display("[ERROR] In: %b | Dewhitened: %b (Expected: %b) | Re-Whitened Loopback: %b", 
                         test_bit, dewhitened_data_out, expected_dewhitened, whitened_data_ref);
            end

            // 3. Now wait for the rising edge that shifts the hardware LFSR...
            @(posedge clk);
            
            // ...and shift our testbench LFSR to match it!
            tb_lfsr = {tb_lfsr[5], tb_lfsr[4], tb_lfsr[3] ^ tb_lfsr[6], tb_lfsr[2], tb_lfsr[1], tb_lfsr[0], tb_lfsr[6]};
        end
    endtask

    // =========================================================
    // MAIN TEST SEQUENCE
    // =========================================================
    initial begin
        $dumpfile("dewhitener_test.vcd");
        $dumpvars(0, data_dewhitener_tb);

        $display("=== Starting Automated Data Dewhitener Verification ===");
        rst_n = 0;
        lfsr_load = 0;
        enable = 0;
        channel_index = 0;
        data_in = 0;
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);

        // --- Test 1: Random Pattern ---
        load_channel(6'd37); 
        test_pattern = 40'b0011010110001101;
        for (i = 0; i < 16; i = i + 1) begin
            feed_and_check(test_pattern[i]);
        end
        enable = 0; #(CLK_PERIOD * 3);

        // --- Test 2: Stream of Zeros ---
        load_channel(6'd21); // Channel 21
        for (i = 0; i < 10; i = i + 1) begin
            feed_and_check(1'b0);
        end
        enable = 0; #(CLK_PERIOD * 3);

        // --- Test 3: Stream of Ones ---
        load_channel(6'd51); // Channel 51
        for (i = 0; i < 10; i = i + 1) begin
            feed_and_check(1'b1);
        end
        enable = 0; #(CLK_PERIOD * 3);

        $display("\n=== Verification Complete ===");
        $finish;
    end

endmodule