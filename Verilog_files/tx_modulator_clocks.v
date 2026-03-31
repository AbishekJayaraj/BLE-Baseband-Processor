/**
 * @module tx_modulator_chain
 * @brief Wrapper for the transmission chain.
 * @details Change SYS_CLK_FREQ and PLL_MULT to scale everything.
 */
module tx_modulator_clocks #(
    parameter SYS_CLK_FREQ = 20_000_000, // CHANGE THIS to 10_000_000 if needed
    parameter PLL_MULT     = 20,         // Keep this at 20 for 20x SPS
    parameter CARRIER_FREQ = 100_000_000,
    parameter DEV_FREQ     = 10_000_000
)(
    input  wire ext_clk,
    input  wire rst_n,
    input  wire whitened_data_in,
    output wire rf_modulated_out
);

    // This calculates the internal frequency used for logic math
    localparam INT_CLK_FREQ = SYS_CLK_FREQ * PLL_MULT;

    wire clk_fast;
    wire locked;

    // --- PLL Instantiation ---
    // Note: You must ensure your PLL IP multiplier matches PLL_MULT
    clock_gen_pll i_pll (
        .clk_in(ext_clk),
        .clk_out(clk_fast),
        .reset(!rst_n),
        .locked(locked)
    );

    // --- GFSK Modulator Instance ---
    gfsk_modulator #(
        .CLK_FREQ(INT_CLK_FREQ),
        .DATA_RATE(SYS_CLK_FREQ), // Data rate tied to system clock
        .CARRIER(CARRIER_FREQ),
        .DEVIATION(DEV_FREQ)
    ) i_gfsk_modulator (
        .clk(clk_fast),
        .rst_n(rst_n && locked),
        .data_in(whitened_data_in),
        .modulated_out(rf_modulated_out)
    );

endmodule