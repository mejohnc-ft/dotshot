// Render a time-driven HTML scene to H.264 by stepping window.render(t) and piping frames into ffmpeg.
// Used by make-intro.sh. Needs puppeteer-core (installed into build/media/node by that script) and ffmpeg.
//
//   Also writes <out>.cues.json when the scene defines window.SOUNDS.
//
//   node render-video.mjs <file://…scene.html> <out.mp4> [--fps 30] [--duration 50] [--width 1280] [--height 720] [--scale 1.5] [--crf 18]
import { spawn } from "node:child_process";
import { createRequire } from "node:module";

const require = createRequire(process.env.DOTSHOT_NODE_MODULES + "/");
const puppeteer = require("puppeteer-core");

const [url, out, ...rest] = process.argv.slice(2);
const opt = { fps: 30, duration: 0, width: 1280, height: 720, scale: 1.5, crf: 18 };
for (let i = 0; i < rest.length; i += 2) opt[rest[i].replace(/^--/, "")] = parseFloat(rest[i + 1]);
if (!url || !out) {
  console.error("usage: render-video.mjs <url> <out.mp4> [--fps N] [--duration S] [--width W] [--height H] [--scale K]");
  process.exit(2);
}

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
  args: ["--hide-scrollbars", "--allow-file-access-from-files", "--font-render-hinting=none"],
});
const page = await browser.newPage();
await page.setViewport({ width: opt.width, height: opt.height, deviceScaleFactor: opt.scale });
await page.goto(url, { waitUntil: "load" });
await page.evaluate(() => document.fonts.ready);
const duration = opt.duration || (await page.evaluate(() => window.DURATION));

// Scenes may publish sound cues (window.SOUNDS) for soundtrack.mjs; write them next to the video.
const cues = await page.evaluate(() => window.SOUNDS && { duration: window.DURATION, sections: window.SECTIONS, sounds: window.SOUNDS, style: window.STYLE, score: window.SCORE });
if (cues) {
  const { writeFileSync } = await import("node:fs");
  writeFileSync(out.replace(/\.mp4$/, "") + ".cues.json", JSON.stringify(cues, null, 1));
}
const frames = Math.round(duration * opt.fps);

const ffmpeg = spawn("ffmpeg", [
  "-loglevel", "error", "-y", "-f", "image2pipe", "-framerate", String(opt.fps), "-c:v", "png", "-i", "-",
  "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", String(opt.crf), "-preset", "slow", "-tune", "animation",
  "-movflags", "+faststart", out,
], { stdio: ["pipe", "inherit", "inherit"] });

for (let n = 0; n < frames; n++) {
  await page.evaluate((t) => window.render(t), n / opt.fps);
  const png = await page.screenshot({ type: "png", optimizeForSpeed: true });
  if (!ffmpeg.stdin.write(png)) await new Promise((r) => ffmpeg.stdin.once("drain", r));
  if (n % opt.fps === 0) process.stdout.write(`\r  ${Math.round(n / opt.fps)}s / ${duration}s`);
}
ffmpeg.stdin.end();
await new Promise((r) => ffmpeg.on("close", r));
await browser.close();
process.stdout.write(`\r  ${frames} frames → ${out}\n`);
