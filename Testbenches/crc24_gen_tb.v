`timescale 1ns / 1ps

module tb_crc24_gen;

    // --- Internal Signals ---
    reg        clk;
    reg        rst_n;
    reg        enable;
    reg        data_in;
    wire [23:0] crc_out;

    // --- Instantiate the Device Under Test (DUT) ---
    crc24_gen uut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .data_in(data_in),
        .crc_out(crc_out)
    );

    // --- Clock Generator ---
    parameter CLK_PERIOD = 50;
    always begin
        clk = 0; #(CLK_PERIOD / 2);
        clk = 1; #(CLK_PERIOD / 2);
    end

    // --- Helper Task (defined at module level) ---
    task send_bit;
        input bit_to_send;
        begin
            @(negedge clk);
            enable = 1;
            data_in = bit_to_send;
            @(posedge clk);
            #1;
            enable = 0;
        end
    endtask

    // --- Test Sequence ---
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_crc24_gen);

        $display("Starting simulation...");
        rst_n = 0;
        enable = 0;
        data_in = 0;
        #(CLK_PERIOD * 2);
        
        rst_n = 1;
        #(CLK_PERIOD);
        $display("Reset released. CRC should be 555555. Is: %h", crc_out);

        #(CLK_PERIOD * 2);

        // 4. Send 8-bit PDU: 8'hAB = 10101011
        // **Must be sent LSB-first: 11010101**
        $display("Sending 8-bit PDU 8'hAB (LSB-first: 11010101)");

        // 5. Send all 8 bits (LSB-first)
        send_bit(1); // Bit 0
        send_bit(1); // Bit 1
        send_bit(0); // Bit 2
        send_bit(1); // Bit 3
        send_bit(0); // Bit 4
        send_bit(1); // Bit 5
        send_bit(0); // Bit 6
        send_bit(1); // Bit 7 (MSB)
        
        @(negedge clk);
        enable = 0;
        data_in = 0;
        
        #(CLK_PERIOD * 2);
        
        // 6. Check Final Result
        // The correct LSB-first result for 8'hAB is 9902f7
        $display("PDU sent. Final CRC: %h (Expected: fa577e)", crc_out);

        // 7. Finish simulation
        $display("Simulation complete.");
        $finish;
    end

endmodule