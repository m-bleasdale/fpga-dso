import matplotlib.pyplot as plt

def load(filename):
    idx = []
    val = []
    with open(filename) as f:
        for line in f:
            i, v = line.split()
            idx.append(int(i))
            val.append(int(v))
    return idx, val

idx_1hz, val_1hz = load("./visualisations/SineLUTOutput/sine_1hz.txt")
idx_2hz, val_2hz = load("./visualisations/SineLUTOutput/sine_2hz.txt")

fig, axes = plt.subplots(2, 1, figsize=(10, 6), sharex=True)

axes[0].step(idx_1hz, val_1hz, where="post")
axes[0].set_title("1Hz sweep, one cycle across the LUT")
axes[0].set_ylabel("sine_out")

axes[1].step(idx_2hz, val_2hz, where="post", color="darkorange")
axes[1].set_title("2Hz sweep, two cycles across the LUT")
axes[1].set_ylabel("sine_out")
axes[1].set_xlabel("sample index")

plt.tight_layout()
plt.savefig("sine_waveforms.png", dpi=150)
print("saved sine_waveforms.png")