/**
 * @module packet_framer
 * @brief ASIC-ready BLE Packet Framer with Dynamic Length Tracking.
 */
module packet_framer #(
    parameter [31:0] ACCESS_ADDR = 32'h8E89BED6, // Advertising Access Address
    parameter [5:0]  CHANNEL_IDX = 6'd37         // Default Adv Channel
)(
    input  wire        clk,               // 20MHz System Clock
    input  wire        rst_n,
    input  wire        start_tx,          // Pulse to start packet
    input  wire [7:0]  tx_data_in,        // From CPU/DMA
    input  wire        tx_valid_in,       // Data valid handshake
    input  wire [23:0] crc_in,            // From CRC Engine
    
    output reg         tx_ready_out,      // Handshake to CPU
    output reg         irq_tx_done,       // Interrupt: Packet complete
    output reg         crc_enable,        // Enable CRC block
    output reg         whitener_enable,   // Enable Whitener block
    output wire [5:0]  channel_index_out, // For Whitener seed
    output reg         serial_data_out    // To Whitener/Modulator
);

    // --- State Encoding (7 States) ---
    localparam IDLE         = 3'd0,
               PREAMBLE     = 3'd1,
               ADDR         = 3'd2,
               HEADER       = 3'd3,
               PAYLOAD      = 3'd4,
               CRC_SUM      = 3'd5,
               DONE         = 3'd6;

    reg [2:0] state;
    reg [5:0] bit_cnt;       // Counts bits within fields
    reg [7:0] byte_cnt;      // Counts total bytes in PDU
    reg [7:0] packet_length; // Captured from 2nd byte of PDU
    reg [7:0] shift_reg;     // Serialization buffer

    assign channel_index_out = CHANNEL_IDX;

    // --- FSM Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            bit_cnt         <= 0;
            byte_cnt        <= 0;
            packet_length   <= 0;
            tx_ready_out    <= 0;
            irq_tx_done     <= 0;
            crc_enable      <= 0;
            whitener_enable <= 0;
            serial_data_out <= 0;
            shift_reg       <= 0;
        end else begin
            case (state)
                
                // 1. IDLE: Wait for start command
                IDLE: begin
                    irq_tx_done <= 0;
                    if (start_tx) begin
                        state   <= PREAMBLE;
                        bit_cnt <= 0;
                    end
                end

                // 2. PREAMBLE: Send fixed 8'hAA (LSB first: 01010101)
                PREAMBLE: begin
                    serial_data_out <= bit_cnt[0]; 
                    if (bit_cnt == 7) begin
                        state   <= ADDR;
                        bit_cnt <= 0;
                    end else bit_cnt <= bit_cnt + 1'b1;
                end

                // 3. ACCESS_ADDR: Send 32-bit address (No Whitening/CRC)
                ADDR: begin
                    serial_data_out <= ACCESS_ADDR[bit_cnt[4:0]];
                    if (bit_cnt == 31) begin
                        state        <= HEADER;
                        bit_cnt      <= 0;
                        tx_ready_out <= 1; // Request first byte of PDU
                    end else bit_cnt <= bit_cnt + 1'b1;
                end

                // 4. HEADER: Send 16-bit PDU Header (Whitening & CRC Start)
                HEADER: begin
                    whitener_enable <= 1;
                    crc_enable      <= 1;

                    if (tx_valid_in && tx_ready_out) begin
                        shift_reg    <= tx_data_in;
                        tx_ready_out <= 0; // Buffer full
                        // Capture length byte (2nd byte of Header)
                        if (byte_cnt == 1) packet_length <= tx_data_in;
                    end

                    serial_data_out <= (tx_valid_in && tx_ready_out) ? tx_data_in[0] : shift_reg[bit_cnt[2:0]];
                    
                    if (bit_cnt == 7) begin
                        bit_cnt <= 0;
                        tx_ready_out <= 1;
                        if (byte_cnt == 1) begin
                            state <= PAYLOAD;
                            byte_cnt <= 0; // Reset for payload count
                        end else byte_cnt <= byte_cnt + 1'b1;
                    end else bit_cnt <= bit_cnt + 1'b1;
                end

                // 5. PAYLOAD: Send actual data based on captured packet_length
                PAYLOAD: begin
                    if (tx_valid_in && tx_ready_out) begin
                        shift_reg    <= tx_data_in;
                        tx_ready_out <= 0;
                    end

                    serial_data_out <= (tx_valid_in && tx_ready_out) ? tx_data_in[0] : shift_reg[bit_cnt[2:0]];

                    if (bit_cnt == 7) begin
                        bit_cnt <= 0;
                        tx_ready_out <= 1;
                        // End of payload detection
                        if (byte_cnt == (packet_length - 1)) begin
                            state      <= CRC_SUM;
                            crc_enable <= 0; // Freeze CRC engine
                        end else byte_cnt <= byte_cnt + 1'b1;
                    end else bit_cnt <= bit_cnt + 1'b1;
                end

                // 6. CRC_SUM: Send 24-bit calculated CRC (Whitened)
                CRC_SUM: begin
                    tx_ready_out    <= 0;
                    serial_data_out <= crc_in[bit_cnt[4:0]];
                    if (bit_cnt == 23) begin
                        state           <= DONE;
                        whitener_enable <= 0;
                    end else bit_cnt    <= bit_cnt + 1'b1;
                end

                // 7. DONE: Cleanup and notify CPU
                DONE: begin
                    irq_tx_done     <= 1;
                    serial_data_out <= 0;
                    state           <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule