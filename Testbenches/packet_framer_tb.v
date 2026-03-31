`timescale 1ns / 1ps

module packet_framer_tb;

    // --- Signals ---
    reg        clk;
    reg        rst_n;
    reg        start_tx;
    reg [7:0]  tx_data_in;
    reg        tx_valid_in;
    reg [23:0] crc_in;
    
    wire       tx_ready_out;
    wire       irq_tx_done;
    wire       crc_enable;
    wire       whitener_enable;
    wire [5:0] channel_index_out;
    wire       serial_data_out;

    // --- Instantiate the Framer ---
    packet_framer #(
        .ACCESS_ADDR(32'h8E89BED6)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_tx(start_tx),
        .tx_data_in(tx_data_in),
        .tx_valid_in(tx_valid_in),
        .crc_in(crc_in),
        .tx_ready_out(tx_ready_out),
        .irq_tx_done(irq_tx_done),
        .crc_enable(crc_enable),
        .whitener_enable(whitener_enable),
        .channel_index_out(channel_index_out),
        .serial_data_out(serial_data_out)
    );

    // --- Clock Generation (20MHz) ---
    initial clk = 0;
    always #25 clk = ~clk;

    // --- Test Procedure ---
    initial begin
        $dumpfile("framer_test.vcd");
        $dumpvars(0, packet_framer_tb);

        // 1. Initialize
        rst_n = 0;
        start_tx = 0;
        tx_data_in = 0;
        tx_valid_in = 0;
        crc_in = 24'hABCDEF; // Mock CRC value
        
        #100 rst_n = 1;
        #100;

        // 2. Start Transmission
        @(posedge clk);
        start_tx = 1;
        @(posedge clk);
        start_tx = 0;

        // 3. Simulate Host Feeding Data (PDU Header + 3 Bytes Payload)
        // Header Byte 1: Type
        feed_byte(8'h02); 
        // Header Byte 2: Length (3 bytes)
        feed_byte(8'h03); 
        
        // Payload Bytes
        feed_byte(8'hDE);
        feed_byte(8'hAD);
        feed_byte(8'hBE);

        // 4. Wait for Completion
        wait(irq_tx_done);
        #200;
        
        $display("--- Framer Test Complete ---");
        $finish;
    end

    // --- Task: Simulate a CPU feeding a byte with Handshake ---
    task feed_byte(input [7:0] data);
        begin
            // Wait until Framer is ready
            while (!tx_ready_out) @(posedge clk);
            
            // Apply data and valid signal
            tx_data_in = data;
            tx_valid_in = 1;
            
            // Wait for Framer to consume data
            @(posedge clk);
            while (tx_ready_out) @(posedge clk);
            
            tx_valid_in = 0;
            $display("[%0t] CPU Fed Byte: 0x%h", $time, data);
        end
    endtask

endmodule