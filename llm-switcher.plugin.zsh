# llm-switcher - oh-my-zsh plugin for switching between LLM provider profiles
# Inspired by the oh-my-zsh aws plugin
#
# Configuration file: ~/.llm-switcher (override with LLM_SWITCHER_CONFIG)
#
# Profile format (INI-style):
#
#   [profile_name]
#   provider=openai|anthropic|google|mistral|ollama|custom
#   api_key=your-api-key          (required for all providers except ollama)
#   model=model-name              (optional)
#   base_url=https://...          (optional, for custom or self-hosted endpoints)
#   config_dir=~/.claude-thiink   (optional, path to a tool config directory)
#   config_dir_var=CLAUDE_CONFIG_DIR  (optional, override the default env var for config_dir)
#
# When config_dir is set the plugin exports the directory as an environment
# variable so tools that store their auth in a directory (e.g. Claude Code with
# CLAUDE_CONFIG_DIR) pick it up automatically in the current shell.
#
# Provider defaults for config_dir_var (used when config_dir is set but
# config_dir_var is not explicitly specified):
#   anthropic -> CLAUDE_CONFIG_DIR
#   (all other providers require an explicit config_dir_var)
#
# Supported providers and the environment variables they set:
#   openai    -> OPENAI_API_KEY
#   anthropic -> ANTHROPIC_API_KEY  (+ CLAUDE_CONFIG_DIR when config_dir is set)
#   google    -> GOOGLE_API_KEY, GEMINI_API_KEY
#   mistral   -> MISTRAL_API_KEY
#   ollama    -> OLLAMA_HOST (uses base_url, defaults to http://localhost:11434)
#   custom    -> no provider-specific variable, relies on LLM_API_KEY / LLM_BASE_URL
#
# In all cases the following generic variables are also exported:
#   LLM_PROFILE         - profile name
#   LLM_PROVIDER        - provider name
#   LLM_API_KEY         - api_key value (unset for ollama)
#   LLM_MODEL           - model value (when present in profile)
#   LLM_BASE_URL        - base_url value (when present in profile)
#   LLM_CONFIG_DIR      - config_dir value, ~ expanded (when present in profile)
#   LLM_CONFIG_DIR_VAR  - name of the provider-specific env var that was set for
#                         config_dir (used internally for clean unset on switch)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Return the path to the active config file.
function _llm_config_file() {
  echo "${LLM_SWITCHER_CONFIG:-$HOME/.llm-switcher}"
}

# Read a key from a named section of an INI file.
# Usage: _llm_ini_get <file> <section> <key>
function _llm_ini_get() {
  local file="$1" section="$2" key="$3"
  awk -F '=' -v section="$section" -v key="$key" '
    /^\[/ { in_section = ($0 == "[" section "]") }
    in_section && /^[[:space:]]*[^#;]/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      if ($1 == key) {
        # Rejoin value parts (handles values that themselves contain "=")
        val = ""
        for (i=2; i<=NF; i++) val = (i==2 ? "" : val "=") $i
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        print val
        exit
      }
    }
  ' "$file"
}

