`timescale 1ns / 1ps

module Receiver_top_tb;

    // --- Simulation Configuration ---
    parameter REAL_SYS_FREQ = 20_000_000;
    parameter REAL_INT_MULT = 20;
    parameter SYS_PERIOD = 1000000000 / REAL_SYS_FREQ;
    
    // --- Port Signals ---
    reg        ext_clk;
    reg        rst_n;
    
    // Transmitter signals
    reg        start_tx;
    reg  [7:0] tx_data_in;
    reg        tx_valid_in;
    wire       tx_ready_out;
    wire       irq_tx_done;
    wire       rf_out;
    
    // Receiver signals
    wire       rx_ready;
    wire       packet_valid;
    wire [7:0] rx_data_out;
    wire       rx_data_valid;
    wire [7:0] payload_length;

    // --- Instantiate BLE Transmitter ---
    ble_tx_top tx_dut (
        .ext_clk(ext_clk),
        .rst_n(rst_n),
        .start_tx(start_tx),
        .tx_data_in(tx_data_in),
        .tx_valid_in(tx_valid_in),
        .tx_ready_out(tx_ready_out),
        .irq_tx_done(irq_tx_done),
        .rf_out(rf_out)
    );

    // --- Instantiate BLE Receiver ---
    Receiver_top rx_dut (
        .ext_clk(ext_clk),
        .rst_n(rst_n),
        .rf_in(rf_out),  // Connect TX output to RX input
        .rx_ready(rx_ready),
        .packet_valid(packet_valid),
        .rx_data_out(rx_data_out),
        .rx_data_valid(rx_data_valid),
        .payload_length(payload_length)
    );

    // --- Clock Generation ---
    initial ext_clk = 0;
    always #(SYS_PERIOD/2) ext_clk = ~ext_clk;

    // --- Helper Task: Send a byte via TX ---
    task send_byte(input [7:0] byte_val);
        begin
            @(negedge ext_clk);
            wait(tx_ready_out);
            tx_data_in = byte_val;
            tx_valid_in = 1;
            @(negedge ext_clk);
            tx_valid_in = 0;
        end
    endtask

    // --- Test Sequence ---
    initial begin
        // 1. Setup Waveform Dump
        $dumpfile("ble_system_full.vcd");
        $dumpvars(0, Receiver_top_tb);

        $display("=== BLE Transceiver System Test ===");
        $display("Transmitter connected to Receiver through RF channel");
        $display("System Clock: %0d MHz", REAL_SYS_FREQ/1000000);

        // 2. Reset Phase
        rst_n = 0;
        start_tx = 0;
        tx_valid_in = 0;
        tx_data_in = 0;
        #(SYS_PERIOD * 10);
        rst_n = 1;
        #(SYS_PERIOD * 5);

        // 3. Wait for receiver ready
        wait(rx_ready);
        $display("\n[%0t] Receiver is ready", $time);

        // 4. Start transmission
        $display("[%0t] Starting packet transmission...", $time);
        @(negedge ext_clk);
        start_tx = 1;
        @(negedge ext_clk);
        start_tx = 0;

        // 5. Wait for first tx_ready
        wait(tx_ready_out);
        $display("[%0t] TX ready for data", $time);

        // 6. Send a test packet (5 bytes payload: 0xAA, 0xBB, 0xCC, 0xDD, 0xEE)
        $display("[%0t] Sending test packet...", $time);
        send_byte(8'hAA);
        send_byte(8'hBB);
        send_byte(8'hCC);
        send_byte(8'hDD);
        send_byte(8'hEE);

        // 7. Wait for transmission to complete
        wait(irq_tx_done);
        $display("[%0t] Transmission complete (IRQ)", $time);
        #(SYS_PERIOD * 100);

        // 8. Monitor receiver for packet reception
        $display("\n[%0t] Monitoring receiver...", $time);
        
        if (packet_valid) begin
            $display("[%0t] PACKET VALID - Reception complete", $time);
            $display("Payload Length: %0d bytes", payload_length);
        end else if (rx_dut.i_parser.packet_complete) begin
            $display("[%0t] Packet received but CRC FAILED", $time);
        end

        // 9. Display received data
        $display("\n--- Received Data ---");
        if (rx_dut.i_parser.packet_complete) begin
            $display("Payload bytes: ");
            for (int i = 0; i < payload_length; i = i + 1) begin
                $display("  Byte[%0d]: 0x%02X", i, rx_dut.i_parser.payload_bytes[i]);
            end
            
            $display("Received CRC: 0x%06X", rx_dut.i_parser.crc_received);
            $display("Expected CRC: 0x%06X", tx_dut.i_crc.crc_out);
        end

        // 10. Final observation window
        #(SYS_PERIOD * 50);
        $display("\n=== BLE Transceiver Test Complete ===");
        $finish;
    end

    // --- Monitor for unexpected events ---
    always @(posedge ext_clk) begin
        if (rx_data_valid) begin
            $display("[%0t] RX Data: 0x%02X", $time, rx_data_out);
        end
    end

endmodule
