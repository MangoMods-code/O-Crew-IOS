#!/usr/bin/env python3
"""Composes O-Crew's background track (an original, mellow store-radio loop) and the
pitched combo/jingle sounds. Everything is synthesized here; no samples.
Run: python3 tools/make_music.py   (needs numpy; ffmpeg for the .m4a)"""
import numpy as np, wave, os, subprocess, sys

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "OCrew", "Resources", "Sounds")
rng = np.random.default_rng(11)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def write_wav(path, x, sr=SR):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())

def env_adsr(n, a, d, s, r, sr=SR):
    a_n, d_n, r_n = int(a * sr), int(d * sr), int(r * sr)
    e = np.ones(n) * s
    a_n = min(a_n, n); e[:a_n] = np.linspace(0, 1, a_n, endpoint=False)
    d_end = min(n, a_n + d_n)
    if d_end > a_n: e[a_n:d_end] = np.linspace(1, s, d_end - a_n)
    r_n = min(r_n, n)
    if r_n > 0: e[-r_n:] *= np.linspace(1, 0, r_n)
    return e

def epiano(m, dur, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR; f = hz(m)
    mod = np.sin(2 * np.pi * f * 14 * t) * np.exp(-t * 18) * 0.25      # tine "bell" attack
    body = np.sin(2 * np.pi * f * t + 1.6 * np.exp(-t * 3.0) * np.sin(2 * np.pi * f * t) + mod)
    trem = 1 - 0.12 * (0.5 + 0.5 * np.sin(2 * np.pi * 4.6 * t))
    return body * np.exp(-t * 1.5) * trem * env_adsr(n, 0.004, 0.2, 0.8, 0.12) * vel

def vibes(m, dur, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR; f = hz(m)
    x = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 9) + 0.12 * np.sin(2 * np.pi * f * 10 * t) * np.exp(-t * 22)
    vib = 1 - 0.18 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.2 * t))
    return x * np.exp(-t * 2.6) * vib * env_adsr(n, 0.002, 0.1, 0.9, 0.1) * vel

def bass(m, dur, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR; f = hz(m)
    x = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 6)
    return x * env_adsr(n, 0.008, 0.15, 0.75, 0.08) * vel

def kick():
    n = int(0.28 * SR); t = np.arange(n) / SR
    f = 46 + 90 * np.exp(-t * 32)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 13)

def lowpass(x, a):
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc); y[i] = acc
    return y

def snare():
    n = int(0.16 * SR); t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n)
    noise = noise - lowpass(noise, 0.25)
    return (noise * 0.7 + 0.35 * np.sin(2 * np.pi * 190 * t)) * np.exp(-t * 26)

def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR); t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n)
    noise = noise - lowpass(noise, 0.6)
    return noise * np.exp(-t * (16 if open_ else 70))

def add(buf, x, at, gain=1.0):
    """Mix x into buf at time `at`, wrapping around the end so the loop is seamless."""
    i = int(at * SR) % len(buf)
    n = len(x); end = i + n
    if end <= len(buf): buf[i:end] += x * gain
    else:
        k = len(buf) - i
        buf[i:] += x[:k] * gain; buf[:n - k] += x[k:] * gain