# Expand a leading ~ in a path.  We do this manually so it works inside
# double-quoted strings and without eval.
function _llm_expand_tilde() {
  local path="$1"
  [[ "$path" == '~'* ]] && path="${HOME}${path#\~}"
  echo "$path"
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------

# lgp — print the name of the currently active LLM profile.
function lgp() {
  echo "${LLM_PROFILE:-}"
}

# llm_profiles — list all profile names defined in the config file.
function llm_profiles() {
  local config_file
  config_file="$(_llm_config_file)"
  [[ -r "$config_file" ]] || return 1
  grep --color=never -E '^\[.+\]' "$config_file" | sed 's/^\[\(.*\)\]$/\1/'
}

# lsp [profile] — set (switch to) an LLM profile.
# With no argument, clears the current profile and all associated env vars.
function lsp() {
  if [[ -z "$1" ]]; then
    # Unset the config-dir var that was set by the previous profile, if any.
    if [[ -n "${LLM_CONFIG_DIR_VAR:-}" ]]; then
      unset "$LLM_CONFIG_DIR_VAR"
    fi
    unset LLM_PROFILE LLM_PROVIDER LLM_API_KEY LLM_MODEL LLM_BASE_URL
    unset LLM_CONFIG_DIR LLM_CONFIG_DIR_VAR
    unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
    unset MISTRAL_API_KEY OLLAMA_HOST
    _llm_clear_state
    echo "LLM profile cleared."
    return
  fi

  local config_file
  config_file="$(_llm_config_file)"

  if [[ ! -r "$config_file" ]]; then
    echo "${fg[red]}Config file not found: $config_file${reset_color}" >&2
    echo "Create it with at least one [profile] section. See README for details." >&2
    return 1
  fi

  local -a available_profiles
  available_profiles=($(llm_profiles))

  if [[ -z "${available_profiles[(r)$1]}" ]]; then
    echo "${fg[red]}Profile '$1' not found in '$config_file'${reset_color}" >&2
    echo "Available profiles: ${(j:, :)available_profiles:-none}${reset_color}" >&2
    return 1
  fi

  local profile="$1"
  local provider api_key model base_url config_dir config_dir_var

  provider="$(_llm_ini_get       "$config_file" "$profile" provider)"
  api_key="$(_llm_ini_get        "$config_file" "$profile" api_key)"
  model="$(_llm_ini_get          "$config_file" "$profile" model)"
  base_url="$(_llm_ini_get       "$config_file" "$profile" base_url)"
  config_dir="$(_llm_ini_get     "$config_file" "$profile" config_dir)"
  config_dir_var="$(_llm_ini_get "$config_file" "$profile" config_dir_var)"

  if [[ -z "$provider" ]]; then
    echo "${fg[yellow]}Warning: no 'provider' set for profile '$profile'. Defaulting to 'custom'.${reset_color}" >&2
    provider="custom"
  fi

  # Unset the config-dir env var that the *previous* profile set (if any)
  # before we potentially set a different one below.
  if [[ -n "${LLM_CONFIG_DIR_VAR:-}" ]]; then
    unset "$LLM_CONFIG_DIR_VAR"
  fi

  # Always export generic variables.
  export LLM_PROFILE="$profile"
  export LLM_PROVIDER="$provider"

  if [[ -n "$api_key" ]]; then
    export LLM_API_KEY="$api_key"
  else
    unset LLM_API_KEY
  fi

  if [[ -n "$model" ]]; then
    export LLM_MODEL="$model"
  else
    unset LLM_MODEL
  fi

  if [[ -n "$base_url" ]]; then
    export LLM_BASE_URL="$base_url"
  else
    unset LLM_BASE_URL
  fi

  # Handle config_dir -------------------------------------------------------
  # Expand ~ and export both the generic LLM_CONFIG_DIR and the
  # provider-specific (or explicitly named) env var.
  if [[ -n "$config_dir" ]]; then
    local expanded_dir
    expanded_dir="$(_llm_expand_tilde "$config_dir")"
    export LLM_CONFIG_DIR="$expanded_dir"

    # Resolve which env var name to use for this provider.
    if [[ -z "$config_dir_var" ]]; then
      case "$provider" in
        anthropic) config_dir_var="CLAUDE_CONFIG_DIR" ;;
        *)         config_dir_var="" ;;
      esac
    fi

    if [[ -n "$config_dir_var" ]]; then
      export "$config_dir_var"="$expanded_dir"
      export LLM_CONFIG_DIR_VAR="$config_dir_var"
    else
      unset LLM_CONFIG_DIR_VAR
    fi
  else
    unset LLM_CONFIG_DIR LLM_CONFIG_DIR_VAR
  fi

  # Export provider-specific API-key variables and clean up stale ones.
  unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY MISTRAL_API_KEY OLLAMA_HOST

  case "$provider" in
    openai)
      [[ -n "$api_key" ]] && export OPENAI_API_KEY="$api_key"
      ;;
    anthropic)
      [[ -n "$api_key" ]] && export ANTHROPIC_API_KEY="$api_key"
      ;;
    google)
      [[ -n "$api_key" ]] && export GOOGLE_API_KEY="$api_key" && export GEMINI_API_KEY="$api_key"
      ;;
    mistral)
      [[ -n "$api_key" ]] && export MISTRAL_API_KEY="$api_key"
      ;;
    ollama)
      export OLLAMA_HOST="${base_url:-http://localhost:11434}"
      ;;
    custom)
      # No provider-specific variable; consumers rely on LLM_API_KEY / LLM_BASE_URL.
      ;;
    *)
      echo "${fg[yellow]}Warning: unknown provider '$provider'. Only generic LLM_* variables will be set.${reset_color}" >&2
      ;;
  esac

  _llm_update_state

  echo "Switched to LLM profile: $profile (provider: $provider)"
}

# ---------------------------------------------------------------------------
# State persistence (survives new shell sessions)
#
# The state file uses KEY=VALUE lines (one per variable) so that values
# containing spaces or special characters — such as directory paths — are
# stored and restored correctly.
# ---------------------------------------------------------------------------

function _llm_state_file() {
  echo "${LLM_STATE_FILE:-/tmp/.llm_current_profile}"
}

