`timescale 1ns / 1ps

/**
 * @module ble_tx_system_tb
 * @brief Interactive Profiling Testbench using SystemVerilog
 */
module ble_tx_system_tb;

    // --- Signals ---
    reg         ext_clk;
    reg         rst_n;
    reg         start_tx;
    reg  [7:0]  tx_data_in;
    reg         tx_valid_in;

    wire        tx_ready_out;
    wire        irq_tx_done;
    wire        rf_out;

    // --- Instantiate the Top-Level System ---
    ble_tx_top uut (
        .ext_clk(ext_clk),
        .rst_n(rst_n),
        .start_tx(start_tx),
        .tx_data_in(tx_data_in),
        .tx_valid_in(tx_valid_in),
        .tx_ready_out(tx_ready_out),
        .irq_tx_done(irq_tx_done),
        .rf_out(rf_out)
    );

    // --- Clock Generation ---
    initial ext_clk = 0;
    always #25 ext_clk = ~ext_clk; // 20MHz (50ns period)

    // --- Statistics Tracking Variables ---
    integer total_cycles = 0;
    integer state_cycles [0:6]; // Array to count cycles for each of the 7 states
    
    string user_payload = "TEST"; // Default payload
    integer payload_length;
    integer i;

    // --- Cycle Counting Block (The Snooper) ---
    // This runs in the background and watches the internal FSM state
    always @(posedge ext_clk) begin
        if (rst_n) begin
            total_cycles++;
            // Hierarchical access: peeking directly into the framer's state register
            state_cycles[uut.i_framer.state]++; 
        end
    end

    // --- Main Test Procedure ---
    initial begin
        $dumpfile("ble_system_full.vcd");
        $dumpvars(0, ble_tx_system_tb);

        // 0. Initialize Counters
        for (i = 0; i < 7; i++) state_cycles[i] = 0;

        // 1. Fetch Terminal Input
        // If the user runs the sim with +MSG="Hello", it overrides the default
        if ($value$plusargs("MSG=%s", user_payload)) begin
            $display("-----------------------------------------");
            $display(">> Terminal Input Detected: '%s'", user_payload);
        end else begin
            $display("-----------------------------------------");
            $display(">> No input detected. Using default: '%s'", user_payload);
        end
        
        payload_length = user_payload.len();
        $display(">> Payload Size: %0d bytes", payload_length);
        $display("-----------------------------------------");

        // 2. System Reset
        rst_n = 0;
        start_tx = 0;
        tx_data_in = 0;
        tx_valid_in = 0;
        #200 rst_n = 1;
        #100;

        // 3. Initiate Transmission
        @(posedge ext_clk);
        start_tx = 1;
        @(posedge ext_clk);
        start_tx = 0;

        // 4. Feed the Header
        feed_byte(8'h00); // ADV_IND
        feed_byte(payload_length[7:0]); // Dynamic Length Byte

        // 5. Feed the Payload Loop (ASCII Conversion)
        for (i = 0; i < payload_length; i++) begin
            // Extract single character from string and cast to byte
            feed_byte(user_payload[i]); 
        end

        // 6. Wait for Hardware to Finish
        wait(irq_tx_done);
        #500; 

        // 7. Print Final Profiling Statistics
        print_statistics();
        $finish;
    end

    // --- Task: CPU/DMA Handshake ---
    task feed_byte(input [7:0] data);
        begin
            while (!tx_ready_out) @(posedge ext_clk);
            tx_data_in  = data;
            tx_valid_in = 1;
            
            @(posedge ext_clk);
            while (tx_ready_out) @(posedge ext_clk);
            tx_valid_in = 0;
        end
    endtask

    // --- Task: Print Profiling Report ---
    task print_statistics;
        begin
            $display("\n=========================================");
            $display("       BLE TX HARDWARE PROFILING         ");
            $display("=========================================");
            $display(" Payload Sent : '%s'", user_payload);
            $display(" Payload Size : %0d Bytes (%0d bits)", payload_length, payload_length*8);
            $display(" Total Time   : %0d ns", $time);
            $display(" Total Cycles : %0d", total_cycles);
            $display("-----------------------------------------");
            $display(" Cycles Spent Per FSM Stage:");
            $display("   [0] IDLE     : %0d", state_cycles[0]);
            $display("   [1] PREAMBLE : %0d (Expected ~8)", state_cycles[1]);
            $display("   [2] ADDR     : %0d (Expected ~32)", state_cycles[2]);
            $display("   [3] HEADER   : %0d (Expected ~16)", state_cycles[3]);
            $display("   [4] PAYLOAD  : %0d (Expected ~%0d)", state_cycles[4], payload_length*8);
            $display("   [5] CRC      : %0d (Expected ~24)", state_cycles[5]);
            $display("   [6] DONE     : %0d", state_cycles[6]);
            $display("=========================================\n");
        end
    endtask

endmodule