def music():
    bpm = 82.0; beat = 60 / bpm; bars = 16
    L = int(bars * 4 * beat * SR)
    keys = np.zeros(L); low = np.zeros(L); drums = np.zeros(L); lead = np.zeros(L)
    # i: Fmaj9  Em7  Dm9  Cmaj7 | Fmaj9  G6/9  Am7  Am7/G  (x2 with a different melody)
    chords = [
        (41, [57, 60, 64, 67]), (40, [55, 59, 62, 67]), (38, [53, 57, 60, 64]), (36, [52, 55, 59, 64]),
        (41, [57, 60, 64, 67]), (43, [55, 59, 62, 64]), (45, [55, 60, 64, 67]), (43, [55, 59, 62, 67]),
    ]
    swing = 0.14 * beat
    for bar in range(bars):
        t0 = bar * 4 * beat
        root, notes = chords[bar % 8]
        # keys: soft chord on 1, answer on the "and" of 2, little push before 4
        for j, m in enumerate(notes):
            add(keys, epiano(m, beat * 2.6, 0.5), t0 + j * 0.012, 0.22)
        for j, m in enumerate(notes[1:]):
            add(keys, epiano(m, beat * 1.2, 0.4), t0 + 2.5 * beat + swing + j * 0.01, 0.16)
        if bar % 2 == 1:
            add(keys, epiano(notes[-1] + 12, beat * 0.8, 0.35), t0 + 3.5 * beat + swing, 0.12)
        # bass: root, fifth/octave movement
        add(low, bass(root, beat * 1.4), t0, 0.42)
        add(low, bass(root, beat * 0.5), t0 + 1.5 * beat + swing, 0.3)
        add(low, bass(root + 7, beat * 0.9), t0 + 2.5 * beat + swing, 0.32)
        add(low, bass(root + (12 if bar % 4 == 3 else 0), beat * 0.45), t0 + 3.5 * beat + swing, 0.28)
        # drums: laid-back kick/snare with swung hats
        for b in (0, 2.5):
            add(drums, kick(), t0 + b * beat + (swing if b % 1 else 0), 0.55)
        for b in (1, 3):
            add(drums, snare(), t0 + b * beat, 0.26)
        for e in range(8):
            off = swing if e % 2 else 0
            add(drums, hat(open_=(e == 7 and bar % 4 == 3)), t0 + e * 0.5 * beat + off, 0.07 if e % 2 else 0.11)
    # melody: two 8-bar phrases, pentatonic-ish over the changes (beats within the phrase, midi, length)
    A = [(0, 76, 1.5), (1.5, 79, .5), (2, 76, 1), (3.5, 74, .5), (4, 71, 2), (6.5, 72, .5), (7, 74, 1),
         (8, 72, 1.5), (9.5, 69, .5), (10, 72, 1), (11, 76, 1), (12, 79, 2.5), (15, 76, .5), (15.5, 74, .5),
         (16, 76, 1.5), (17.5, 81, .5), (18, 79, 1), (19.5, 76, .5), (20, 74, 1.5), (21.5, 71, .5), (22, 74, 2),
         (24, 72, 1), (25, 76, 1), (26, 79, 1), (27, 84, 1), (28, 83, 1.5), (29.5, 79, .5), (30, 76, 2)]
    B = [(0.5, 84, .5), (1, 81, 1), (2, 79, 1.5), (3.5, 76, .5), (4.5, 79, .5), (5, 76, 1), (6, 74, 2),
         (8.5, 77, .5), (9, 76, 1), (10, 72, 1), (11.5, 69, .5), (12, 71, 1), (13, 72, 1), (14, 76, 2),
         (16.5, 81, .5), (17, 84, 1), (18, 81, .5), (18.5, 79, 1.5), (20, 79, 1), (21, 76, 1), (22, 74, 1), (23, 71, 1),
         (24, 72, 2), (26.5, 76, .5), (27, 79, 1), (28, 76, 3)]
    for phrase, t0 in ((A, 0), (B, 32 * beat)):
        for (b, m, ln) in phrase:
            late = swing if (b * 2) % 2 == 1 else 0
            add(lead, vibes(m, max(0.5, ln * beat * 1.6), 0.8), t0 + b * beat + late, 0.2)
    mix = lowpass(keys, 0.35) * 1.0 + lowpass(low, 0.2) * 1.0 + drums * 0.9 + lowpass(lead, 0.5) * 0.9
    # a little tape warmth + room
    mix = np.tanh(mix * 1.4) * 0.8
    echo = np.zeros(L); d = int(0.33 * SR)
    echo[d:] = mix[:-d]; echo[:d] = mix[-d:]
    mix = mix + 0.14 * lowpass(echo, 0.2)
    room = lowpass(rng.uniform(-1, 1, L), 0.02) * 0.02
    mix = mix + room
    mix /= np.max(np.abs(mix)) * 1.12
    return mix

def jingle(notes, step, dur, fn=vibes, gain=0.5):
    L = int((step * (len(notes) - 1) + dur + 0.05) * SR); buf = np.zeros(L)
    for i, m in enumerate(notes):
        ms = m if isinstance(m, (list, tuple)) else [m]
        for mm in ms:
            x = fn(mm, dur); s = int(i * step * SR); buf[s:s + len(x)] += x[:L - s] * gain
    return buf / max(1.0, np.max(np.abs(buf)) * 1.05)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    scale = [72, 74, 76, 79, 81, 84, 86, 88]         # C major pentatonic climbing
    for i, m in enumerate(scale, 1):
        write_wav(os.path.join(OUT, f"combo{i}.wav"), jingle([[m, m + 12]], 0, 0.5, gain=0.45))
    write_wav(os.path.join(OUT, "section.wav"), jingle([72, 76, 79, [84, 88]], 0.09, 0.9))
    write_wav(os.path.join(OUT, "star.wav"), jingle([[88, 91]], 0, 0.7, gain=0.5))
    write_wav(os.path.join(OUT, "click.wav"), jingle([96], 0, 0.06, gain=0.35))
    n = int(0.18 * SR); t = np.arange(n) / SR
    wh = lowpass(rng.uniform(-1, 1, n), 0.18) * np.sin(np.pi * t / t[-1]) ** 2 * 0.9
    write_wav(os.path.join(OUT, "whoosh.wav"), wh)
    m = music()
    tmp = os.path.join(OUT, "_music.wav"); write_wav(tmp, m)
    dst = os.path.join(OUT, "music.m4a")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "aac", "-b:a", "80k", dst], check=True)
    os.remove(tmp)
    print("ok", round(len(m) / SR, 2), "s", os.path.getsize(dst) // 1024, "KB")
