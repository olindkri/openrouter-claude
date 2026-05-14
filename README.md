# openrouter-claude

A `claude` launcher that routes Claude Code through OpenRouter — same idea as
Ollama's `claude` integration, but for any model on OpenRouter.

When you run it without `-m`, it pulls OpenRouter's **live programming
leaderboard** (https://openrouter.ai/rankings/programming) and shows the
top-N most-used coding models as a numbered picker. No hardcoded list — it
always reflects what's currently popular on OpenRouter.

## How it works

Claude Code honors three env vars:

- `ANTHROPIC_BASE_URL` — where to send requests
- `ANTHROPIC_AUTH_TOKEN` — bearer token sent on each request
- `ANTHROPIC_MODEL` — model slug

OpenRouter exposes an Anthropic-compatible endpoint at
`https://openrouter.ai/api`. Pointing `ANTHROPIC_BASE_URL` there (with your
OpenRouter key as the auth token) makes Claude Code talk to OpenRouter
natively — no proxy needed.

The picker scrapes the rankings page's RSC payload, dedups by model slug,
maps OpenRouter's dated `permaslug` (e.g. `moonshotai/kimi-k2.6-20260420`) to
the canonical model id (`moonshotai/kimi-k2.6`) using `/api/v1/models`, then
joins context length + prompt price for display. Both feeds are cached for 6h
in `~/.config/openrouter-claude/` (Mac/Linux) or
`%USERPROFILE%\.openrouter-claude\` (Windows).

## Prereqs

- `claude` CLI: `npm i -g @anthropic-ai/claude-code`
- OpenRouter API key from https://openrouter.ai/keys
- macOS / Linux: `python3` + `curl` (preinstalled on macOS)
- Windows: PowerShell 5.1+ (preinstalled)

## Install — macOS / Linux

```bash
sudo install -m 0755 openrouter-claude /usr/local/bin/openrouter-claude
# or, no sudo:
mkdir -p ~/.local/bin && cp openrouter-claude ~/.local/bin/ && chmod +x ~/.local/bin/openrouter-claude
```

Provide your key once:

```bash
mkdir -p ~/.config/openrouter-claude
printf %s 'sk-or-v1-...' > ~/.config/openrouter-claude/key
chmod 600 ~/.config/openrouter-claude/key
```

…or export `OPENROUTER_API_KEY` in your shell rc.

## Install — Windows

Run the installer once from PowerShell — it copies the launcher into
`%LOCALAPPDATA%\Programs\openrouter-claude`, adds that directory to your User
PATH so `openrouter-claude` is callable from any cmd/PowerShell/Windows
Terminal session, and offers to install `fzf` for the arrow-key picker:

```powershell
pwsh -ExecutionPolicy Bypass -File .\install.ps1
```

Then open a **new** terminal and run `openrouter-claude`. It will prompt you
for an OpenRouter API key on first launch (https://openrouter.ai/keys) and
save it to `%USERPROFILE%\.openrouter-claude\key`.

To uninstall: `pwsh -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall`.

To install to a custom location:
`pwsh -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir "C:\Tools\orc"`.

## Usage

```bash
openrouter-claude                          # interactive picker (top 25 from leaderboard)
openrouter-claude --list -n 50             # show top 50, exit
openrouter-claude --view month             # ranking window: day | week | month | trending
openrouter-claude --refresh                # bypass 6h cache
openrouter-claude --list-all               # dump every OpenRouter model

openrouter-claude -m kimi                  # alias -> moonshotai/kimi-k2.6
openrouter-claude -m moonshotai/kimi-k2.6  # full slug
openrouter-claude -- --resume              # forward flags to `claude`
```

Sample output (live `--view week`):

```
#    ID                                            CTX     $/M in  NAME
1    google/gemini-2.5-flash-lite              1048576      $0.10  Google: Gemini 2.5 Flash Lite
2    google/gemini-2.5-flash                   1048576      $0.30  Google: Gemini 2.5 Flash
3    google/gemini-3-flash-preview             1048576      $0.50  Google: Gemini 3 Flash Preview
6    deepseek/deepseek-v3.2                     131072      $0.25  DeepSeek: DeepSeek V3.2
7    deepseek/deepseek-v4-flash                1048576      $0.13  DeepSeek: DeepSeek V4 Flash
12   google/gemma-4-31b-it                      262144      $0.12  Google: Gemma 4 31B
17   anthropic/claude-sonnet-4.6               1000000      $3.00  Anthropic: Claude Sonnet 4.6
23   minimax/minimax-m2.7                       196608      $0.28  MiniMax: MiniMax M2.7
27   moonshotai/kimi-k2.6                       262142      $0.74  MoonshotAI: Kimi K2.6
```

Built-in name aliases (for `-m`): `kimi`, `kimi-thinking`, `sonnet`, `opus`,
`haiku`, `deepseek`, `deepseek-flash`, `glm`, `qwen`, `qwen-coder`, `gemma`,
`gemini`, `minimax`, `grok`, `grok-code`, `gpt`. Anything else is passed
through as a literal OpenRouter model slug.

## Caveats

- Tool-use / agentic features depend on the chosen model implementing the
  Anthropic tool schema correctly. Anthropic's own models (Sonnet/Opus/Haiku
  via OpenRouter), Kimi K2.6, GLM 5/5.1, DeepSeek V4, and Qwen3 Coder Plus
  work well; some smaller open models do not.
- Anthropic's prompt caching and 1M-context features only apply on
  Anthropic's first-party endpoint, not via OpenRouter.
- The leaderboard reflects **all** OpenRouter programming traffic — popularity
  ≠ quality. Top entries skew toward cheap/fast models (Gemini Flash, GPT-4o
  mini). Use `--view month` for a steadier signal, or just type a slug.
- Pricing shown is `prompt` USD per million tokens; output tokens cost more.
  See https://openrouter.ai/models for the full sheet.
