/**
This is the file that performs Data whitening on the PDU as well as the 24 bit CRC
Data whitening is an important process that helps in randomizing the data for better transmissison
Data whitening is done using LFSR wher the initial sequence is derived from the transmission channel index
*/

module data_whitener(
    clk,
    rst_n,
    lfsr_load,          // <-- Added this critical control signal
    enable,
    channel_index,
    data_in,
    whitened_data_out
);
   
   // --- Port Declarations ---
   input        clk;
   input        rst_n;
   input        lfsr_load;      // Pulse to load the channel value
   input        enable;         // Pulse to advance the LFSR
   input  [5:0] channel_index;
   input        data_in;
   output       whitened_data_out; // This is a 1-bit wire

   // --- Internal Signals ---
   reg  [6:0]    lfsr;           // The 7-bit LFSR register
   wire [6:0]    lfsr_seed;    // The 7-bit seed (from channel_index)
   wire [6:0]    lfsr_next;    // The next combinational value for the LFSR
   wire          lfsr_out_bit; // The LSB of the LFSR, used for whitening

   // --- Combinational Logic (The "Calculator") ---

   // 1. Create the 7-bit seed from the 6-bit channel index

   assign lfsr_seed = {channel_index, 1'b0};

   // 2. Define the LFSR's next-state logic (the polynomial)
   //    Polynomial: x^7 + x^4 + 1
   //    Taps are at lfsr[6] (for x^7) and lfsr[3] (for x^4)
   assign lfsr_next[6] = lfsr[5];
   assign lfsr_next[5] = lfsr[4];
   assign lfsr_next[4] = lfsr[3] ^ lfsr[6]; // Tap for x^4
   assign lfsr_next[3] = lfsr[2];
   assign lfsr_next[2] = lfsr[1];
   assign lfsr_next[1] = lfsr[0];
   assign lfsr_next[0] = lfsr[6];             // Tap for x^7

   // 3. Define the output bit (the LSB)
   assign lfsr_out_bit = lfsr[0];

   // 4. Define the final whitened output
   assign whitened_data_out = data_in ^ lfsr_out_bit;


   // --- Sequential Logic (The "Memory") ---
   // This block controls the LFSR register.
   // Load has priority over enable.
   always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 7'b1111111; // Reset to a non-zero state
        end 
        else if (lfsr_load) begin
            // Load the LFSR with the channel seed value
            lfsr <= lfsr_seed; 
        end 
        else if (enable) begin
            // Advance the LFSR to the next state
            lfsr <= lfsr_next;
        end
   end

endmodule