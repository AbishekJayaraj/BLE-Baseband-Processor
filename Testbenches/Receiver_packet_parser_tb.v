`timescale 1ns / 1ps

module Receiver_packet_parser_tb;

    reg        clk;
    reg        rst_n;
    reg        data_in;
    reg        data_valid;

    wire        rx_ready;
    wire        packet_complete;
    wire        crc_valid;
    wire [7:0]  rx_data_out;
    wire        rx_data_valid;
    wire [7:0]  payload_length;
    wire [5:0]  channel_index_out;

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

    // --- RX Monitor Thread ---
    always @(posedge clk) begin
        if (rx_data_valid) begin
            $display("[RX THREAD] Extracted Payload Byte: %02X", rx_data_out);
        end
        if (packet_complete) begin
            $display("[RX THREAD] Packet fully parsed and passed to MAC layer!");
        end
    end

    // =========================================================
    // TESTBENCH DYNAMIC CRC ENGINE
    // =========================================================
    reg [23:0] tb_crc;
    reg crc_fb;

    // Task to send Header/Payload bytes AND calculate the CRC simultaneously
    task send_pdu_byte(input [7:0] byte_val);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                data_in = byte_val[i];
                data_valid = 1;

                // Calculate next CRC state to match the hardware LFSR
                crc_fb = byte_val[i] ^ tb_crc[0];
                tb_crc = {
                    crc_fb,               // [23]
                    tb_crc[23],           // [22]
                    tb_crc[22],           // [21]
                    tb_crc[21],           // [20]
                    tb_crc[20],           // [19]
                    tb_crc[19],           // [18]
                    tb_crc[18],           // [17]
                    tb_crc[17],           // [16]
                    tb_crc[16],           // [15]
                    tb_crc[15],           // [14]
                    tb_crc[14],           // [13]
                    tb_crc[13],           // [12]
                    tb_crc[12],           // [11]
                    tb_crc[11],           // [10]
                    tb_crc[10] ^ crc_fb,  // [9]
                    tb_crc[9]  ^ crc_fb,  // [8]
                    tb_crc[8],            // [7]
                    tb_crc[7],            // [6]
                    tb_crc[6]  ^ crc_fb,  // [5]
                    tb_crc[5],            // [4]
                    tb_crc[4]  ^ crc_fb,  // [3]
                    tb_crc[3]  ^ crc_fb,  // [2]
                    tb_crc[2],            // [1]
                    tb_crc[1]  ^ crc_fb   // [0]
                };
            end
        end
    endtask

    // Task to send the final calculated CRC
    task send_dynamic_crc();
        integer i;
        begin
            $display("[TX THREAD] Sending auto-calculated CRC: %06X", tb_crc);
            for (i = 0; i < 24; i = i + 1) begin
                @(negedge clk);
                data_in = tb_crc[i];
                data_valid = 1;
            end
        end
    endtask

    // --- Standard Helper Tasks (No CRC math needed here) ---
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

    // --- Main Test Sequence ---
    initial begin
        $dumpfile("parser_test.vcd");
        $dumpvars(0, Receiver_packet_parser_tb);

        $display("=== Starting Packet Parser Verification ===");
        rst_n = 0;
        data_in = 0;
        data_valid = 0;
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        $display("\n--- Sending Preamble (0xAA) ---");
        send_byte(8'hAA);

        $display("\n--- Sending Access Address (0x8E89BED6) ---");
        send_word(32'h8E89BED6);

        // --- Start of PDU (Protocol Data Unit) ---
        // We must initialize the CRC to the BLE default before sending the header
        tb_crc = 24'h555555; 

        $display("\n--- Sending Header ---");
        send_pdu_byte(8'h02); 
        send_pdu_byte(8'h05); 

        $display("\n--- Sending Payload ---");
        // You can change these to ANY values, and the testbench will automatically adapt!
        send_pdu_byte(8'h39);
        send_pdu_byte(8'h41);
        send_pdu_byte(8'h43);
        send_pdu_byte(8'h44);
        send_pdu_byte(8'haa);

        $display("\n--- Sending CRC ---");
        send_dynamic_crc(); 

        // Let FSM wrap up
        @(negedge clk);
        data_in = 0; 
        @(negedge clk);
        @(negedge clk);
        data_valid = 0;

        #(CLK_PERIOD * 10);
        $display("\n=== Packet Parser Verification Complete ===");
        $finish;
    end
endmodule