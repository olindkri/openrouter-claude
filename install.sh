#!/usr/bin/env bash
# install.sh — install openrouter-claude on macOS/Linux so it runs from any terminal.
# Idempotent: re-run to update. Use INSTALL_DIR=... to override location.

set -euo pipefail

# Resolve script's own directory (works whether called via path, symlink, or curl|bash)
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SRC_DIR="$(pwd)"
fi
LAUNCHER="$SRC_DIR/openrouter-claude"

# Pick an install dir: explicit override > first writable PATH dir among the candidates.
INSTALL_DIR="${INSTALL_DIR:-}"
if [ -z "$INSTALL_DIR" ]; then
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
    if [ -d "$d" ] && [ -w "$d" ]; then INSTALL_DIR="$d"; break; fi
    if [ ! -d "$d" ] && [ "$d" = "$HOME/.local/bin" ]; then INSTALL_DIR="$d"; break; fi
  done
fi
[ -z "$INSTALL_DIR" ] && INSTALL_DIR="$HOME/.local/bin"

mkdir -p "$INSTALL_DIR"

REPO_URL="${OPENROUTER_CLAUDE_REPO:-https://github.com/olindkri/openrouter-claude}"

# If launched standalone (e.g. curl|bash), clone the repo to a persistent location.
if [ ! -f "$LAUNCHER" ]; then
  CLONE_DIR="${OPENROUTER_CLAUDE_DIR:-$HOME/.openrouter-claude}"
  if [ -d "$CLONE_DIR/.git" ]; then
    echo "Updating existing clone: $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only --quiet || true
  else
    echo "Cloning $REPO_URL -> $CLONE_DIR"
    rm -rf "$CLONE_DIR"
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" >/dev/null
  fi
  SRC_DIR="$CLONE_DIR"
  LAUNCHER="$SRC_DIR/openrouter-claude"
fi

if [ ! -f "$LAUNCHER" ]; then
  echo "install.sh: openrouter-claude launcher not found (looked in $SRC_DIR)" >&2
  exit 1
fi

# Symlink so future `git pull` in the source dir updates the command for free.
ln -sf "$LAUNCHER" "$INSTALL_DIR/openrouter-claude"
chmod +x "$LAUNCHER"

echo "Installed: $INSTALL_DIR/openrouter-claude -> $LAUNCHER"

# PATH sanity
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo ""
    echo "WARN: $INSTALL_DIR is not on your PATH."
    case "$INSTALL_DIR" in
      "$HOME/.local/bin")
        echo "  Add to your shell rc:"
        echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc   # or ~/.bashrc"
        ;;
      *)
        echo "  Add to your shell rc:"
        echo "    echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc"
        ;;
    esac
    ;;
esac

# claude CLI check
if ! command -v claude >/dev/null 2>&1; then
  echo ""
  echo "WARN: 'claude' CLI not found on PATH."
  echo "  install:  npm i -g @anthropic-ai/claude-code"
fi

# fzf check (offer to install via brew)
if ! command -v fzf >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo ""
    printf "Install fzf via Homebrew for arrow-key picker? [Y/n] "
    read -r ANS </dev/tty || ANS=""
    case "$ANS" in
      n|N|no|NO) echo "  skipped (you can install later with: brew install fzf)" ;;
      *)         brew install fzf ;;
    esac
  else
    echo ""
    echo "Tip: install fzf for arrow-key model picking. (e.g. apt install fzf, dnf install fzf, brew install fzf)"
  fi
fi

echo ""
echo "Done. Open a new terminal and run: openrouter-claude"
echo "On first launch you'll be prompted for an OpenRouter API key (https://openrouter.ai/keys)."
