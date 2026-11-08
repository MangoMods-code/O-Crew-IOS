#!/usr/bin/env python3
"""Generates O-Crew's sound effects procedurally (no third-party assets).
Run: python3 tools/make_sounds.py"""
import math, random, struct, wave, os

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "OCrew", "Resources", "Sounds")
random.seed(7)

def env(i, n, attack=0.005, release=0.6):
    t = i / RATE; dur = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = max(0.0, 1.0 - max(0.0, t - dur * (1 - release)) / (dur * release)) if release > 0 else 1.0
    return a * r

def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.8 / peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))

def tone(freqs, dur, kind="sine", attack=0.004, release=0.7, sweep=None):
    n = int(RATE * dur); out = []; ph = 0.0
    for i in range(n):
        f = freqs if not sweep else freqs + (sweep - freqs) * (i / n)
        ph += 2 * math.pi * f / RATE
        if kind == "sine": v = math.sin(ph)
        elif kind == "square": v = 1.0 if math.sin(ph) > 0 else -1.0
        else: v = 2 * ((ph / (2 * math.pi)) % 1) - 1
        out.append(v * env(i, n, attack, release))
    return out

def mix(*parts):
    n = max(len(p) for p in parts); out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p): out[i] += v
    return out

def concat(*parts):
    out = []
    for p in parts: out += p
    return out

def silence(d): return [0.0] * int(RATE * d)

def noise(dur, release=0.8, lowpass=0.2):
    n = int(RATE * dur); out = []; last = 0.0
    for i in range(n):
        last += (random.uniform(-1, 1) - last) * lowpass
        out.append(last * env(i, n, 0.002, release))
    return out

def bell(f, dur):
    n = int(RATE * dur)
    return [(math.sin(2*math.pi*f*i/RATE) + 0.5*math.sin(2*math.pi*f*2.76*i/RATE) + 0.25*math.sin(2*math.pi*f*5.4*i/RATE))
            * math.exp(-6 * i / n) for i in range(n)]


write("place", mix(tone(190, 0.07, "sine", sweep=90, release=0.9), [v * 0.4 for v in noise(0.05, lowpass=0.5)]))
write("pickup", tone(380, 0.08, "sine", sweep=620, release=0.5))

write("chime", concat(bell(659, 0.32), bell(523, 0.55)))
write("error", tone(200, 0.16, "square", release=0.4))
write("skill", [v * (1 - i / (RATE * 0.35)) for i, v in enumerate(mix(noise(0.35, lowpass=0.08), tone(300, 0.35, "sine", sweep=900)))])


write("fanfare", concat(tone(523, 0.12), tone(659, 0.12), tone(784, 0.12), tone(1047, 0.35, release=0.8)))
write("ding", concat(bell(1568, 0.18), bell(2093, 0.35)))
write("bonk", tone(150, 0.12, "sine", sweep=95, release=0.7))
write("pop", tone(520, 0.06, "sine", sweep=900, release=0.6))
write("magnet", [v * min(1, i / (RATE * 0.25)) for i, v in enumerate(mix(tone(220, 0.45, "sine", sweep=660), [x * 0.4 for x in noise(0.45, lowpass=0.05)]))])
write("toss", mix(noise(0.18, lowpass=0.3), tone(260, 0.12, "sine", sweep=120)))
write("complete", concat(tone(523, 0.1), tone(659, 0.1), tone(784, 0.1), bell(1047, 0.25), bell(1319, 0.6)))
write("step", [v * 0.9 for v in mix(noise(0.07, release=0.9, lowpass=0.12), tone(85, 0.06, "sine", sweep=55, release=0.9))])
print("ok")
