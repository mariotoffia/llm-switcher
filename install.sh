#!/usr/bin/env sh
# install.sh - install llm-switcher and run an auto-config probe.
#
# One-liner install (no checkout needed):
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/mariotoffia/llm-switcher/main/install.sh)"
#
# Or from a local checkout:
#   ./install.sh
#
# Flags:
#   --modify-zshrc       Add 'llm-switcher' to plugins=(...) in ~/.zshrc (default: off)
#   --force              Overwrite an existing config file
#   --no-autoconfig      Skip the auto-config probe
#   --autoconfig-only    Skip plugin install; just (re-)run auto-config
#   --plugins-dir DIR    Override install location (default: $ZSH_CUSTOM/plugins)
#   --config FILE        Override config file path (default: ~/.llm-switcher)
#   --repo URL           Override the git repo URL to clone from
#   -h, --help           Show this help

set -eu

REPO_URL="${LLM_SWITCHER_REPO:-https://github.com/mariotoffia/llm-switcher.git}"
PLUGIN_NAME=llm-switcher

MODIFY_ZSHRC=0
FORCE=0
NO_AUTOCONFIG=0
AUTOCONFIG_ONLY=0
PLUGINS_DIR=""
CONFIG_FILE="${LLM_SWITCHER_CONFIG:-$HOME/.llm-switcher}"

while [ $# -gt 0 ]; do
  case "$1" in
    --modify-zshrc)    MODIFY_ZSHRC=1 ;;
    --force)           FORCE=1 ;;
    --no-autoconfig)   NO_AUTOCONFIG=1 ;;
    --autoconfig-only) AUTOCONFIG_ONLY=1 ;;
    --plugins-dir)     PLUGINS_DIR="$2"; shift ;;
    --config)          CONFIG_FILE="$2"; shift ;;
    --repo)            REPO_URL="$2"; shift ;;
    -h|--help)
      awk '/^# install\.sh/,/^$/{ sub(/^# ?/,""); print }' "$0" 2>/dev/null \
        || sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'install.sh: unknown flag: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
PLUGINS_DIR="${PLUGINS_DIR:-$ZSH_CUSTOM_DIR/plugins}"
INSTALL_DIR="$PLUGINS_DIR/$PLUGIN_NAME"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# 1. Install the plugin (clone or symlink)
# ---------------------------------------------------------------------------
install_plugin() {
  mkdir -p "$PLUGINS_DIR"
  script_dir=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || script_dir=""
  if [ -n "$script_dir" ] && [ -f "$script_dir/$PLUGIN_NAME.plugin.zsh" ]; then
    log "Linking $script_dir -> $INSTALL_DIR"
    if [ -e "$INSTALL_DIR" ] && [ ! -L "$INSTALL_DIR" ]; then
      err "$INSTALL_DIR exists and is not a symlink; remove it or pass --plugins-dir."
    fi
    ln -snf "$script_dir" "$INSTALL_DIR"
  else
    log "Cloning $REPO_URL -> $INSTALL_DIR"
    have git || err "git is required to clone the plugin (or run install.sh from a checkout)"
    if [ -d "$INSTALL_DIR/.git" ]; then
      ( cd "$INSTALL_DIR" && git pull --ff-only )
    elif [ -e "$INSTALL_DIR" ]; then
      err "$INSTALL_DIR exists. Remove it or pass --plugins-dir."
    else
      git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    fi
  fi
  log "Plugin installed at $INSTALL_DIR"
}

# ---------------------------------------------------------------------------
# 2. (optional) Add to plugins=(...) in ~/.zshrc
# ---------------------------------------------------------------------------
modify_zshrc() {
  zshrc="$HOME/.zshrc"
  if [ ! -f "$zshrc" ]; then
    warn "no ~/.zshrc; skipping plugins= edit"
    return 0
  fi
  if grep -qE 'plugins=\([^)]*\bllm-switcher\b[^)]*\)' "$zshrc"; then
    log "llm-switcher already present in plugins=(...) in $zshrc"
    return 0
  fi
  if ! grep -qE '^plugins=\(' "$zshrc"; then
    warn "no plugins=(...) line in $zshrc; add it manually"
    return 0
  fi
  ts=$(date +%Y%m%d-%H%M%S)
  cp "$zshrc" "$zshrc.bak.$ts"
  sed -i.tmp -E 's/^(plugins=\([^)]*)/\1 llm-switcher/' "$zshrc"
  rm -f "$zshrc.tmp"
  log "Added llm-switcher to plugins=(...) in $zshrc (backup: $zshrc.bak.$ts)"
}

# ---------------------------------------------------------------------------
# 3. Auto-config: probe for installed CLIs, dirs, and env vars; emit profiles
# ---------------------------------------------------------------------------
MEMBERS=""
add_member() {
  if [ -z "$MEMBERS" ]; then MEMBERS="$1"; else MEMBERS="$MEMBERS, $1"; fi
}

probe_anthropic() {
  if [ -d "$HOME/.claude" ] || have claude; then
    {
      printf '\n[claude]\n'
      printf 'provider=anthropic\n'
      [ -d "$HOME/.claude" ] && printf 'config_dir=~/.claude\n'
      [ -n "${ANTHROPIC_API_KEY:-}" ] && printf 'api_key=%s\n' "$ANTHROPIC_API_KEY"
    } >> "$AUTOCONFIG_TMP"
    add_member claude
  elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    { printf '\n[anthropic]\nprovider=anthropic\napi_key=%s\n' "$ANTHROPIC_API_KEY"; } >> "$AUTOCONFIG_TMP"
    add_member anthropic
  fi
}

