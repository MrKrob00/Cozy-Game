#!/usr/bin/env python3
"""Генерирует временные звуки игры в assets/audio/.

Звуки синтезируются из синусов и шума, чтобы в игре был звук до появления
настоящих записей. Чтобы заменить звук, положите свой .ogg или .wav с тем же
именем (варианты одного звука — имя_1, имя_2, …: игра выбирает случайный).

Запуск из папки проекта:  python3 tools/make_placeholder_sounds.py
Нужен только numpy.
"""

import os
import wave

import numpy as np

RATE = 32000
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


def seconds(duration):
    return np.arange(int(RATE * duration)) / RATE


def note(name):
    """Частота ноты вида 'C5', 'G#6'."""
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return 440.0 * 2 ** ((names.index(name[:-1]) - 9) / 12 + int(name[-1]) - 4)


def band_noise(duration, low, high):
    """Шум, ограниченный полосой частот (фильтр через спектр)."""
    n = int(RATE * duration)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    edge = 0.15
    gain = np.clip((freqs - low * (1 - edge)) / (low * edge + 1), 0, 1) * np.clip(
        (high * (1 + edge) - freqs) / (high * edge + 1), 0, 1
    )
    out = np.fft.irfft(spectrum * gain, n)
    return out / (np.max(np.abs(out)) + 1e-9)


def mallet(freq, duration, decay=7.0, bright=0.25):
    """Мягкий удар по деревянной клавише: основной тон и быстро гаснущий обертон."""
    t = seconds(duration)
    tone = np.sin(2 * np.pi * freq * t) * np.exp(-decay * t)
    tone += bright * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-decay * 4 * t)
    attack = np.clip(t / 0.004, 0, 1)
    return tone * attack


def bell(freq, duration, decay=5.0):
    """Звонкий колокольчик с негармоническим обертоном."""
    t = seconds(duration)
    tone = np.sin(2 * np.pi * freq * t) * np.exp(-decay * t)
    tone += 0.4 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-decay * 2.2 * t)
    return tone * np.clip(t / 0.003, 0, 1)


def sweep(f_from, f_to, duration, curve=1.0):
    """Синус с плавно меняющейся частотой."""
    t = seconds(duration)
    progress = (t / duration) ** curve
    freq = f_from + (f_to - f_from) * progress
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE)


def envelope(signal, attack=0.005, release=0.05):
    n = len(signal)
    t = np.arange(n) / RATE
    return signal * np.clip(t / attack, 0, 1) * np.clip((n / RATE - t) / release, 0, 1)


def mix(parts, duration):
    """Складывает [(смещение в секундах, сигнал)] в одну дорожку."""
    out = np.zeros(int(RATE * duration))
    for offset, signal in parts:
        start = int(RATE * offset)
        end = min(start + len(signal), len(out))
        out[start:end] += signal[: end - start]
    return out


def make_loop(signal, overlap):
    """Делает отрезок бесшовным: хвост плавно вливается в начало."""
    n = int(RATE * overlap)
    body = signal[:-n].copy()
    fade = np.linspace(0, 1, n)
    body[:n] = body[:n] * fade + signal[-n:] * (1 - fade)
    return body


