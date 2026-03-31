/**
 * @module crc24_gen
 * @brief Implements the BLE 24-bit CRC
 */
module crc24_gen (
    clk,
    rst_n,
    enable,
    data_in,
    crc_out
);

    // --- Port Declarations ---
    input        clk;
    input        rst_n;
    input        enable;
    input        data_in;
    output [23:0] crc_out;

    // --- Internal Signals ---
    reg [23:0] crc_out;
    reg [23:0] crc_next;
    reg        feedback;

    localparam [23:0] CRC_INIT = 24'h555555;

    // --- Process 1: Combinational Logic (Calculator) ---
    // This logic implements the LSB-first CRC calculation.
 always @(*) begin
        
        // 1. Feedback bit is input XOR'd with the LSB
        feedback = data_in ^ crc_out[0]; 

        // 2. The register shifts RIGHT, with feedback XOR'd at the taps.
        // Polynomial: x^24 + x^10 + x^9 + x^6 + x^4 + x^3 + x + 1
        // Taps: 24, 10, 9, 6, 4, 3, 1, 0
        
        crc_next[0]  = crc_out[1]  ^ feedback; // Tap x^1
        crc_next[1]  = crc_out[2];
        crc_next[2]  = crc_out[3]  ^ feedback; // Tap x^3
        crc_next[3]  = crc_out[4]  ^ feedback; // Tap x^4
        crc_next[4]  = crc_out[5];
        crc_next[5]  = crc_out[6]  ^ feedback; // Tap x^6
        crc_next[6]  = crc_out[7];
        crc_next[7]  = crc_out[8];
        crc_next[8]  = crc_out[9]  ^ feedback; // Tap x^9
        crc_next[9]  = crc_out[10] ^ feedback; // Tap x^10
        crc_next[10] = crc_out[11];
        crc_next[11] = crc_out[12];
        crc_next[12] = crc_out[13];
        crc_next[13] = crc_out[14];
        crc_next[14] = crc_out[15];
        crc_next[15] = crc_out[16];
        crc_next[16] = crc_out[17];
        crc_next[17] = crc_out[18];
        crc_next[18] = crc_out[19];
        crc_next[19] = crc_out[20];
        crc_next[20] = crc_out[21];
        crc_next[21] = crc_out[22];
        crc_next[22] = crc_out[23];
        crc_next[23] = feedback;             // Tap x^24
    end
    // --- Process 2: Sequential Logic (Memory) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_out <= CRC_INIT;
        end else if (enable) begin
            crc_out <= crc_next;
        end
    end

endmodule