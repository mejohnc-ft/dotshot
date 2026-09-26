// Synthesize the intro's soundtrack: a calm pad/arpeggio score plus UI sounds on the scene's cues.
// Everything is generated here (no samples), so the audio is covered by the repository's MIT license.
//
//   node soundtrack.mjs <intro.cues.json> <music.wav> <sfx.wav>
//
// make-intro.sh mixes the two stems with ffmpeg (reverb on the music, loudness normalization).
import { readFileSync, writeFileSync } from "node:fs";

const [cuesPath, musicPath, sfxPath] = process.argv.slice(2);
if (!cuesPath || !musicPath || !sfxPath) {
  console.error("usage: soundtrack.mjs <cues.json> <music.wav> <sfx.wav>");
  process.exit(2);
}
const { duration, sections: S, sounds, score } = JSON.parse(readFileSync(cuesPath, "utf8"));
// A scene can bring its own score ({bar, chords: [[time, [midi…]]…], pulse: [[from, to]…], arp: [[from, to]…]});
// otherwise the default score below follows the scene's sections.

const SR = 48000;
const N = Math.ceil(duration * SR);
const TAU = Math.PI * 2;
const hz = (midi) => 440 * Math.pow(2, (midi - 69) / 12);

// Deterministic noise so every render is identical.
let seed = 0x2f6b1d;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

function stereo() { return [new Float32Array(N), new Float32Array(N)]; }
const music = stereo();
const sfx = stereo();

function add(buf, start, length, pan, fn) {  // fn(t) → sample; pan -1..1 (equal power)
  const l = Math.cos((pan + 1) * Math.PI / 4), r = Math.sin((pan + 1) * Math.PI / 4);
  const i0 = Math.max(0, Math.round(start * SR)), i1 = Math.min(N, Math.round((start + length) * SR));
  for (let i = i0; i < i1; i++) {
    const v = fn(i / SR - start);
    buf[0][i] += v * l; buf[1][i] += v * r;
  }
}
const adsr = (t, len, a, rel) => Math.min(1, t / a) * Math.min(1, Math.max(0, (len - t) / rel));

// ---- score ------------------------------------------------------------------------------------
// Title: Dmaj9 swell. Problem: a suspended, unresolved walk. Product scenes: D – A/C# – Bm7 – Gmaj9
// with a soft arpeggio. End: back home to Dmaj9 with a bell.
const BAR = score?.bar ?? 2.5, EIGHTH = BAR / 8;
const inRanges = (t, ranges) => ranges.some(([a, b]) => t >= a && t < b);
const chords = score ? score.chords.map(([t, notes]) => [t, notes]) : [
  [S.s1, [50, 57, 61, 64, 66]],
  [S.s2, [47, 54, 57, 62, 66]], [S.s2 + BAR, [43, 55, 59, 62, 66]], [S.s2 + 2 * BAR, [40, 55, 59, 62, 67]],
  [S.s2 + 3 * BAR, [45, 57, 62, 64, 69]], [S.s3 - 1.1, [45, 57, 61, 64, 67]],
];
if (!score) {
  const LOOP = [[50, 57, 62, 66, 69], [49, 57, 61, 64, 69], [47, 57, 62, 66, 69], [43, 57, 62, 66, 71]];
  for (let t = S.s3, i = 0; t < S.s7 - 0.01; t += BAR, i++) chords.push([t, LOOP[i % 4]]);
  chords.push([S.s7, [50, 57, 61, 64, 66, 69]]);
}
chords.sort((a, b) => a[0] - b[0]);

chords.forEach(([start, notes], k) => {
  const end = k + 1 < chords.length ? chords[k + 1][0] : duration;
  const len = end - start + 1.0;  // overlap for a legato cross-fade
  const attack = k === 0 ? 2.2 : 0.7;
  notes.forEach((m, j) => {
    const f = hz(m);
    [-6, 0, 6].forEach((cents, v) => {
      const fv = f * Math.pow(2, cents / 1200);
      const phase = (j * 1.7 + v * 2.3) % TAU;
      add(music, start, len, (v - 1) * 0.55, (t) => {
        const p = TAU * fv * t + phase;
        const tone = Math.sin(p) + 0.32 * Math.sin(2 * p) + 0.12 * Math.sin(3 * p) + 0.05 * Math.sin(4 * p);
        const breathe = 1 + 0.08 * Math.sin(TAU * 0.23 * t + j);
        return 0.018 * tone * breathe * adsr(t, len, attack, 1.1);
      });
    });
  });
  // Bass: the chord root an octave down from the product scenes on (a scene score voices its own low root).
  if (score || start >= S.s3 - 1.2) {
    const f = hz(score ? notes[0] : notes[0] - 12);
    add(music, start, len, 0, (t) => 0.05 * (Math.sin(TAU * f * t) + 0.45 * Math.sin(TAU * 2 * f * t) + 0.15 * Math.sin(TAU * 3 * f * t)) * adsr(t, len, 0.25, 0.9));
  }
});

