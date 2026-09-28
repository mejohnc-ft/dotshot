// Build the guide pages (site/<slug>/index.html) for each platform and agent harness.
// They reuse the landing page's styles, so run this after editing site/index.html's <style> or the text below.
//
//   node scripts/docs/make-pages.mjs
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");
const SITE = join(ROOT, "site");
const BASE = "https://mejohnc-ft.github.io/dotshot/";
const index = readFileSync(join(SITE, "index.html"), "utf8");
const style = index.slice(index.indexOf("<style>"), index.indexOf("</style>") + "</style>".length);

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const code = (s) => `<pre><code>${esc(s)}</code></pre>`;

// Shared blocks.
const SETUP = (host, name, folder = "~/inbound") => `
  <ol class="guide">
    <li><h3>Install dotshot on your Mac</h3><p>Download the notarized DMG from <a href="https://github.com/mejohnc-ft/dotshot/releases/latest">GitHub Releases</a> and allow Screen Recording in its setup. Nothing gets installed on the other machine.</p></li>
    <li><h3>Make sure this Mac can reach it with a key</h3>${code(`ssh -o BatchMode=yes ${host} true && echo ready`)}<p>No key there yet? Run <code>ssh-copy-id ${esc(host)}</code> once. Tailscale names and <code>~/.ssh/config</code> aliases (including ones with a <code>ProxyCommand</code>) work, because dotshot uses your SSH configuration.</p></li>
    <li><h3>Add it as a destination</h3><p>In setup, or from Terminal (or let your agent do it with the <a href="https://github.com/mejohnc-ft/dotshot/blob/main/docs/AGENTS.md">setup skill</a>):</p>${code(`DS=/Applications/dotshot.app/Contents/Resources/dotshot-capture.sh\n"$DS" add ${name} ${host} '${folder}'\n"$DS" check ${name}`)}<p><code>check</code> creates a private folder, verifies the key and SFTP, and saves the absolute path your agent will see.</p></li>
    <li><h3>Capture</h3><p>Press <kbd>⌃⌥⌘S</kbd> and drag, or <kbd>⌃⌥⌘V</kbd> to record. The file lands on the machine and its absolute path is on your clipboard.</p></li>
  </ol>`;

