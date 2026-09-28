"""
Simulates a single cycle of a sine wave for the sine LUT

Values are signed 2's complement

Address: 12 bits --> 4096 entries
Values: all 12 bits

"""


import numpy as np

ADDR_BITS = 12
DATA_BITS = 12
N = 2**ADDR_BITS              # 4096 entries
HALF = 2**(DATA_BITS - 1)     # 2048
MAX_VAL = HALF - 1            # 2047  (max positive)
MIN_VAL = -HALF                # -2048 (max negative)

def generate_sine_lut(n=N, data_bits=DATA_BITS):

    #Sine LUT as signed 2's comp
    #Values from -2048 to 2047 (@ 12 bits)
    half = 2**(data_bits - 1)
    theta = np.linspace(0, 2*np.pi, n, endpoint=False)
    sine = np.sin(theta)  #-1.0 --> 1.0

    lut = np.round(sine * (half - 1)).astype(int)
    lut = np.clip(lut, -half, half - 1)
    return lut

lut = generate_sine_lut()

def to_twos_complement_hex(val, bits):
    if val < 0:
        val = (1 << bits) + val
    hex_digits = (bits + 3) // 4
    return f"{val:0{hex_digits}X}"

#write to quartus .mif
def write_mif(lut, filename, width=DATA_BITS, depth=N):
    with open(filename, "w") as f:
        f.write(f"WIDTH={width};\n")
        f.write(f"DEPTH={depth};\n\n")
        f.write("ADDRESS_RADIX=UNS;\n")
        f.write("DATA_RADIX=HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        for addr, val in enumerate(lut):
            f.write(f"\t{addr}\t:\t{to_twos_complement_hex(val, width)};\n")
        f.write("END;\n")

write_mif(lut, "sine_lut.mif")

with open("sine_lut.hex", "w") as f:
    for val in lut:
        f.write(f"{to_twos_complement_hex(val, DATA_BITS)}\n")

print("Done")