def save(name, signal, peak):
    signal = signal / (np.max(np.abs(signal)) + 1e-9) * peak
    data = (np.clip(signal, -1, 1) * 32767).astype("<i2")
    os.makedirs(OUT_DIR, exist_ok=True)
    with wave.open(os.path.join(OUT_DIR, name + ".wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data.tobytes())
    print(f"{name}.wav  {len(signal) / RATE:.2f} с")


def find():
    notes = ["E6", "G#6", "B6", "E7"]
    return mix([(0.07 * i, bell(note(n), 0.6)) for i, n in enumerate(notes)], 0.85)


def coin():
    return mix([(0.0, bell(note("B6"), 0.25, 9)), (0.07, bell(note("E7"), 0.3, 8))], 0.4)


def dump():
    # Трава сыплется в ящик: шорох вниз и мягкий стук. Стук — выше 400 Гц,
    # иначе динамик телефона его не воспроизводит.
    whoosh = band_noise(0.42, 500, 5000) * sweep(1.0, 0.2, 0.42) ** 2
    whoosh = envelope(whoosh, 0.02, 0.25)
    t = seconds(0.2)
    thud = (np.sin(2 * np.pi * 440 * t) + 0.5 * np.sin(2 * np.pi * 660 * t)) * np.exp(-30 * t)
    return mix([(0.0, whoosh * 0.7), (0.28, thud * 0.8)], 0.55)


def bonk():
    """Мягкий деревянный «бум» при наезде косилки на препятствие."""
    t = seconds(0.18)
    knock = np.sin(2 * np.pi * sweep_freq(620, 480, t) * t) * np.exp(-26 * t)
    click = band_noise(0.18, 1500, 4000) * np.exp(-90 * t) * 0.35
    return knock + click


def sweep_freq(f_from, f_to, t):
    return f_from + (f_to - f_from) * (t / t[-1])


def blip(freq):
    """Короткий слог реплики жителя."""
    t = seconds(0.05)
    return np.sin(2 * np.pi * freq * t) * np.clip(t / 0.004, 0, 1) * np.exp(-40 * t)


def chime():
    """Отметка прогресса участка: два звонких тона."""
    return mix([(0.0, bell(note("G6"), 0.7, 5)), (0.12, bell(note("D7"), 0.8, 4.5))], 1.0)


def stamp():
    """Штамп падает на бумагу: глухой хлопок средних частот и щелчок."""
    t = seconds(0.16)
    body = band_noise(0.16, 450, 1600) * np.exp(-38 * t)
    tap = np.sin(2 * np.pi * 520 * t) * np.exp(-45 * t) * 0.6
    return body + tap


def bag_full():
    return mix([(0.0, mallet(note("G5"), 0.3)), (0.13, mallet(note("D5"), 0.4))], 0.55)


def deny():
    return mix([(0.0, mallet(note("D5"), 0.2, 10)), (0.1, mallet(note("D5"), 0.25, 10))], 0.4)


def hop():
    return envelope(sweep(320, 640, 0.11, 0.6), 0.004, 0.05)


def squeak():
    return envelope(np.concatenate([sweep(1700, 2700, 0.07), sweep(2700, 2100, 0.09)]), 0.005, 0.05)


def plant():
    notes = ["C6", "D6", "E6", "G6", "A6", "C7"]
    return mix([(0.075 * i, bell(note(n), 0.45, 7)) for i, n in enumerate(notes)], 0.95)


def complete():
    # Короткая радостная фраза и аккорд.
    parts = [(0.11 * i, mallet(note(n), 0.5, 5)) for i, n in enumerate(["C5", "E5", "G5", "C6"])]
    parts += [(0.5, mallet(note(n), 1.3, 2.6, 0.15) * 0.7) for n in ["C5", "E5", "G5", "C6", "E6"]]
    parts += [(0.5 + 0.06 * i, bell(note(n), 0.9, 4) * 0.25) for i, n in enumerate(["G6", "C7", "E7"])]
    return mix(parts, 1.9)


def click():
    return envelope(sweep(900, 600, 0.035), 0.002, 0.02)


def pop():
    return envelope(sweep(420, 760, 0.07, 0.5), 0.003, 0.04)


def chirp(pattern):
    """Птичья трель: pattern — [(пауза до, частота от, частота до, длительность)]."""
    parts, at = [], 0.0
    for gap, f_from, f_to, length in pattern:
        at += gap
        parts.append((at, envelope(sweep(f_from, f_to, length), 0.008, length * 0.5)))
        at += length
    return mix(parts, at + 0.05)


SOUNDS = {
    "bonk": (bonk, 0.5),
    "blip": (lambda: blip(880), 0.25),
    "chime": (chime, 0.5),
    "stamp": (stamp, 0.55),
    "find": (find, 0.6),
    "coin": (coin, 0.5),
    "dump": (dump, 0.7),
    "bag_full": (bag_full, 0.6),
    "deny": (deny, 0.5),
    "hop": (hop, 0.45),
    "squeak": (squeak, 0.35),
    "plant": (plant, 0.55),
    "complete": (complete, 0.7),
    "click": (click, 0.4),
    "pop": (pop, 0.45),
    "chirp_1": (lambda: chirp([(0, 3200, 4600, 0.07), (0.05, 3400, 4800, 0.07), (0.05, 3600, 5200, 0.1)]), 0.3),
    "chirp_2": (lambda: chirp([(0, 5200, 3900, 0.09), (0.09, 5200, 3900, 0.09)]), 0.3),
    "chirp_3": (lambda: chirp([(0, 2800, 3500, 0.05)] + [(0.035, 4200, 4500, 0.04)] * 4), 0.28),
}

if __name__ == "__main__":
    for sound_name, (builder, peak) in SOUNDS.items():
        save(sound_name, builder(), peak)
