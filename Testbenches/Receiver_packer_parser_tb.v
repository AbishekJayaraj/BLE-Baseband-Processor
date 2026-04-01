`timescale 1ns / 1ps

module Receiver_packer_parser_tb;

    // --- Inputs ---
    reg        clk;
    reg        rst_n;
    reg        data_in;
    reg        data_valid;

    // --- Outputs ---
    wire       rx_ready;
    wire       packet_complete;
    wire       crc_valid;
    wire [7:0] rx_data_out;
    wire       rx_data_valid;
    wire [7:0] payload_length;
    wire [5:0] channel_index_out;

    // --- Instantiate the Packet Parser ---
    Receiver_packet_parser #(
        .ACCESS_ADDR(32'h8E89BED6),
        .CHANNEL_IDX(6'd37)
    ) uut_parser (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_valid(data_valid),
        .rx_ready(rx_ready),
        .packet_complete(packet_complete),
        .crc_valid(crc_valid),
        .rx_data_out(rx_data_out),
        .rx_data_valid(rx_data_valid),
        .payload_length(payload_length),
        .channel_index_out(channel_index_out)
    );

    // --- Clock Generator (20MHz -> 50ns period) ---
    parameter CLK_PERIOD = 50;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Task: Send a bit stream ---
    task send_bit_stream(input [127:0] stream, input integer num_bits);
        integer i;
        begin
            for (i = 0; i < num_bits; i = i + 1) begin
                @(negedge clk);
                data_in = stream[i];
                data_valid = 1;
            end
            data_valid = 0;
        end
    endtask

    // --- Helper Task: Send a byte (LSB first) ---
    task send_byte(input [7:0] byte_val);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                data_in = byte_val[i];
                data_valid = 1;
            end
        end
    endtask

    // --- Helper Task: Send a 32-bit word (LSB first) ---
    task send_word(input [31:0] word_val);
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) begin
                @(negedge clk);
                data_in = word_val[i];
                data_valid = 1;
            end
        end
    endtask

    // --- Test Sequence ---
    initial begin
        // 1. Setup Waveform Dump
        $dumpfile("parser_test.vcd");
        $dumpvars(0, Receiver_packer_parser_tb);

        // 2. Initialization & Reset
        $display("=== Starting Packet Parser Verification ===");
        rst_n = 0;
        data_in = 0;
        data_valid = 0;
        #(CLK_PERIOD * 2);
        
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // 3. Test 1: Send Valid Preamble
        $display("\n--- Test 1: Sending valid preamble (0xAA) ---");
        send_byte(8'hAA);
        
        wait(uut_parser.state != 4'd0);
        $display("Preamble detected, state changed to %0d", uut_parser.state);
        
        // Confirm with another 0xAA
        send_byte(8'hAA);
        #(CLK_PERIOD * 5);

        // 4. Test 2: Send Access Address
        $display("\n--- Test 2: Sending access address (0x8E89BED6) ---");
        send_word(32'h8E89BED6);
        
        wait(uut_parser.state > 4'd2);
        $display("Access address matched, state changed to %0d", uut_parser.state);
        #(CLK_PERIOD * 5);

        // 5. Test 3: Send Header (flags + length)
        $display("\n--- Test 3: Sending header (2 bytes) ---");
        send_byte(8'h02);  // Flags byte
        send_byte(8'h05);  // Length = 5 bytes payload
        
        wait(rx_data_valid);
        $display("First header byte received: 0x%02X", rx_data_out);
        
        @(rx_data_valid);
        $display("Second header byte received: 0x%02X (Length=%0d)", rx_data_out, payload_length);
        #(CLK_PERIOD * 5);

        // 6. Test 4: Send Payload
        $display("\n--- Test 4: Sending payload (5 bytes) ---");
        send_byte(8'h11);
        send_byte(8'h22);
        send_byte(8'h33);
        send_byte(8'h44);
        send_byte(8'h55);
        
        repeat (5) @(rx_data_valid);
        $display("All payload bytes received");
        #(CLK_PERIOD * 5);

        // 7. Test 5: Send CRC
        $display("\n--- Test 5: Sending CRC (24 bits) ---");
        // For this test, we'll send some dummy CRC
        // In reality, this should be calculated
        send_bit_stream(128'h123456, 24);  // Dummy CRC
        
        wait(packet_complete);
        $display("Packet reception complete");
        $display("CRC Valid: %b", crc_valid);
        #(CLK_PERIOD * 10);

        $display("\n=== Packet Parser Verification Complete ===");
        $finish;
    end

endmodule
