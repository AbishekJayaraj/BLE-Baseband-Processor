import sys
import os

def reverse_bits(bit_string):
    """Reverses a bit string (BLE transmits LSB first, we need MSB for human reading)."""
    return bit_string[::-1]

def bits_to_hex(bit_string):
    """Converts a binary string to a formatted Hex string."""
    # Pad to make sure it's a multiple of 8
    pad_len = (8 - (len(bit_string) % 8)) % 8
    padded = ("0" * pad_len) + bit_string
    
    hex_chars = []
    # Convert every 8 bits into a Hex byte
    for i in range(0, len(padded), 8):
        byte_val = int(padded[i:i+8], 2)
        hex_chars.append(f"{byte_val:02X}")
    return " ".join(hex_chars)

def bits_to_text(bit_string):
    """Converts a binary string to ASCII text (ignoring non-printable chars)."""
    chars = []
    for i in range(0, len(bit_string), 8):
        byte_str = bit_string[i:i+8]
        if len(byte_str) == 8:
            val = int(byte_str, 2)
            if 32 <= val <= 126: # Printable ASCII range
                chars.append(chr(val))
            else:
                chars.append(".")
    return "".join(chars)

def extract_ble_packet(vcd_filepath, target_signal="serial_data_out"):
    print(f"Reading VCD file: {vcd_filepath}...")
    
    if not os.path.exists(vcd_filepath):
        print(f"Error: {vcd_filepath} not found.")
        return

    signal_symbol = None
    timeline = {}
    
    # --- 1. Parse the VCD File ---
    with open(vcd_filepath, 'r') as f:
        # Find the symbol for our target wire
        for line in f:
            parts = line.split()
            if len(parts) >= 5 and parts[0] == '$var' and parts[4] == target_signal:
                signal_symbol = parts[3]
                break
                
        if not signal_symbol:
            print(f"Error: Could not find '{target_signal}' in VCD.")
            return
            
        print(f"Found '{target_signal}' mapped to symbol '{signal_symbol}'. Extracting waveform...")
        
        # Build a dictionary of time -> value
        f.seek(0)
        current_time = 0
        current_val = '0'
        for line in f:
            line = line.strip()
            if line.startswith('#'):
                current_time = int(line[1:])
            elif line.endswith(signal_symbol):
                # Value changes look like "1!" or "0!"
                val = line[0]
                if val in ['0', '1']:
                    timeline[current_time] = val
                    current_val = val

    # --- 2. Sample the Bitstream ---
    # We need to find when the packet actually starts. 
    # The framer sends the preamble (01010101) starting with a 0.
    # We will look for the first 0 -> 1 transition to sync our clock.
    
    times = sorted(timeline.keys())
    if not times:
        print("No data transitions found.")
        return
        
    # Find the time of the first '1' (This is the second bit of the preamble)
    sync_time = 0
    for t in times:
        if timeline[t] == '1':
            sync_time = t
            break

    # The data rate is 20 MHz, which is 50ns per bit. 
    # Because VCD is in picoseconds (1ns/1ps), 50ns = 50,000 ps.
    BIT_PERIOD_PS = 50000 
    
    # Back up half a bit-period to sample exactly in the middle of the first preamble bit ('0')
    sample_time = sync_time - (BIT_PERIOD_PS // 2) 
    
    raw_bits = ""
    last_known_val = '0'
    
    # Sample the timeline every 50ns
    max_time = times[-1] + BIT_PERIOD_PS
    while sample_time < max_time:
        # Find the signal value at this exact sample time
        active_val = last_known_val
        for t in times:
            if t > sample_time:
                break
            active_val = timeline[t]
            
        raw_bits += active_val
        last_known_val = active_val
        sample_time += BIT_PERIOD_PS

    print(f"Extracted {len(raw_bits)} raw bits. Slicing packet...\n")

    # --- 3. Segregate the BLE Fields ---
    # We use a cursor to walk through the raw bitstream
    cursor = 0
    
    def extract_field(name, bit_length):
        nonlocal cursor
        if cursor + bit_length > len(raw_bits):
            return None
        
        chunk = raw_bits[cursor : cursor + bit_length]
        cursor += bit_length
        
        # BLE is LSB first. We must reverse it byte-by-byte to read it properly.
        corrected_bin = ""
        for i in range(0, len(chunk), 8):
            byte_chunk = chunk[i:i+8]
            corrected_bin += reverse_bits(byte_chunk)
            
        hex_val = bits_to_hex(corrected_bin)
        text_val = bits_to_text(corrected_bin)
        
        print(f"{name.upper()}")
        print(f"  TX Binary (Air):  {chunk}")
        print(f"  Logic Binary:     {corrected_bin}")
        print(f"  Hexadecimal:      {hex_val}")
        if name.lower() == "payload":
            print(f"  Plain Text:       '{text_val}'")
        print("-" * 50)
        
        return corrected_bin

    print("==================================================")
    print(" BLE PACKET DECODER RESULTS")
    print("==================================================")

    # Slice the packet according to BLE specs
    extract_field("Preamble", 8)
    extract_field("Access Address", 32)
    
    header_logic_bin = extract_field("PDU Header", 16)
    
    if header_logic_bin:
        # The Length is the second byte of the header
        length_byte_bin = header_logic_bin[8:16]
        payload_length_bytes = int(length_byte_bin, 2)
        payload_bit_len = payload_length_bytes * 8
        
        extract_field("Payload", payload_bit_len)
        extract_field("CRC", 24)
        
        # Any bits left over are padding or idle state
        leftover = len(raw_bits) - cursor
        if leftover > 0:
            print(f"Trailing Idle Bits: {leftover}")
    else:
        print("Failed to extract header.")

if __name__ == "__main__":
    # Ensure this matches your VCD file name
    extract_ble_packet("ble_system_full.vcd")