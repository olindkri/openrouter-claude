# openrouter-claude

A `claude` launcher that routes Claude Code through OpenRouter — same idea as
Ollama's `claude` integration, but for any model on OpenRouter.

When you run it without `-m`, it pulls OpenRouter's **live programming
leaderboard** (https://openrouter.ai/rankings/programming) and shows the
top models in an arrow-key picker with name, context, price, and a
description from the OpenRouter catalog. No hardcoded list — it always
reflects what's currently popular on OpenRouter.

---

## One-line install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/olindkri/openrouter-claude/main/install.sh | bash
```

The installer auto-clones the repo to `~/.openrouter-claude`, symlinks
`openrouter-claude` into the first writable PATH dir (Homebrew's `bin`,
`/usr/local/bin`, or `~/.local/bin`), and offers to install `fzf`. Re-run
the same command later to update.

### Windows (PowerShell)

```powershell
$d="$env:TEMP\orc-src"; if(Test-Path $d){rm -r -fo $d}; git clone --depth 1 https://github.com/olindkri/openrouter-claude $d; & "$d\install.ps1"; rm -r -fo $d
```

Zip-only fallback (no `git` required):

```powershell
$z="$env:TEMP\orc.zip"; $d="$env:TEMP\orc-src"; if(Test-Path $d){rm -r -fo $d}; iwr -useb https://github.com/olindkri/openrouter-claude/archive/refs/heads/main.zip -OutFile $z; Expand-Archive -Force $z $d; & "$d\openrouter-claude-main\install.ps1"; rm -r -fo $d,$z
```

After install, open a **new** terminal and run `openrouter-claude`. First
launch prompts for an OpenRouter API key (https://openrouter.ai/keys) and
saves it to `~/.config/openrouter-claude/key` (Mac/Linux) or
`%USERPROFILE%\.openrouter-claude\key` (Windows).

---

## How it works

Claude Code honors three env vars:

- `ANTHROPIC_BASE_URL` — where to send requests
- `ANTHROPIC_AUTH_TOKEN` — bearer token sent on each request
- `ANTHROPIC_MODEL` — model slug

OpenRouter exposes an Anthropic-compatible endpoint at
`https://openrouter.ai/api`. Pointing `ANTHROPIC_BASE_URL` there (with your
OpenRouter key as the auth token) makes Claude Code talk to OpenRouter
natively — no proxy needed.

The picker scrapes the rankings page's RSC payload, sums tokens per
permaslug (same ordering the site shows), maps OpenRouter's dated permaslug
(e.g. `moonshotai/kimi-k2.6-20260420`) to the canonical model id
(`moonshotai/kimi-k2.6`) using `/api/v1/models`, and pulls description,
context length, and price from the catalog. Both feeds are cached for 6h.

## Prereqs

- `claude` CLI: `npm i -g @anthropic-ai/claude-code`
- OpenRouter API key from https://openrouter.ai/keys
- `fzf` (recommended — enables the arrow-key picker; installer offers to
  install it via `brew` / `winget` / `scoop`)
- macOS / Linux: `python3` + `curl` (preinstalled on macOS)
- Windows: PowerShell 5.1+ (preinstalled)

## Usage

```bash
openrouter-claude                          # arrow-key picker (top 25 from leaderboard)
openrouter-claude --list -n 50             # print top 50 as a table, exit
openrouter-claude --view month             # ranking window: day | week | month | trending
openrouter-claude --refresh                # bypass 6h cache
openrouter-claude --list-all               # dump every OpenRouter model

openrouter-claude -m kimi                  # alias -> moonshotai/kimi-k2.6
openrouter-claude -m moonshotai/kimi-k2.6  # full slug
openrouter-claude -- --resume              # forward flags to `claude`
```

In the picker:

- **↑↓** to move, **Enter** to launch, **Esc** to cancel
- Type to filter the list (fuzzy match)
- **Ctrl+A** to change your OpenRouter API key without leaving the picker

Built-in name aliases (for `-m`): `kimi`, `kimi-thinking`, `sonnet`, `opus`,
`haiku`, `deepseek`, `deepseek-flash`, `glm`, `qwen`, `qwen-coder`, `gemma`,
`gemini`, `minimax`, `grok`, `grok-code`, `gpt`, `hy3`. Anything else is
passed through as a literal OpenRouter model slug.

## Uninstall

**macOS / Linux** — remove the symlink and source clone:

```bash
rm -f "$(command -v openrouter-claude)" ~/.config/openrouter-claude/key
# if you cloned to ~/.openrouter-claude:
rm -rf ~/.openrouter-claude
```

**Windows:**

```powershell
& "$env:LOCALAPPDATA\Programs\openrouter-claude\install.ps1" -Uninstall
```

## Web search (no API key)

Claude Code's built-in `WebSearch` tool runs server-side on Anthropic's
infrastructure, so it doesn't work on OpenRouter models. To get search on
*every* model, register the DuckDuckGo MCP server once:

```bash
openrouter-claude --setup-search        # macOS / Linux
openrouter-claude -SetupSearch          # Windows PowerShell
```

This runs `claude mcp add -s user ddg-search -- uvx duckduckgo-mcp-server`.
The server scrapes DuckDuckGo HTML — no account, no key, no quota. Requires
`uv` (recommended; `brew install uv` / `winget install astral-sh.uv`) or
`pipx`. Open a fresh Claude Code session afterward and ask it to search.

## Route through claude-code-router

If you want per-request-type routing (long-context → one model, background
→ another) and proper auto-compaction, install
[claude-code-router](https://github.com/musistudio/claude-code-router):

```bash
npm i -g @musistudio/claude-code-router
ccr start
openrouter-claude --router              # macOS / Linux
openrouter-claude -Router               # Windows PowerShell
```

In router mode the launcher skips the OpenRouter key prompt and model
picker — CCR handles both via its own config (`~/.claude-code-router/config.json`).
Override the port with `--router-port 4567` or `CCR_PORT=4567`. Note: CCR
**cannot** make non-Anthropic models do web search either — that's still a
hard model-capability limit. Use `--setup-search` for that.

## Auto-compaction on non-Anthropic models

Claude Code's built-in auto-compaction is a server-side feature gated by an
Anthropic-only beta header (`context-management-2025-06-27`). OpenRouter
doesn't forward it, so on non-Anthropic models the session would otherwise
just run out of context with no warning.

The launcher works around this by exporting two undocumented Claude Code
env vars before exec'ing `claude`:

- `CLAUDE_CODE_MAX_CONTEXT_TOKENS` — set from the catalog `context_length`
  of the chosen model, capped at 180000 (providers commonly serve less than
  the catalog claims).
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` — fire `/compact` at 75% instead of
  the default ~92%, since alternative models pollute context faster.

Override either by setting the env var yourself before running
`openrouter-claude`. If you're hitting context walls anyway, run `/compact`
manually every 10–15 turns or restart the session.

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