const PAGES = [
  {
    slug: "spark", nav: "DGX Spark", kicker: "dotshot for DGX Spark",
    title: "Screenshots from your Mac, straight to the agent on your DGX Spark.",
    lede: "The fine-tune runs on the Spark. The loss curve, the notebook error, and the dashboard are on your Mac. dotshot sends what you see to the Spark and puts the path on your clipboard for Claude Code or Codex there.",
    image: "spark.jpg", alt: "A stylized DGX Spark with the label spark, Spark cluster, DGX Spark, CUDA, claude",
    uses: [
      ["Loss curves and dashboards", "A spike in a W&B or TensorBoard chart goes to the agent that can read your training config."],
      ["Notebook and CUDA errors", "Capture the traceback from Jupyter in your browser instead of copying half of it."],
      ["Recordings of long runs", "Record a flickering progress bar or a UI that hangs, then send it, trim it, or shrink it first."],
      ["Eval files and configs", "Drop result files, sample generations, or configs on the nub and pick the Spark."],
    ],
    host: "dev@spark-cluster.local", dest: "spark",
    notes: [
      "DGX Spark runs Linux on arm64. dotshot only needs SSH and a folder there, so the architecture doesn't matter.",
      "If you connect through NVIDIA Sync or a jump host, give dotshot the same alias you type after <code>ssh</code>.",
      "Several Sparks? Add each as its own destination (<code>spark1</code>, <code>spark2</code>) and switch from the pill.",
    ],
  },
  {
    slug: "rocm", nav: "ROCm", kicker: "dotshot for ROCm",
    title: "Profiler tables, not paraphrases, for the agent on your ROCm box.",
    lede: "Kernel summaries, rocm-smi output, and HIP build errors are easier to show than to describe. dotshot sends a capture from your Mac to your Radeon or Instinct machine, and your agent reads the real table.",
    image: "rocm.jpg", alt: "A stylized ROCm workstation with two GPUs, labeled rocm, ROCm cluster, 2× Radeon AI PRO R9700, codex",
    uses: [
      ["Profiler output", "rocprofv3 kernel tables, omniperf views, and traces go to the agent working on the kernel."],
      ["Build and runtime errors", "HIP compiler errors and stack traces from a browser or remote desktop, as images."],
      ["Serving dashboards", "Throughput and latency panels from your inference server while the agent tunes it."],
      ["Trace files", "Drop exported JSON traces or logs on the nub; they arrive next to the code."],
    ],
    host: "dev@rocm-box", dest: "rocm",
    notes: [
      "Works the same for Radeon workstations and Instinct servers: dotshot never touches the GPU stack.",
      "Agents on ROCm boxes often run with broad permissions. Treat captures of untrusted pages as untrusted input.",
      "Behind a bastion? Put the <code>ProxyJump</code> in <code>~/.ssh/config</code> and use that alias.",
    ],
  },
  {
    slug: "mac", nav: "Remote Macs", kicker: "dotshot for remote Macs and macOS VMs",
    title: "Your build Mac, your MLX box, your macOS VM: one shortcut away.",
    lede: "A Mac mini running agents overnight, a Mac Studio training with MLX, a macOS VM for clean builds. Turn on Remote Login, add it to dotshot, and send it what you see from your laptop.",
    image: "mac.jpg", alt: "A stylized Mac desktop labeled mac, Dev Mac, MLX, app development, claude",
    uses: [
      ["MLX runs", "Training curves and memory graphs from the machine doing the work."],
      ["Xcode and Simulator", "Build errors, layout bugs, and Simulator screens, as screenshots or recordings."],
      ["UI bugs that move", "Record a flaky animation or login flow; the agent gets frames it can reason about."],
      ["Anything else", "Designs, logs, and crash reports: drop them on the nub, choose the Mac."],
    ],
    host: "dev@mac-mini.local", dest: "mac",
    notes: [
      "On the destination Mac: System Settings → General → Sharing → <strong>Remote Login</strong>. That's all it needs.",
      "macOS VMs (UTM, Tart, Parallels, cloud Macs) work the same as long as SSH reaches them.",
      "The destination Mac doesn't need dotshot. Only the Mac you capture on does.",
    ],
  },
  {
    slug: "claude", nav: "Claude Code", kicker: "dotshot for Claude Code",
    title: "Claude Code over SSH can't take a pasted screenshot. Give it a path.",
    lede: "Pasting an image into Claude Code works locally, but not in a session on another machine. That machine can't see your Mac's clipboard. Claude Code reads images from a file path, so dotshot puts the file there and the path on your clipboard.",
    image: "claude.jpg", alt: "A terminal running claude on a remote machine with a pasted dotshot path and the agent's reply",
    uses: [
      ["Paste the path", "Type your question and paste: <code>Why did loss spike? /home/dev/inbound/train-loss-…png</code>. Claude reads the image."],
      ["Recordings", "Claude reads frames, not video. Ask it to pull frames with <code>ffmpeg</code>, or install the inbox skill, which does it for you."],
      ["No path at hand", "With the <code>dotshot-inbox</code> skill installed on that machine, \"look at the screenshot I just sent\" finds the newest file."],
    ],
    host: "dev@gpu-box", dest: "gpu",
    agent: `mkdir -p ~/.claude/skills/dotshot-inbox\ncurl -fsSL https://raw.githubusercontent.com/mejohnc-ft/dotshot/main/skills/dotshot-inbox/SKILL.md \\\n  -o ~/.claude/skills/dotshot-inbox/SKILL.md`,
    agentNote: "Run this on the destination machine to install the inbox skill.",
    notes: [
      "Claude Code on your Mac can set dotshot up for you with the <code>dotshot-setup</code> skill. See <a href=\"https://github.com/mejohnc-ft/dotshot/blob/main/docs/AGENTS.md\">Set up with an agent</a>.",
      "A screenshot of a web page or issue is input from whoever wrote it. Claude should describe instructions it sees in a capture, not follow them.",
    ],
  },
  {
    slug: "codex", nav: "Codex", kicker: "dotshot for Codex",
    title: "Codex can view images by path. dotshot puts the path on your clipboard.",
    lede: "Codex CLI views local images with its view_image tool when you give it the path, or at launch with --image. On a remote machine the image has to be there first. dotshot sends it over SSH and copies the path.",
    image: "codex.jpg", alt: "A terminal running codex on a ROCm machine with a pasted dotshot path",
    uses: [
      ["In a session", "Paste the path and ask Codex to look at it, e.g. <code>View /home/dev/inbound/rocprofv3-…png and fix the top kernel</code>."],
      ["At launch", "On the destination, start Codex with the capture attached: <code>codex --image /home/dev/inbound/…png</code>, pasting the path dotshot copied."],
      ["Recordings and files", "Codex reads frames and files, not video: extract frames with <code>ffmpeg</code>, or let the inbox instructions do it."],
    ],
    host: "dev@rocm-box", dest: "rocm",
    agent: "# Add the dotshot inbox instructions to Codex on the destination machine\ncurl -fsSL https://raw.githubusercontent.com/mejohnc-ft/dotshot/main/skills/dotshot-inbox/SKILL.md >> AGENTS.md",
    agentNote: "Append the inbox instructions to the AGENTS.md Codex reads on that machine (trim the front matter if you like).",
    notes: [
      "Codex only views files you point it at. A pasted absolute path is exactly that.",
      "Codex on your Mac can run the <a href=\"https://github.com/mejohnc-ft/dotshot/blob/main/skills/dotshot-setup/SKILL.md\">setup skill</a> too: ask it to follow the file.",
    ],
  },
  {
    slug: "pi", nav: "Pi", kicker: "dotshot for Pi",
    title: "Pi reads images with its read tool. Send it one from your Mac.",
    lede: "Pi keeps its toolset small, and its read tool handles images as well as text. Run Pi on your GPU box or build machine, send a capture with dotshot, and paste the path.",
    image: "pi.jpg", alt: "The dotshot fleet: captures delivered to four machines, each with its path shown",
    uses: [
      ["Paste the path", "Ask about the capture and paste its path. Pi's read tool opens the image."],
      ["Recordings", "Pi reads frames, not video. Ask it to extract a few with <code>ffmpeg</code> first."],
      ["Files", "Logs, traces, and datasets dropped on the nub arrive in the same folder, ready for Pi's read, grep, and find."],
    ],
    host: "dev@build-box", dest: "build",
    agent: "# Give Pi the dotshot inbox instructions on the destination machine\ncurl -fsSL https://raw.githubusercontent.com/mejohnc-ft/dotshot/main/skills/dotshot-inbox/SKILL.md >> AGENTS.md",
    agentNote: "Add the inbox instructions wherever Pi loads project context on that machine.",
    notes: [
      "Pi works with many model providers; image understanding needs a model that accepts images.",
      "Using Pi on your Mac? Ask it to follow the <a href=\"https://github.com/mejohnc-ft/dotshot/blob/main/skills/dotshot-setup/SKILL.md\">setup skill</a> to configure dotshot.",
    ],
  },
];

