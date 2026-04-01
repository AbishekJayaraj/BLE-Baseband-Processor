/**
 * @module Receiver_packet_parser
 * @brief BLE Packet Parser for the Receiver
 * @details Synchronizes to preamble, detects access address, extracts header/payload/CRC
 */
module Receiver_packet_parser #(
    parameter [31:0] ACCESS_ADDR = 32'h8E89BED6, // Advertising Access Address
    parameter [5:0]  CHANNEL_IDX = 6'd37         // Default Adv Channel
)(
    input  wire        clk,                // 20MHz System Clock
    input  wire        rst_n,
    input  wire        data_in,            // Dewhitened serial data
    input  wire        data_valid,         // Data valid pulse from demodulator
    
    output reg         rx_ready,           // Ready to receive data
    output reg         packet_complete,    // New packet received
    output reg         crc_valid,          // CRC check passed
    output reg  [7:0]  rx_data_out,        // Received byte output
    output reg         rx_data_valid,      // Received byte is valid
    output reg  [7:0]  payload_length,     // Length from header
    output wire [5:0]  channel_index_out   // For dewhitener seed
);

    // --- State Machine ---
    localparam IDLE         = 4'd0,
               PREAMBLE_SYNC = 4'd1,
               ADDR_SYNC    = 4'd2,
               HEADER_RX    = 4'd3,
               PAYLOAD_RX   = 4'd4,
               CRC_RX       = 4'd5,
               CRC_CHECK    = 4'd6,
               DONE         = 4'd7;

    reg [3:0]   state;
    reg [7:0]   bit_cnt;           // Bit counter (0-7)
    reg [7:0]   byte_cnt;          // Byte counter
    reg [7:0]   shift_reg;         // Deserializer
    reg [31:0]  addr_shift;        // 32-bit address buffer
    reg [23:0]  crc_calc;          // Calculated CRC
    reg [23:0]  crc_received;      // Received CRC
    reg [7:0]   preamble_cnt;      // Count preamble bytes
    reg [7:0]   header_byte[1:0];  // Storage for 2-byte header
    reg [7:0]   payload_bytes [255:0]; // Payload buffer (max 255 bytes)
    reg [7:0]   payload_idx;       // Current payload position
    
    // CRC calculation signals
    wire [23:0] crc_next;
    wire        crc_feedback;

    assign channel_index_out = CHANNEL_IDX;

    // --- CRC16 Checker (same polynomial as transmitter) ---
    assign crc_feedback = data_in ^ crc_calc[0];
    assign crc_next[0]  = crc_calc[1]  ^ crc_feedback;
    assign crc_next[1]  = crc_calc[2];
    assign crc_next[2]  = crc_calc[3]  ^ crc_feedback;
    assign crc_next[3]  = crc_calc[4]  ^ crc_feedback;
    assign crc_next[4]  = crc_calc[5];
    assign crc_next[5]  = crc_calc[6]  ^ crc_feedback;
    assign crc_next[6]  = crc_calc[7];
    assign crc_next[7]  = crc_calc[8];
    assign crc_next[8]  = crc_calc[9]  ^ crc_feedback;
    assign crc_next[9]  = crc_calc[10] ^ crc_feedback;
    assign crc_next[10] = crc_calc[11];
    assign crc_next[11] = crc_calc[12];
    assign crc_next[12] = crc_calc[13];
    assign crc_next[13] = crc_calc[14];
    assign crc_next[14] = crc_calc[15];
    assign crc_next[15] = crc_calc[16];
    assign crc_next[16] = crc_calc[17];
    assign crc_next[17] = crc_calc[18];
    assign crc_next[18] = crc_calc[19];
    assign crc_next[19] = crc_calc[20];
    assign crc_next[20] = crc_calc[21];
    assign crc_next[21] = crc_calc[22];
    assign crc_next[22] = crc_calc[23];
    assign crc_next[23] = crc_feedback;

    // --- FSM Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            bit_cnt         <= 0;
            byte_cnt        <= 0;
            shift_reg       <= 0;
            addr_shift      <= 0;
            preamble_cnt    <= 0;
            rx_ready        <= 1;
            packet_complete <= 0;
            crc_valid       <= 0;
            rx_data_valid   <= 0;
            crc_calc        <= 24'h555555; // CRC initialization
            payload_length  <= 0;
        end else begin
            
            // Default outputs
            rx_data_valid   <= 0;
            packet_complete <= 0;
            
            case (state)
                
                // === IDLE: Wait for preamble ===
                IDLE: begin
                    rx_ready    <= 1;
                    crc_calc    <= 24'h555555;
                    preamble_cnt <= 0;
                    
                    if (data_valid) begin
                        shift_reg <= {data_in, shift_reg[7:1]};
                        bit_cnt <= bit_cnt + 1;
                        
                        // Check for preamble pattern (0xAA = 10101010)
                        if (bit_cnt == 7) begin
                            if (shift_reg == 8'hAA) begin
                                state <= PREAMBLE_SYNC;
                                preamble_cnt <= 1;
                                $display("[RX] Preamble detected at time %0t", $time);
                            end
                            bit_cnt <= 0;
                        end
                    end
                end

                // === PREAMBLE_SYNC: Confirm preamble pattern ===
                PREAMBLE_SYNC: begin
                    if (data_valid) begin
                        shift_reg <= {data_in, shift_reg[7:1]};
                        bit_cnt <= bit_cnt + 1;
                        
                        if (bit_cnt == 7) begin
                            if (shift_reg == 8'hAA) begin
                                // Valid preamble, move to address sync
                                state <= ADDR_SYNC;
                                addr_shift <= 0;
                                byte_cnt <= 0;
                                bit_cnt <= 0;
                                $display("[RX] Preamble confirmed, syncing to access address");
                            end else begin
                                // No valid preamble, return to IDLE
                                state <= IDLE;
                                bit_cnt <= 0;
                            end
                        end
                    end
                end

                // === ADDR_SYNC: Detect 32-bit access address ===
                ADDR_SYNC: begin
                    if (data_valid) begin
                        addr_shift <= {data_in, addr_shift[31:1]};
                        bit_cnt <= bit_cnt + 1;
                        
                        if (bit_cnt == 31) begin
                            if (addr_shift == ACCESS_ADDR) begin
                                // Address matched!
                                state <= HEADER_RX;
                                byte_cnt <= 0;
                                bit_cnt <= 0;
                                $display("[RX] Access address matched: 0x%08X", ACCESS_ADDR);
                            end else begin
                                // No address match, return to IDLE
                                state <= IDLE;
                                bit_cnt <= 0;
                            end
                        end
                    end
                end

                // === HEADER_RX: Receive 2-byte header ===
                HEADER_RX: begin
                    if (data_valid) begin
                        shift_reg <= {data_in, shift_reg[7:1]};
                        bit_cnt <= bit_cnt + 1;
                        
                        // Update CRC during header
                        crc_calc <= crc_next;
                        
                        if (bit_cnt == 7) begin
                            // Complete byte received
                            header_byte[byte_cnt] <= shift_reg;
                            
                            if (byte_cnt == 1) begin
                                // Extract length from 2nd header byte
                                payload_length <= shift_reg;
                                state <= PAYLOAD_RX;
                                byte_cnt <= 0;
                                payload_idx <= 0;
                                $display("[RX] Header received, payload length: %d bytes", shift_reg);
                            end else begin
                                byte_cnt <= byte_cnt + 1;
                            end
                            bit_cnt <= 0;
                        end
                    end
                end

                // === PAYLOAD_RX: Receive payload ===
                PAYLOAD_RX: begin
                    if (data_valid) begin
                        shift_reg <= {data_in, shift_reg[7:1]};
                        bit_cnt <= bit_cnt + 1;
                        
                        // Update CRC during payload
                        crc_calc <= crc_next;
                        
                        if (bit_cnt == 7) begin
                            payload_bytes[payload_idx] <= shift_reg;
                            rx_data_out <= shift_reg;
                            rx_data_valid <= 1;
                            
                            if (payload_idx == (payload_length - 1)) begin
                                // All payload received, expect CRC
                                state <= CRC_RX;
                                byte_cnt <= 0;
                            end else begin
                                payload_idx <= payload_idx + 1;
                            end
                            bit_cnt <= 0;
                        end
                    end
                end

                // === CRC_RX: Receive 24-bit CRC ===
                CRC_RX: begin
                    if (data_valid) begin
                        crc_received[bit_cnt] <= data_in;
                        bit_cnt <= bit_cnt + 1;
                        
                        if (bit_cnt == 23) begin
                            // All CRC bits received
                            state <= CRC_CHECK;
                            bit_cnt <= 0;
                            $display("[RX] CRC received: 0x%06X | Calculated: 0x%06X", crc_received, crc_calc);
                        end
                    end
                end

                // === CRC_CHECK: Verify CRC ===
                CRC_CHECK: begin
                    if (crc_received == crc_calc) begin
                        crc_valid <= 1;
                        $display("[RX] CRC VALID - Packet accepted");
                    end else begin
                        crc_valid <= 0;
                        $display("[RX] CRC INVALID - Packet rejected");
                    end
                    
                    state <= DONE;
                end

                // === DONE: Signal completion ===
                DONE: begin
                    packet_complete <= 1;
                    state <= IDLE;
                    $display("[RX] Packet reception complete at time %0t", $time);
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
