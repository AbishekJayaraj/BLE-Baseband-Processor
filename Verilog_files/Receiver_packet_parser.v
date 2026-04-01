/**
 * @module Receiver_packet_parser
 * @brief BLE Packet Parser for the Receiver
 */
module Receiver_packet_parser #(
    parameter [31:0] ACCESS_ADDR = 32'h8E89BED6,
    parameter [5:0]  CHANNEL_IDX = 6'd37
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        data_in,
    input  wire        data_valid,
    
    output reg         rx_ready,
    output reg         packet_complete,
    output reg         crc_valid,
    output reg  [7:0]  rx_data_out,
    output reg         rx_data_valid,
    output reg  [7:0]  payload_length,
    output wire [5:0]  channel_index_out
);

    localparam IDLE         = 3'd0,
               ADDR_SYNC    = 3'd1,
               HEADER_RX    = 3'd2,
               PAYLOAD_RX   = 3'd3,
               CRC_RX       = 3'd4,
               CRC_CHECK    = 3'd5,
               DONE         = 3'd6;

    reg [2:0]  state;
    reg [7:0]  bit_cnt;
    reg [7:0]  byte_cnt;
    reg [7:0]  shift_reg;
    reg [31:0] addr_shift;
    reg [23:0] crc_calc;
    reg [23:0] crc_received;
    reg [7:0]  payload_idx;

    // --- CRC24 Logic (Must match BLE spec, not CRC16) ---
    wire [23:0] crc_next;
    wire        crc_feedback;
    assign channel_index_out = CHANNEL_IDX;

    // Polynomial: x^24 + x^10 + x^9 + x^6 + x^4 + x^3 + x + 1
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            bit_cnt         <= 0;
            byte_cnt        <= 0;
            shift_reg       <= 0;
            addr_shift      <= 0;
            rx_ready        <= 1;
            packet_complete <= 0;
            crc_valid       <= 0;
            rx_data_valid   <= 0;
            crc_calc        <= 24'h555555;
            payload_length  <= 0;
        end else begin
            rx_data_valid   <= 0;
            packet_complete <= 0;
            
            if (data_valid) begin
                case (state)
                    // === 1. IDLE: Hunt for 8-bit Preamble ===
                    IDLE: begin
                        shift_reg <= {data_in, shift_reg[7:1]};
                        crc_calc  <= 24'h555555; // Keep reset until PDU starts
                        
                        if ({data_in, shift_reg[7:1]} == 8'hAA || {data_in, shift_reg[7:1]} == 8'h55) begin
                            state      <= ADDR_SYNC;
                            bit_cnt    <= 0;
                            addr_shift <= 0;
                            $display("[RX] Preamble matched: %h", {data_in, shift_reg[7:1]});
                        end
                    end

                    // === 2. ADDR_SYNC: Hunt for 32-bit Access Address ===
                    ADDR_SYNC: begin
                        addr_shift <= {data_in, addr_shift[31:1]};
                        bit_cnt    <= bit_cnt + 8'd1;
                        
                        if (bit_cnt == 31) begin
                            if ({data_in, addr_shift[31:1]} == ACCESS_ADDR) begin
                                state    <= HEADER_RX;
                                bit_cnt  <= 0;
                                byte_cnt <= 0;
                                $display("[RX] Access Address matched: %h", ACCESS_ADDR);
                            end else begin
                                state <= IDLE; // False alarm, back to hunting
                            end
                        end
                    end

                    // === 3. HEADER_RX: Capture 2 bytes ===
                    HEADER_RX: begin
                        shift_reg <= {data_in, shift_reg[7:1]};
                        crc_calc  <= crc_next; // Start CRC
                        bit_cnt   <= bit_cnt + 8'd1;
                        
                        if (bit_cnt == 7) begin
                            bit_cnt <= 0;
                            if (byte_cnt == 0) begin
                                byte_cnt <= 1;
                                $display("[RX] Header Byte 1 (Flags): %h", {data_in, shift_reg[7:1]});
                            end else begin
                                payload_length <= {data_in, shift_reg[7:1]};
                                payload_idx    <= 0;
                                state          <= PAYLOAD_RX;
                                $display("[RX] Header Byte 2 (Length): %d bytes", {data_in, shift_reg[7:1]});
                            end
                        end
                    end

                    // === 4. PAYLOAD_RX: Variable length data ===
                    PAYLOAD_RX: begin
                        shift_reg <= {data_in, shift_reg[7:1]};
                        crc_calc  <= crc_next;
                        bit_cnt   <= bit_cnt + 8'd1;
                        
                        if (bit_cnt == 7) begin
                            bit_cnt       <= 0;
                            rx_data_out   <= {data_in, shift_reg[7:1]};
                            rx_data_valid <= 1;
                            
                            if (payload_idx == (payload_length - 1)) begin
                                state   <= CRC_RX;
                                bit_cnt <= 0;
                            end else begin
                                payload_idx <= payload_idx + 8'd1;
                            end
                        end
                    end

                    // === 5. CRC_RX: Capture 24 bits ===
                    CRC_RX: begin
                        crc_received <= {data_in, crc_received[23:1]}; // LSB first shift
                        bit_cnt      <= bit_cnt + 8'd1;
                        
                        if (bit_cnt == 23) begin
                            state   <= CRC_CHECK;
                            bit_cnt <= 0;
                        end
                    end

                    // === 6. CRC_CHECK (Combinational cycle) ===
                    CRC_CHECK: begin
                        if (crc_received == crc_calc) begin
                            crc_valid <= 1;
                            $display("[RX] CRC VALID. Calculated: %h | Received: %h", crc_calc, crc_received);
                        end else begin
                            crc_valid <= 0;
                            $display("[RX] CRC INVALID. Calculated: %h | Received: %h", crc_calc, crc_received);
                        end
                        state <= DONE;
                    end

                    // === 7. DONE ===
                    DONE: begin
                        packet_complete <= 1;
                        state           <= IDLE;
                    end
                endcase
            end
        end
    end
endmodule