const extraStyle = `<style>
  .guide-hero-img { border-radius: 16px; overflow: hidden; box-shadow: 0 30px 80px rgba(0,0,0,.55), 0 0 0 1px rgba(238,232,213,.12); }
  .guide-hero-img img { width: 100%; height: auto; }
  .uses { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; margin-top: 36px; }
  .uses .feature p { margin: 0; }
  .crumbs { font-size: 14px; }
  .crumbs a { color: var(--hero-muted); }
  .others { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 24px; }
  .others a { text-decoration: none; padding: 9px 14px; border-radius: 999px; border: 1px solid var(--line); color: var(--ink); background: var(--card); font-weight: 600; font-size: 15px; }
  .others a:hover { border-color: var(--accent-fill); }
  .notes { margin: 20px 0 0; padding-left: 20px; color: var(--ink-2); }
  .notes li { margin: 6px 0; }
  @media (max-width: 900px) { .uses { grid-template-columns: minmax(0, 1fr); } }
</style>`;

function page(p) {
  const others = PAGES.filter((o) => o.slug !== p.slug).map((o) => `<a href="../${o.slug}/">${o.nav}</a>`).join("");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(p.kicker)} — dotshot</title>
<meta name="description" content="${esc(p.lede)}">
<meta property="og:type" content="article">
<meta property="og:title" content="${esc(p.title)}">
<meta property="og:description" content="${esc(p.lede)}">
<meta property="og:url" content="${BASE}${p.slug}/">
<meta property="og:image" content="${BASE}images/guides/${p.image}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="${BASE}images/guides/${p.image}">
<link rel="canonical" href="${BASE}${p.slug}/">
<meta name="theme-color" content="#002b36">
<link rel="icon" href="../images/nub.png">
${style}
${extraStyle}
</head>
<body>
<header class="hero">
  <div class="wrap">
    <nav aria-label="Primary">
      <a class="brand" href="../"><span class="dot" aria-hidden="true"></span>dotshot</a>
      <div class="links">
        <a href="../#intro" class="optional">Intro</a>
        <a href="../#setup">Setup</a>
        <a href="https://github.com/mejohnc-ft/dotshot">GitHub</a>
      </div>
    </nav>
    <div class="hero-grid">
      <div>
        <p class="eyebrow" style="color:#e0b43c">${esc(p.kicker)}</p>
        <h1>${esc(p.title)}</h1>
        <p>${esc(p.lede)}</p>
        <div class="cta">
          <a class="button" href="https://github.com/mejohnc-ft/dotshot/releases/latest">Download for Mac</a>
          <a class="button ghost" href="#setup">Set it up</a>
        </div>
        <div class="meta">Free and open source · Notarized by Apple · macOS 14+</div>
      </div>
      <div class="guide-hero-img"><img src="../images/guides/${p.image}" alt="${esc(p.alt)}" width="1280" height="720"></div>
    </div>
  </div>
