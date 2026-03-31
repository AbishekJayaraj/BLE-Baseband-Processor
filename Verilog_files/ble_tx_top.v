/**
 * @module ble_tx_top
 * @brief Top-level integration for the BLE Baseband Transmitter.
 */
module ble_tx_top (
    input  wire        ext_clk,     // 20MHz External Clock
    input  wire        rst_n,
    input  wire        start_tx,    // Pulse to begin packet
    input  wire [7:0]  tx_data_in,  // From CPU/DMA
    input  wire        tx_valid_in, // Data valid handshake
    
    output wire        tx_ready_out, // Handshake to CPU
    output wire        irq_tx_done,  // Interrupt: Packet complete
    output wire        rf_out        // Final GFSK Modulated Signal
);

    // --- Internal Interconnects ---
    wire [5:0]  channel_idx;
    wire [23:0] crc_val;
    wire        framer_serial_out;
    wire        crc_en;
    wire        white_en;
    wire        whitened_stream;

    // 1. Packet Framer (The Conductor)
    packet_framer i_framer (
        .clk(ext_clk),
        .rst_n(rst_n),
        .start_tx(start_tx),
        .tx_data_in(tx_data_in),
        .tx_valid_in(tx_valid_in),
        .crc_in(crc_val),
        .tx_ready_out(tx_ready_out),
        .irq_tx_done(irq_tx_done),
        .crc_enable(crc_en),
        .whitener_enable(white_en),
        .channel_index_out(channel_idx),
        .serial_data_out(framer_serial_out)
    );

    // 2. CRC Engine (The Guard)
    crc24_gen i_crc (
        .clk(ext_clk),
        .rst_n(rst_n),
        .enable(crc_en),
        .data_in(framer_serial_out),
        .crc_out(crc_val)
    );

    // 3. Data Whitener (The Scrambler)
    data_whitener i_whitener (
        .clk(ext_clk),
        .rst_n(rst_n),
        .lfsr_load(start_tx), // Seed LFSR when packet starts
        .enable(white_en),    // Only advance LFSR when in Header/Payload/CRC states
        .channel_index(channel_idx),
        .data_in(framer_serial_out),
        .whitened_data_out(whitened_stream)
    );

    // 4. Modulator Chain (The Radio Interface)
    // Ties the 20MHz whitened stream to the 400MHz GFSK engine
    tx_modulator_clocks i_modulator_chain (
        .ext_clk(ext_clk),
        .rst_n(rst_n),
        .whitened_data_in(whitened_stream),
        .rf_modulated_out(rf_out)
    );

endmodule