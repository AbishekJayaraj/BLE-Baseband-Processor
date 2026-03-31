`timescale 1ns / 1ps

/**
 * @module ble_tx_system_tb
 * @brief Comprehensive Testbench for the Full BLE Transmitter Chain.
 */
module ble_tx_system_tb;

    // --- Signals ---
    reg         ext_clk;     // 20MHz System Clock
    reg         rst_n;
    reg         start_tx;
    reg  [7:0]  tx_data_in;
    reg         tx_valid_in;
    
    wire        tx_ready_out;
    wire        irq_tx_done;
    wire        rf_out;      // The 400MHz-sampled GFSK output

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
    // 20MHz clock = 50ns period (25ns per toggle)
    initial ext_clk = 0;
    always #25 ext_clk = ~ext_clk;

    // --- Main Test Procedure ---
    initial begin
        // Setup Waveform Dumping
        $dumpfile("ble_system_full.vcd");
        $dumpvars(0, ble_tx_system_tb);

        // 1. System Reset
        $display("[%0t] Starting System Reset...", $time);
        rst_n = 0;
        start_tx = 0;
        tx_data_in = 0;
        tx_valid_in = 0;
        
        #200 rst_n = 1;
        #100; // Wait for PLL Lock simulation

        // 2. Initiate Transmission
        @(posedge ext_clk);
        start_tx = 1;
        @(posedge ext_clk);
        start_tx = 0;
        $display("[%0t] Transmission Triggered.", $time);

        // 3. Feed the BLE Advertisement Packet
        // Standard BLE Header: Type=ADV_IND (0x00), Length=3 (0x03)
        feed_byte(8'h00); // PDU Header Byte 1
        feed_byte(8'h03); // PDU Header Byte 2 (Length field)
        
        // Payload: 0xDE, 0xAD, 0xBE
        feed_byte(8'hDE);
        feed_byte(8'hAD);
        feed_byte(8'hBE);

        // 4. Observe the Chain
        $display("[%0t] All bytes fed. Waiting for CRC and Final Modulation...", $time);
        
        // Wait for the hardware to finish the CRC and trail
        wait(irq_tx_done);
        
        #500; // Final padding to see the waveform end
        $display("[%0t] SUCCESS: Packet Transmission Complete.", $time);
        $finish;
    end

    // --- Task: CPU/DMA Handshake Simulation ---
    task feed_byte(input [7:0] data);
        begin
            // Wait for Framer to be ready for next byte
            while (!tx_ready_out) @(posedge ext_clk);
            
            tx_data_in  = data;
            tx_valid_in = 1;
            
            // Wait for Framer to consume (latch) the byte
            @(posedge ext_clk);
            while (tx_ready_out) @(posedge ext_clk);
            
            tx_valid_in = 0;
            $display("[%0t] System-In: Byte 0x%h accepted.", $time, data);
        end
    endtask

endmodule