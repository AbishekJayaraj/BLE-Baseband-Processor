/**
 * @module gfsk_mod
 * @brief Parameterized GFSK Modulator
 * @details Change the parameters at the top to scale the entire design.
 */
module gfsk_modulator #(
    parameter CLK_FREQ  = 400_000_000, // Internal high-speed clock rate
    parameter DATA_RATE = 20_000_000,  // Data rate (matches your sys_clk)
    parameter CARRIER   = 100_000_000, // Target carrier frequency
    parameter DEVIATION = 10_000_000   // Frequency shift for 0 vs 1
)(
    input  wire clk,         // High-speed clock from PLL
    input  wire rst_n,
    input  wire data_in,     // Data arrives at DATA_RATE speed
    output reg  modulated_out
);

    // --- Automatic Math (Computed at Synthesis) ---
    // SPS: Samples Per Symbol (e.g., 400MHz / 20Mbps = 20)
    localparam SPS = CLK_FREQ / DATA_RATE; 
    
    // NCO Tuning Words: (Target_Freq * 2^8) / CLK_FREQ
    localparam [7:0] M_CENTER = (CARRIER * 256) / CLK_FREQ;
    localparam [7:0] M_DEV    = (DEVIATION * 256) / CLK_FREQ;

    // --- Internal Registers ---
    reg [7:0] phase_acc;    // 8-bit Phase Accumulator
    reg [7:0] sample_cnt;   // Tracks samples per bit (0 to SPS-1)
    reg [2:0] shift_reg;    // History for Gaussian smoothing
    reg [7:0] m_current;    // Instantaneous frequency step

    // --- Gaussian Smoothing Logic ---
    // Divides the SPS window into 4 quadrants to ramp the frequency
    always @(*) begin
        case (shift_reg)
            3'b001: begin // Rising Transition
                if      (sample_cnt < (SPS/4))   m_current = M_CENTER - (M_DEV/2);
                else if (sample_cnt < (SPS/2))   m_current = M_CENTER;
                else if (sample_cnt < (3*SPS/4)) m_current = M_CENTER + (M_DEV/2);
                else                             m_current = M_CENTER + M_DEV;
            end
            3'b110: begin // Falling Transition
                if      (sample_cnt < (SPS/4))   m_current = M_CENTER + (M_DEV/2);
                else if (sample_cnt < (SPS/2))   m_current = M_CENTER;
                else if (sample_cnt < (3*SPS/4)) m_current = M_CENTER - (M_DEV/2);
                else                             m_current = M_CENTER - M_DEV;
            end
            3'b111:  m_current = M_CENTER + M_DEV; // Logic 1
            3'b000:  m_current = M_CENTER - M_DEV; // Logic 0
            default: m_current = M_CENTER;
        endcase
    end

    // --- Sequential Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc     <= 8'h00;
            sample_cnt    <= 8'h00;
            shift_reg     <= 3'b000;
            modulated_out <= 1'b0;
        end else begin
            // 1. Bit Timing
            if (sample_cnt >= (SPS - 1)) begin
                sample_cnt  <= 8'h00;
                shift_reg   <= {shift_reg[1:0], data_in};
            end else begin
                sample_cnt  <= sample_cnt + 8'd1;
            end

            // 2. NCO Phase Accumulation
            phase_acc <= phase_acc + m_current;

            // 3. Bitstream Output
            modulated_out <= phase_acc[7];
        end
    end
endmodule