// Arpeggio: upper chord tones in eighths while the product is on screen.
const ARP = [1, 3, 2, 4, 3, 2, 4, 1];
const arpStep = score ? BAR / 4 : EIGHTH;
for (let t = score ? Math.min(...score.arp.map(([a]) => a)) : S.s3, n = 0; t < (score ? duration : S.s7) - arpStep; t += arpStep, n++) {
  if (score && !inRanges(t, score.arp)) continue;
  const chord = [...chords].reverse().find(([s]) => s <= t + 1e-6)[1];
  const m = chord[ARP[n % 8] % chord.length] + 12;
  const f = hz(m);
  const accent = n % 8 === 0 ? 1 : n % 2 === 0 ? 0.8 : 0.62;
  const build = score ? 0.6 : t < S.s4 ? 0.75 : 1;  // a little more energy after the first capture lands
  add(music, t, 1.2, n % 2 ? 0.35 : -0.35, (x) =>
    0.05 * accent * build * Math.min(1, x / 0.004) * Math.exp(-x * 5.5) * (Math.sin(TAU * f * x) + (0.3 * Math.sin(TAU * 2 * f * x) + 0.12 * Math.sin(TAU * 3 * f * x)) * Math.exp(-x * 12)));
}

// Air: a quiet two-octave-up echo of the arpeggio's downbeats.
for (let t = score ? duration : S.s4, n = 0; t < S.s7 - EIGHTH; t += EIGHTH * 2, n++) {
  const chord = [...chords].reverse().find(([s]) => s <= t + 1e-6)[1];
  const f = hz(chord[ARP[(n * 2) % 8] % chord.length] + 24);
  add(music, t + 0.01, 0.9, n % 2 ? -0.6 : 0.6, (x) => 0.012 * Math.min(1, x / 0.004) * Math.exp(-x * 7) * Math.sin(TAU * f * x));
}

// A scene score's pulse: a sub-bass thump on every beat, accented on the downbeat.
if (score) {
  for (const [a, b] of score.pulse) {
    for (let t = a, n = 0; t < b; t += BAR / 4, n++) {
      const g = n % 4 === 0 ? 0.16 : 0.09;
      add(music, t, 0.6, 0, (x) => g * Math.min(1, x / 0.003) * Math.exp(-x * 9) * Math.sin(TAU * (58 * x - 40 * x * x)));
    }
  }
}

// Problem scene: a slow, low pulse for tension.
for (let t = score ? duration : S.s2 + 0.3; t < S.s3 - 1.2; t += BAR / 2) {
  add(music, t, 1.0, 0, (x) => 0.045 * Math.exp(-x * 4) * (Math.sin(TAU * hz(38) * x) + 0.4 * Math.sin(TAU * hz(50) * x)));
}

// ---- UI sounds ----------------------------------------------------------------------------------
const lp = (fc) => { let y = 0; const a = 1 - Math.exp(-TAU * fc / SR); return (x) => (y += a * (x - y)); };
const hp = (fc) => { const low = lp(fc); return (x) => x - low(x); };
const tone = (f, decay, amp) => (t) => amp * Math.exp(-t * decay) * Math.sin(TAU * f * t);