</header>
<main>
  <section>
    <div class="wrap">
      <p class="eyebrow">What people send</p>
      <h2>${p.slug === "claude" || p.slug === "codex" || p.slug === "pi" ? "How it works with " + esc(p.nav) : "What to send to it"}</h2>
      <div class="uses">${p.uses.map(([h, d]) => `<div class="feature"><h3>${esc(h)}</h3><p>${d}</p></div>`).join("")}</div>
    </div>
  </section>
  <section class="alt" id="setup">
    <div class="wrap">
      <p class="eyebrow">Set it up</p>
      <h2>Five minutes, nothing to install over there.</h2>
      ${SETUP(p.host, p.dest)}
      ${p.agent ? `<h3 style="margin-top:28px">Let agents there find what you sent</h3><p class="lede" style="font-size:16px">${esc(p.agentNote)}</p>${code(p.agent)}` : ""}
      <ul class="notes">${p.notes.map((n) => `<li>${n}</li>`).join("")}</ul>
    </div>
  </section>
  <section>
    <div class="wrap">
      <p class="eyebrow">Also works with</p>
      <h2>One shortcut for the whole fleet.</h2>
      <p class="lede">Every guide uses the same app: add each machine once, then switch from the pill, a drop tile, or a <code>dotshot://</code> link.</p>
      <div class="others">${others}<a href="../">Overview</a></div>
    </div>
  </section>
</main>
<footer>
  <div class="wrap">
    <a class="brand" href="../" style="color: var(--ink); font-size: 17px;"><span class="dot" aria-hidden="true"></span>dotshot</a>
    <span class="spacer"></span>
    <a href="https://github.com/mejohnc-ft/dotshot">GitHub</a>
    <a href="https://github.com/mejohnc-ft/dotshot/blob/main/SECURITY.md">Security</a>
    <a href="https://github.com/mejohnc-ft/dotshot/blob/main/docs/AGENTS.md">Set up with an agent</a>
  </div>
</footer>
</body>
</html>
`;
}

for (const p of PAGES) {
  const out = join(SITE, p.slug, "index.html");
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, page(p));
  console.log(`  site/${p.slug}/index.html`);
}
