# Set up dotshot with your agent

Your coding agent can do most of dotshot's setup: find your machines, check SSH, create private inbound
folders, and send a test file. The only step it can't do is grant Screen Recording permission. That one's
yours, in dotshot's first setup screen.

## On your Mac: let the agent configure dotshot

Install the `dotshot-setup` skill, then ask for what you want:

```bash
mkdir -p ~/.claude/skills/dotshot-setup
curl -fsSL https://raw.githubusercontent.com/mejohnc-ft/dotshot/main/skills/dotshot-setup/SKILL.md \
  -o ~/.claude/skills/dotshot-setup/SKILL.md
```

> Set up dotshot so my screenshots can reach my agents on spark, rocm, and nas.

Using Codex, Pi, or another agent? Point it at the skill instead:

> Follow https://github.com/mejohnc-ft/dotshot/blob/main/skills/dotshot-setup/SKILL.md to set up dotshot for my machines.

The agent uses the script inside the app, which you can also run yourself:

```bash
DS=/Applications/dotshot.app/Contents/Resources/dotshot-capture.sh
"$DS" add spark spark '~/inbound'     # validate and save a destination
"$DS" check spark                     # host, key, private folder, SFTP; saves the absolute folder
"$DS" send spark ./notes.txt          # deliver a file; the remote path is on your clipboard
"$DS" list
```

The skill never turns off host-key checking, never accepts an unknown host key for you, and never copies
private keys. When a host key is new or a key is rejected, it tells you what to run.

## On each destination: let agents find what you sent

Install the `dotshot-inbox` skill where your agents run. Then "look at the screenshot I just sent" works
without pasting a path, and recordings are turned into frames the model can read.

```bash
# Claude Code
mkdir -p ~/.claude/skills/dotshot-inbox
curl -fsSL https://raw.githubusercontent.com/mejohnc-ft/dotshot/main/skills/dotshot-inbox/SKILL.md \
  -o ~/.claude/skills/dotshot-inbox/SKILL.md
```

For Codex or Pi, paste the body of
[`skills/dotshot-inbox/SKILL.md`](../skills/dotshot-inbox/SKILL.md) into that machine's `AGENTS.md`.

## How each agent reads a delivered path

| Agent | Images | Recordings |
| --- | --- | --- |
| Claude Code | Paste the path into your prompt; Claude reads it | Ask it to pull frames with `ffmpeg` (the inbox skill does this) |
| Codex CLI | Paste the path and ask Codex to view it (`view_image`), or start with `codex --image <path>` | Same: frames first |
| Pi | Paste the path; Pi's `read` tool handles images | Same: frames first |
