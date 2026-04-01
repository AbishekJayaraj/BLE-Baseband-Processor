/**
 * @module gfsk_demodulator
 * @brief Digital Down Conversion (DDC) I/Q Demodulator
 */
module gfsk_demodulator #(
    parameter CLK_FREQ  = 400_000_000,
    parameter DATA_RATE = 20_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire rf_in,
    output reg  data_out,
    output reg  data_valid
);

    localparam SPS = CLK_FREQ / DATA_RATE; // 20 samples per bit

    // --- 1. Local Oscillator & Mixer ---
    reg [1:0] nco_phase;
    wire signed [1:0] rf_bipolar = rf_in ? 2'sd1 : -2'sd1;
    reg  signed [1:0] i_mix, q_mix;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) nco_phase <= 0;
        else        nco_phase <= nco_phase + 1;
    end

    // Multiply RF by local 100MHz Cosine and Sine
    always @(*) begin
        case(nco_phase)
            2'b00: begin i_mix =  rf_bipolar; q_mix =  2'sd0;      end
            2'b01: begin i_mix =  2'sd0;      q_mix =  rf_bipolar; end
            2'b10: begin i_mix = -rf_bipolar; q_mix =  2'sd0;      end
            2'b11: begin i_mix =  2'sd0;      q_mix = -rf_bipolar; end
        endcase
    end

    // --- 2. Low Pass Filter (Moving Average) ---
    reg signed [1:0] i_hist [0:19];
    reg signed [1:0] q_hist [0:19];
    reg signed [6:0] i_sum, q_sum; // Integrates up to +/- 20
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_sum <= 0; q_sum <= 0;
            for(i=0; i<20; i=i+1) begin i_hist[i] <= 0; q_hist[i] <= 0; end
        end else begin
            i_hist[0] <= i_mix;
            q_hist[0] <= q_mix;
            for(i=1; i<20; i=i+1) begin
                i_hist[i] <= i_hist[i-1];
                q_hist[i] <= q_hist[i-1];
            end
            i_sum <= i_sum + i_mix - i_hist[19];
            q_sum <= q_sum + q_mix - q_hist[19];
        end
    end

// --- 3. FM Discriminator (Cross Product) ---
    // Delta Phase = I[n-1]*Q[n] - I[n]*Q[n-1]
    reg signed [6:0] i_sum_d, q_sum_d;
    wire signed [13:0] cross_product;
    reg data_out_raw;

    assign cross_product = (i_sum_d * q_sum) - (i_sum * q_sum_d);

    always @(posedge clk) begin
        i_sum_d <= i_sum;
        q_sum_d <= q_sum;
        
        // FIX: 110MHz rotates phase such that cross product is negative
        if (cross_product < 0) data_out_raw <= 1;
        else if (cross_product > 0) data_out_raw <= 0;
        // If exactly 0, hold the previous state
    end

    // --- 4. Clock Data Recovery (CDR) ---
    reg [4:0] cdr_cnt;
    reg data_out_raw_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdr_cnt <= 0;
            data_valid <= 0;
            data_out <= 0;
        end else begin
            data_out_raw_d <= data_out_raw;
            
            // Sync to data transitions
            if (data_out_raw ^ data_out_raw_d) begin
                cdr_cnt <= 0; 
            end else if (cdr_cnt == 19) begin
                cdr_cnt <= 0; // Wrap around for long identical bits
            end else begin
                cdr_cnt <= cdr_cnt + 1;
            end

            // Sample precisely in the middle of the 'Eye'
            if (cdr_cnt == 10) begin
                data_valid <= 1;
                data_out   <= data_out_raw;
            end else begin
                data_valid <= 0;
            end
        end
    end
endmodule