probe_codex() {
  if [ -d "$HOME/.codex" ] || have codex; then
    {
      printf '\n[codex]\n'
      printf 'provider=codex\n'
      [ -d "$HOME/.codex" ] && printf 'config_dir=~/.codex\n'
      [ -n "${OPENAI_API_KEY:-}" ] && printf 'api_key=%s\n' "$OPENAI_API_KEY"
    } >> "$AUTOCONFIG_TMP"
    add_member codex
  fi
}

probe_copilot() {
  if [ -d "$HOME/.config/gh" ] || [ -d "$HOME/.copilot" ] || have gh; then
    {
      printf '\n[copilot]\n'
      printf 'provider=copilot\n'
      if [ -d "$HOME/.config/gh" ]; then
        printf 'config_dir=~/.config/gh\n'
      elif [ -d "$HOME/.copilot" ]; then
        printf 'config_dir=~/.copilot\n'
      fi
    } >> "$AUTOCONFIG_TMP"
    add_member copilot
  fi
}

probe_openai_key() {
  # Only emit a separate [openai] entry if codex didn't already cover the key.
  if [ -n "${OPENAI_API_KEY:-}" ] && ! [ -d "$HOME/.codex" ] && ! have codex; then
    { printf '\n[openai]\nprovider=openai\napi_key=%s\n' "$OPENAI_API_KEY"; } >> "$AUTOCONFIG_TMP"
    add_member openai
  fi
}

probe_google() {
  ggk="${GOOGLE_API_KEY:-${GEMINI_API_KEY:-}}"
  if [ -n "$ggk" ]; then
    { printf '\n[google]\nprovider=google\napi_key=%s\n' "$ggk"; } >> "$AUTOCONFIG_TMP"
    add_member google
  fi
}

probe_mistral() {
  if [ -n "${MISTRAL_API_KEY:-}" ]; then
    { printf '\n[mistral]\nprovider=mistral\napi_key=%s\n' "$MISTRAL_API_KEY"; } >> "$AUTOCONFIG_TMP"
    add_member mistral
  fi
}

probe_ollama() {
  if [ -n "${OLLAMA_HOST:-}" ] || have ollama; then
    {
      printf '\n[ollama]\n'
      printf 'provider=ollama\n'
      [ -n "${OLLAMA_HOST:-}" ] && printf 'base_url=%s\n' "$OLLAMA_HOST"
    } >> "$AUTOCONFIG_TMP"
    add_member ollama
  fi
}

probe_third_party() {
  for entry in groq:GROQ_API_KEY xai:XAI_API_KEY openrouter:OPENROUTER_API_KEY \
               deepseek:DEEPSEEK_API_KEY perplexity:PERPLEXITY_API_KEY cohere:COHERE_API_KEY; do
    name="${entry%%:*}"; var="${entry##*:}"
    val=$(eval "printf '%s' \"\${$var:-}\"")
    if [ -n "$val" ]; then
      { printf '\n[%s]\nprovider=%s\napi_key=%s\n' "$name" "$name" "$val"; } >> "$AUTOCONFIG_TMP"
      add_member "$name"
    fi
  done
}

autoconfig() {
  if [ -e "$CONFIG_FILE" ] && [ "$FORCE" -ne 1 ]; then
    err "$CONFIG_FILE already exists. Pass --force to overwrite, or --no-autoconfig to skip."
  fi

  AUTOCONFIG_TMP=$(mktemp 2>/dev/null || mktemp -t llm-switcher)
  trap 'rm -f "$AUTOCONFIG_TMP"' EXIT INT TERM HUP

  cat > "$AUTOCONFIG_TMP" <<EOF
# llm-switcher config, generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S').
# This file may contain API keys; chmod 600 is set on creation.
# Edit freely, then activate with 'lsp <profile>' or 'lsp default'.
EOF

  probe_anthropic
  probe_codex
  probe_copilot
  probe_openai_key
  probe_google
  probe_mistral
  probe_ollama
  probe_third_party

  if [ -n "$MEMBERS" ]; then
    {
      printf '\n[group:default]\n'
      printf 'members=%s\n' "$MEMBERS"
    } >> "$AUTOCONFIG_TMP"
  fi

  # Move into place atomically; chmod 600 before mv when target dir is shared.
  chmod 600 "$AUTOCONFIG_TMP"
  mv "$AUTOCONFIG_TMP" "$CONFIG_FILE"
  trap - EXIT INT TERM HUP

  log "Wrote $CONFIG_FILE (chmod 600)"
  if [ -n "$MEMBERS" ]; then
    log "Detected profiles: $MEMBERS"
    log "Activate them all with: lsp default"
  else
    warn "No providers detected. Edit $CONFIG_FILE by hand or rerun after installing a CLI / setting an API key."
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
if [ "$AUTOCONFIG_ONLY" -ne 1 ]; then
  install_plugin
  [ "$MODIFY_ZSHRC" -eq 1 ] && modify_zshrc
fi

if [ "$NO_AUTOCONFIG" -ne 1 ]; then
  autoconfig
fi

cat <<EOF

Done.
EOF
if [ "$AUTOCONFIG_ONLY" -ne 1 ] && [ "$MODIFY_ZSHRC" -ne 1 ]; then
  cat <<EOF
  Add 'llm-switcher' to plugins=(...) in your ~/.zshrc, then:
    source ~/.zshrc
EOF
fi
cat <<EOF
  Try:
    lgp           # list active slots
    llm_profiles  # list available profiles in $CONFIG_FILE
    lsp default   # activate every detected provider (if a [group:default] was generated)
EOF