function _llm_update_state() {
  [[ "${LLM_PROFILE_STATE_ENABLED:-true}" == true ]] || return 0
  local sf
  sf="$(_llm_state_file)"
  [[ -d "$(dirname "$sf")" ]] || return 1
  {
    printf 'LLM_PROFILE=%s\n'        "${LLM_PROFILE}"
    printf 'LLM_PROVIDER=%s\n'       "${LLM_PROVIDER}"
    printf 'LLM_MODEL=%s\n'          "${LLM_MODEL:-}"
    printf 'LLM_BASE_URL=%s\n'       "${LLM_BASE_URL:-}"
    printf 'LLM_API_KEY=%s\n'        "${LLM_API_KEY:-}"
    printf 'LLM_CONFIG_DIR=%s\n'     "${LLM_CONFIG_DIR:-}"
    printf 'LLM_CONFIG_DIR_VAR=%s\n' "${LLM_CONFIG_DIR_VAR:-}"
  } > "$sf"
}

function _llm_clear_state() {
  [[ "${LLM_PROFILE_STATE_ENABLED:-true}" == true ]] || return 0
  local sf
  sf="$(_llm_state_file)"
  [[ -d "$(dirname "$sf")" ]] || return 1
  : > "$sf"
}

# ---------------------------------------------------------------------------
# Prompt integration
# ---------------------------------------------------------------------------

# llm_prompt_info — emit a short string suitable for inclusion in $PROMPT / $RPROMPT.
function llm_prompt_info() {
  [[ -z "$LLM_PROFILE" ]] && return

  local info
  info="${ZSH_THEME_LLM_PROFILE_PREFIX:-<llm:}${LLM_PROFILE}${ZSH_THEME_LLM_PROFILE_SUFFIX:->}"

  if [[ -n "$LLM_MODEL" ]]; then
    info+="${ZSH_THEME_LLM_DIVIDER:- }${ZSH_THEME_LLM_MODEL_PREFIX:-[}${LLM_MODEL}${ZSH_THEME_LLM_MODEL_SUFFIX:-]}"
  fi

  echo "$info"
}

if [[ "${SHOW_LLM_PROMPT:-true}" != false && "$RPROMPT" != *'$(llm_prompt_info)'* ]]; then
  RPROMPT='$(llm_prompt_info)'"$RPROMPT"
fi

# ---------------------------------------------------------------------------
# Tab completion
# ---------------------------------------------------------------------------

function _llm_profiles() {
  reply=($(llm_profiles))
}
compctl -K _llm_profiles lsp

# ---------------------------------------------------------------------------
# Restore state from previous session on shell start
# ---------------------------------------------------------------------------

if [[ "${LLM_PROFILE_STATE_ENABLED:-true}" == true ]]; then
  local _llm_state_path
  _llm_state_path="$(_llm_state_file)"
  if [[ -s "$_llm_state_path" ]]; then
    # Parse KEY=VALUE lines; skip blank lines.
    local _llm_key _llm_val _llm_line
    while IFS= read -r _llm_line; do
      [[ -z "$_llm_line" ]] && continue
      _llm_key="${_llm_line%%=*}"
      _llm_val="${_llm_line#*=}"
      case "$_llm_key" in
        LLM_PROFILE|LLM_PROVIDER|LLM_MODEL|LLM_BASE_URL|LLM_API_KEY|LLM_CONFIG_DIR|LLM_CONFIG_DIR_VAR)
          [[ -n "$_llm_val" ]] && export "$_llm_key"="$_llm_val"
          ;;
      esac
    done < "$_llm_state_path"

    # Re-apply provider-specific API-key variable.
    case "${LLM_PROVIDER:-}" in
      openai)    [[ -n "${LLM_API_KEY:-}" ]] && export OPENAI_API_KEY="$LLM_API_KEY" ;;
      anthropic) [[ -n "${LLM_API_KEY:-}" ]] && export ANTHROPIC_API_KEY="$LLM_API_KEY" ;;
      google)    [[ -n "${LLM_API_KEY:-}" ]] && export GOOGLE_API_KEY="$LLM_API_KEY" && export GEMINI_API_KEY="$LLM_API_KEY" ;;
      mistral)   [[ -n "${LLM_API_KEY:-}" ]] && export MISTRAL_API_KEY="$LLM_API_KEY" ;;
      ollama)    export OLLAMA_HOST="${LLM_BASE_URL:-http://localhost:11434}" ;;
    esac

    # Re-apply the config-dir env var if one was saved.
    if [[ -n "${LLM_CONFIG_DIR:-}" && -n "${LLM_CONFIG_DIR_VAR:-}" ]]; then
      export "$LLM_CONFIG_DIR_VAR"="$LLM_CONFIG_DIR"
    fi
  fi
  unset _llm_state_path _llm_key _llm_val _llm_line
fi
