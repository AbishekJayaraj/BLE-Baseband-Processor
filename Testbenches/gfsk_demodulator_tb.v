`timescale 1ns / 1ps

module gfsk_demodulator_tb;

    reg ext_clk;
    reg rst_n;
    reg tx_bit; // Data fed into modulator
    
    wire rf_modulated;
    wire demod_data;
    wire demod_valid;

    // --- Modulator Instance ---
    tx_modulator_clocks #(
        .SYS_CLK_FREQ(20_000_000),
        .PLL_MULT(20),
        .CARRIER_FREQ(100_000_000),
        .DEV_FREQ(10_000_000)
    ) modulator (
        .ext_clk(ext_clk),
        .rst_n(rst_n),
        .whitened_data_in(tx_bit),
        .rf_modulated_out(rf_modulated)
    );

    // --- DDC Demodulator Instance ---
    gfsk_demodulator #(
        .CLK_FREQ(400_000_000),
        .DATA_RATE(20_000_000)
    ) demodulator (
        .clk(modulator.clk_fast), 
        .rst_n(rst_n),
        .rf_in(rf_modulated),
        .data_out(demod_data),
        .data_valid(demod_valid)
    );

    initial ext_clk = 0;
    always #25 ext_clk = ~ext_clk; // 20MHz clock

    integer i;

   // ==========================================
    // TRANSMITTER THREAD
    // ==========================================
    initial begin
        $dumpfile("gfsk_ddc_test.vcd");
        $dumpvars(0, gfsk_demodulator_tb);
        
        rst_n = 0;
        tx_bit = 0;
        #200 rst_n = 1;
        wait(modulator.locked == 1);
        
        // FIX: Align the testbench to the physical clock edge
        @(posedge ext_clk); 

        $display("\n[TX] Sending Preamble to lock Receiver CDR...");
        for(i = 0; i < 10; i = i + 1) begin
            tx_bit = i % 2; 
            @(posedge ext_clk); // Wait exactly 1 clock cycle (50ns)
        end

        $display("\n[TX] Sending Payload: 1 - 0 - 1 - 1 - 0");
        tx_bit = 1; @(posedge ext_clk);
        tx_bit = 0; @(posedge ext_clk);
        tx_bit = 1; @(posedge ext_clk);
        tx_bit = 1; @(posedge ext_clk);
        tx_bit = 0; @(posedge ext_clk);

        tx_bit = 0; 
        #(500); 
        $display("\n=== Testbench Finished ===");
        $finish;
    end

    // ==========================================
    // RECEIVER THREAD (Independent)
    // ==========================================
    integer rx_count = 0;
    always @(posedge demod_valid) begin
        // Ignore the first few preamble bits while the CDR locks
        if (rx_count > 6) begin
            $display("[RX TIME: %0t] Recovered Bit: %b", $time, demod_data);
        end
        rx_count = rx_count + 1;
    end

endmodule