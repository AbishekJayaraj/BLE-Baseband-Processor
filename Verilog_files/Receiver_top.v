/**
 * @module Receiver_top
 * @brief Top-level integration for the BLE Baseband Receiver
 * @details Integrates demodulator, dewhitener, and packet parser
 */
module Receiver_top (
    input  wire        ext_clk,      // 20MHz External Clock
    input  wire        rst_n,
    input  wire        rf_in,        // Incoming GFSK modulated signal
    
    output wire        rx_ready,     // Ready to receive
    output wire        packet_valid, // Packet received (CRC passed)
    output wire [7:0]  rx_data_out,  // Received byte
    output wire        rx_data_valid,// Data valid handshake
    output wire [7:0]  payload_length // Payload length from header
);

    // --- Clock Generation (20MHz -> 400MHz) ---
    wire clk_400mhz;
    wire pll_locked;

    clock_gen_pll i_rx_pll (
        .clk_in(ext_clk),
        .reset(~rst_n),
        .clk_out(clk_400mhz),
        .locked(pll_locked)
    );

    // Hold reset for internal modules until PLL locks
    wire sys_rst_n = rst_n & pll_locked; 

    // --- Internal Interconnects ---
    wire        demod_data;
    wire        demod_valid;
    wire        dewhite_data;
    wire [5:0]  channel_idx;
    
    // --- Control signals ---
    reg         dewhite_enable;
    reg         dewhite_load;
    wire        packet_complete;
    wire        crc_valid;

    // === 1. GFSK Demodulator ===
    // Converts RF signal back to digital bit stream
    gfsk_demodulator #(
        .CLK_FREQ(400_000_000),
        .DATA_RATE(20_000_000)
    ) i_demod (
        .clk(clk_400mhz),       // Uses internal 400MHz clock
        .rst_n(sys_rst_n),
        .rf_in(rf_in),
        .data_out(demod_data),
        .data_valid(demod_valid)
    );

    // === 2. Data Dewhitener ===
    // Descrambles the received data using channel-specific LFSR
    data_dewhitener i_dewhitener (
        .clk(clk_400mhz),       // Uses internal 400MHz clock
        .rst_n(sys_rst_n),
        .lfsr_load(dewhite_load),
        .enable(dewhite_enable),
        .channel_index(channel_idx),
        .data_in(demod_data),
        .dewhitened_data_out(dewhite_data)
    );

    // === 3. Packet Parser ===
    // Extracts preamble, access address, header, payload, and CRC
    Receiver_packet_parser #(
        .ACCESS_ADDR(32'h8E89BED6),
        .CHANNEL_IDX(6'd37)
    ) i_parser (
        .clk(clk_400mhz),       // Uses internal 400MHz clock
        .rst_n(sys_rst_n),
        .data_in(dewhite_data),
        .data_valid(demod_valid),  // Pass demodulator valid signal
        .rx_ready(rx_ready),
        .packet_complete(packet_complete),
        .crc_valid(crc_valid),
        .rx_data_out(rx_data_out),
        .rx_data_valid(rx_data_valid),
        .payload_length(payload_length),
        .channel_index_out(channel_idx)
    );

    // --- Control Logic for Dewhitener ---
    always @(posedge clk_400mhz or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            dewhite_load   <= 0;
            dewhite_enable <= 0;
        end else begin
            // Load LFSR at the start of access address (State 1: ADDR_SYNC)
            dewhite_load <= (i_parser.state == 3'd1) ? 1 : 0; 
            
            // Enable dewhitener during Header (2), Payload (3), and CRC (4)
            dewhite_enable <= demod_valid && (
                (i_parser.state == 3'd2) || 
                (i_parser.state == 3'd3) || 
                (i_parser.state == 3'd4)
            );
        end
    end

    // --- Output Assignment ---
    assign packet_valid = packet_complete && crc_valid;

endmodule