const SOUND = {
  click(at) { const h = hp(2500); add(sfx, at, 0.05, 0.1, (t) => 0.22 * Math.exp(-t * 400) * h(rand()) + tone(3400, 180, 0.07)(t)); },
  press(at) { const h = hp(1500); add(sfx, at, 0.05, 0.1, (t) => 0.12 * Math.exp(-t * 300) * h(rand()) + tone(1900, 160, 0.05)(t)); },
  key(at) {
    const l = lp(3500), g = 0.8 + 0.4 * Math.abs(rand());
    add(sfx, at, 0.06, 0.15, (t) => g * (0.16 * Math.exp(-t * 220) * l(rand()) + tone(1150, 120, 0.04)(t)));
  },
  tick(at) { add(sfx, at, 0.08, 0, tone(2600, 70, 0.045)); },
  blip(at) { add(sfx, at, 0.1, 0, (t) => tone(1320, 40, 0.05)(t) + tone(1980, 60, 0.02)(t)); },
  pop(at) {
    add(sfx, at, 0.12, 0, (t) => 0.13 * Math.min(1, t / 0.003) * Math.exp(-t * 35) * Math.sin(TAU * (280 * t + 2600 * t * t)));
  },
  shutter(at) {
    [0, 0.075].forEach((d, k) => {
      const h = hp(900), l = lp(6000);
      add(sfx, at + d, 0.08, 0, (t) => (k ? 0.16 : 0.24) * Math.exp(-t * 90) * l(h(rand())));
    });
  },
  sent(at) {
    [[hz(88), 0], [hz(93), 0.085]].forEach(([f, d]) =>
      add(sfx, at + d, 0.9, 0.2, (t) => 0.09 * Math.min(1, t / 0.004) * Math.exp(-t * 6) * (Math.sin(TAU * f * t) + 0.18 * Math.sin(TAU * 2.01 * f * t))));
  },
  drop(at) {
    add(sfx, at, 0.2, 0, (t) => 0.26 * Math.exp(-t * 28) * Math.sin(TAU * (170 * t - 180 * t * t)));
    SOUND.click(at);
  },
  swish(at) {
    const l = lp(1400);
    add(sfx, at, 0.7, 0, (t) => 0.1 * Math.sin(Math.PI * Math.min(1, t / 0.7)) ** 2 * l(rand()));
  },
  rise(at) { [86, 90, 93, 98].forEach((m, k) => add(sfx, at + k * 0.07, 1.4, (k - 1.5) * 0.3, (t) => 0.035 * Math.min(1, t / 0.01) * Math.exp(-t * 3.2) * Math.sin(TAU * hz(m) * t))); },
  rec(at) { [[660, 0], [990, 0.11]].forEach(([f, d]) => add(sfx, at + d, 0.2, 0, (t) => 0.06 * adsr(t, 0.12, 0.004, 0.04) * Math.sin(TAU * f * t))); },
  recstop(at) { [[990, 0], [660, 0.11]].forEach(([f, d]) => add(sfx, at + d, 0.2, 0, (t) => 0.06 * adsr(t, 0.12, 0.004, 0.04) * Math.sin(TAU * f * t))); },
  boom(at) {
    const l = lp(300);
    add(sfx, at, 3.2, 0, (t) => Math.min(1, t / 0.01) * Math.exp(-t * 1.4) * (0.34 * Math.sin(TAU * (46 * t - 5 * t * t)) + 0.1 * l(rand())));
  },
  impact(at) {
    const l = lp(900);
    add(sfx, at, 1.2, 0, (t) => Math.min(1, t / 0.004) * (0.26 * Math.exp(-t * 5) * Math.sin(TAU * (78 * t - 30 * t * t)) + 0.08 * Math.exp(-t * 30) * l(rand())));
  },
  whoosh(at) {
    let y = 0;
    add(sfx, at, 1.0, 0, (t) => {
      const fc = 200 + 3800 * Math.pow(t / 1.0, 1.6), a = 1 - Math.exp(-TAU * fc / SR);
      y += a * (rand() - y);
      return 0.12 * Math.sin(Math.PI * Math.min(1, t / 1.0)) ** 1.5 * y;
    });
  },
  trail(at) {
    add(sfx, at, 1.3, 0.2, (t) => 0.06 * Math.sin(Math.PI * Math.min(1, t / 1.3)) * Math.sin(TAU * (320 * t + 520 * t * t)));
    add(sfx, at, 1.3, -0.2, (t) => 0.025 * Math.sin(Math.PI * Math.min(1, t / 1.3)) * Math.sin(TAU * (640 * t + 1040 * t * t)));
  },
  bell(at) {
    [[hz(74), 0, 0], [hz(81), 0.16, 0.25], [hz(86), 0.32, -0.25]].forEach(([f, d, pan]) =>
      add(sfx, at + d, 3.4, pan, (t) => 0.06 * Math.min(1, t / 0.003) * Math.exp(-t * 1.3) * Math.sin(TAU * f * t + 2.2 * Math.exp(-t * 3) * Math.sin(TAU * 3.5 * f * t))));
  },
};
for (const { t, kind } of sounds) {
  if (!SOUND[kind]) throw new Error(`unknown sound cue: ${kind}`);
  SOUND[kind](t);
}

// ---- output -------------------------------------------------------------------------------------
function fade(buf) {
  for (let i = 0; i < N; i++) {
    const t = i / SR;
    const g = Math.min(1, t / 0.4) * Math.min(1, Math.max(0, (duration - 0.2 - t) / 2.2));
    buf[0][i] *= g; buf[1][i] *= g;
  }
}
function writeWav(path, [l, r]) {
  const data = Buffer.alloc(N * 4);
  for (let i = 0; i < N; i++) {
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, l[i])) * 32767), i * 4);
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, r[i])) * 32767), i * 4 + 2);
  }
  const header = Buffer.alloc(44);
  header.write("RIFF", 0); header.writeUInt32LE(36 + data.length, 4); header.write("WAVE", 8);
  header.write("fmt ", 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22);
  header.writeUInt32LE(SR, 24); header.writeUInt32LE(SR * 4, 28); header.writeUInt16LE(4, 32); header.writeUInt16LE(16, 34);
  header.write("data", 36); header.writeUInt32LE(data.length, 40);
  writeFileSync(path, Buffer.concat([header, data]));
}
fade(music); fade(sfx);
writeWav(musicPath, music);
writeWav(sfxPath, sfx);
console.log(`  soundtrack: ${sounds.length} cues, ${chords.length} chords, ${duration}s`);
