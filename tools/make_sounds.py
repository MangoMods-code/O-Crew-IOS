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

write("scan", tone(1850, 0.09, "square", release=0.3))
write("place", mix(tone(190, 0.07, "sine", sweep=90, release=0.9), [v * 0.4 for v in noise(0.05, lowpass=0.5)]))
write("pickup", tone(380, 0.08, "sine", sweep=620, release=0.5))
write("cash", concat(mix(noise(0.05, lowpass=0.6), tone(900, 0.05, "square")), bell(1318, 0.45)))
write("chime", concat(bell(659, 0.32), bell(523, 0.55)))
write("error", tone(200, 0.16, "square", release=0.4))
write("skill", [v * (1 - i / (RATE * 0.35)) for i, v in enumerate(mix(noise(0.35, lowpass=0.08), tone(300, 0.35, "sine", sweep=900)))])
write("alarm", concat(tone(880, 0.12, "square"), tone(660, 0.12, "square"), tone(880, 0.12, "square")))
write("order", concat(tone(988, 0.07), tone(1319, 0.11)))
write("fanfare", concat(tone(523, 0.12), tone(659, 0.12), tone(784, 0.12), tone(1047, 0.35, release=0.8)))
print("ok")
