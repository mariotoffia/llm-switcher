# llm-switcher - oh-my-zsh plugin for switching between LLM provider profiles
# Inspired by the oh-my-zsh aws plugin
#
# Configuration file: ~/.llm-switcher (override with LLM_SWITCHER_CONFIG)
#
# Profile format (INI-style):
#
#   [profile_name]
#   provider=openai|anthropic|google|mistral|ollama|custom
#   api_key=your-api-key            (optional)
#   config_dir=~/.claude-work       (optional, path to a tool config directory)
#   config_dir_var=CLAUDE_CONFIG_DIR (optional, override default env var for config_dir)
#   model=model-name                (optional)
#   base_url=https://...            (optional, for custom or self-hosted endpoints)
#   login_cmd=claude login          (optional, override the login command)
#   logout_cmd=claude logout        (optional, override the logout command)
#
# api_key and config_dir are both optional and fully independent.  You can use:
#   - only config_dir  (directory-based auth, e.g. after `lsp <profile> login`)
#   - only api_key     (traditional key-based auth)
#   - both             (rare, but supported)
#   - neither          (valid for ollama and custom providers)
#
# Subcommand usage:
#   lsp <profile>         - switch to profile (set env vars in current shell)
#   lsp <profile> login   - switch to profile, create config_dir, run login_cmd
#   lsp <profile> logout  - switch to profile, run logout_cmd
#   lsp                   - clear current profile (unset all LLM_* vars)
#
# When config_dir is set the plugin exports the directory as an environment
# variable so tools that store their auth in a directory (e.g. Claude Code
# using CLAUDE_CONFIG_DIR) pick it up automatically in the current shell.
#
# Provider defaults for config_dir_var (when config_dir is set but
# config_dir_var is not explicitly specified):
#   anthropic -> CLAUDE_CONFIG_DIR
#   (all other providers require an explicit config_dir_var)
#
# Provider defaults for login_cmd / logout_cmd (when not specified in profile):
#   anthropic -> login: claude login   logout: claude logout
#   (all other providers require explicit login_cmd / logout_cmd)
#
# Environment variables exported per provider:
#   openai    -> OPENAI_API_KEY
#   anthropic -> ANTHROPIC_API_KEY  (+ CLAUDE_CONFIG_DIR when config_dir is set)
#   google    -> GOOGLE_API_KEY, GEMINI_API_KEY
#   mistral   -> MISTRAL_API_KEY
#   ollama    -> OLLAMA_HOST (uses base_url, defaults to http://localhost:11434)
#   custom    -> no provider-specific variable; relies on LLM_API_KEY / LLM_BASE_URL
#
# Generic variables exported for every profile:
#   LLM_PROFILE         - profile name
#   LLM_PROVIDER        - provider name
#   LLM_API_KEY         - api_key value (when present)
#   LLM_MODEL           - model value (when present)
#   LLM_BASE_URL        - base_url value (when present)
#   LLM_CONFIG_DIR      - config_dir value, ~ expanded (when present)
#   LLM_CONFIG_DIR_VAR  - name of the provider-specific env var set for config_dir
#                         (tracked so it is cleanly unset when switching profiles)

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

# Expand a leading ~ in a path without using eval.
function _llm_expand_tilde() {
  local path="$1"
  [[ "$path" == '~'* ]] && path="${HOME}${path#\~}"
  echo "$path"
}

# Return the default login command for a provider, or empty string if none.
function _llm_default_login_cmd() {
  case "$1" in
    anthropic) echo "claude login" ;;
    *)         echo "" ;;
  esac
}

# Return the default logout command for a provider, or empty string if none.
function _llm_default_logout_cmd() {
  case "$1" in
    anthropic) echo "claude logout" ;;
    *)         echo "" ;;
  esac
}

# Apply all environment variables for a profile.
# This is the single shared code path used by plain switch, login, and logout.
# Usage: _llm_apply_profile <profile> <provider> <api_key> <model> <base_url> \
#                            <config_dir> <config_dir_var>
function _llm_apply_profile() {
  local profile="$1"
  local provider="$2"
  local api_key="$3"
  local model="$4"
  local base_url="$5"
  local config_dir="$6"
  local config_dir_var="$7"

  # Unset the provider-specific config-dir var that the *previous* profile set.
  if [[ -n "${LLM_CONFIG_DIR_VAR:-}" ]]; then
    unset "$LLM_CONFIG_DIR_VAR"
  fi

  export LLM_PROFILE="$profile"
  export LLM_PROVIDER="$provider"

  # API key (optional) -------------------------------------------------------
  if [[ -n "$api_key" ]]; then
    export LLM_API_KEY="$api_key"
  else
    unset LLM_API_KEY
  fi

  # Model (optional) ---------------------------------------------------------
  if [[ -n "$model" ]]; then
    export LLM_MODEL="$model"
  else
    unset LLM_MODEL
  fi

  # Base URL (optional) ------------------------------------------------------
  if [[ -n "$base_url" ]]; then
    export LLM_BASE_URL="$base_url"
  else
    unset LLM_BASE_URL
  fi

  # Config directory (optional, first-class) ---------------------------------
  # Profiles that authenticate via a managed config directory (e.g. after
  # `lsp <profile> login`) may supply config_dir with no api_key at all.
  if [[ -n "$config_dir" ]]; then
    local expanded_dir
    expanded_dir="$(_llm_expand_tilde "$config_dir")"
    export LLM_CONFIG_DIR="$expanded_dir"

    # Resolve which provider-specific env var name to use.
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

  # Provider-specific API-key variables --------------------------------------
  # Clear any stale vars from the previous profile first.
  unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY MISTRAL_API_KEY OLLAMA_HOST

  case "$provider" in
    openai)
      [[ -n "$api_key" ]] && export OPENAI_API_KEY="$api_key"
      ;;
    anthropic)
      [[ -n "$api_key" ]] && export ANTHROPIC_API_KEY="$api_key"
      ;;
    google)
      if [[ -n "$api_key" ]]; then
        export GOOGLE_API_KEY="$api_key"
        export GEMINI_API_KEY="$api_key"
      fi
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
  grep --color=never -E '^\[[^][:space:]][^]]*\]$' "$config_file" | sed 's/^\[\(.*\)\]$/\1/'
}

# lsp [profile [login|logout]] — manage LLM profiles.
#
#   lsp                    clear current profile (unset all LLM_* vars)
#   lsp <profile>          switch to profile
#   lsp <profile> login    switch to profile and run its login command
#   lsp <profile> logout   switch to profile and run its logout command
#
function lsp() {
  # Use ${1:-} so calling lsp with no arguments is safe under zsh nounset.
  if [[ -z "${1:-}" ]]; then
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
  local subcommand="${2:-}"

  local provider api_key model base_url config_dir config_dir_var login_cmd logout_cmd

  provider="$(_llm_ini_get       "$config_file" "$profile" provider)"
  api_key="$(_llm_ini_get        "$config_file" "$profile" api_key)"
  model="$(_llm_ini_get          "$config_file" "$profile" model)"
  base_url="$(_llm_ini_get       "$config_file" "$profile" base_url)"
  config_dir="$(_llm_ini_get     "$config_file" "$profile" config_dir)"
  config_dir_var="$(_llm_ini_get "$config_file" "$profile" config_dir_var)"
  login_cmd="$(_llm_ini_get      "$config_file" "$profile" login_cmd)"
  logout_cmd="$(_llm_ini_get     "$config_file" "$profile" logout_cmd)"

  if [[ -z "$provider" ]]; then
    echo "${fg[yellow]}Warning: no 'provider' set for profile '$profile'. Defaulting to 'custom'.${reset_color}" >&2
    provider="custom"
  fi

  case "$subcommand" in

    # -- plain switch --------------------------------------------------------
    "")
      _llm_apply_profile "$profile" "$provider" "$api_key" "$model" \
                         "$base_url" "$config_dir" "$config_dir_var"
      echo "Switched to LLM profile: $profile (provider: $provider)"
      ;;

    # -- login ---------------------------------------------------------------
    login)
      _llm_apply_profile "$profile" "$provider" "$api_key" "$model" \
                         "$base_url" "$config_dir" "$config_dir_var"
      echo "Switched to LLM profile: $profile (provider: $provider)"

      # Resolve the login command (profile override > provider default).
      if [[ -z "$login_cmd" ]]; then
        login_cmd="$(_llm_default_login_cmd "$provider")"
      fi
      if [[ -z "$login_cmd" ]]; then
        echo "${fg[red]}No login_cmd configured for profile '$profile' (provider: $provider).${reset_color}" >&2
        echo "Add 'login_cmd=<command>' to the [$profile] section of $config_file." >&2
        return 1
      fi

      # Ensure the config directory exists before the login command tries to
      # write credentials into it.
      if [[ -n "${LLM_CONFIG_DIR:-}" ]]; then
        mkdir -p "$LLM_CONFIG_DIR"
      fi

      echo "Running: $login_cmd"
      # Use zsh word-splitting (${(z)...}) instead of eval to avoid interpreting
      # shell metacharacters from the config file.  This safely handles quoted
      # arguments (e.g. login_cmd=claude login) without injection risk.
      local -a _login_parts
      _login_parts=(${(z)login_cmd})
      "${_login_parts[@]}"
      ;;

    # -- logout --------------------------------------------------------------
    logout)
      _llm_apply_profile "$profile" "$provider" "$api_key" "$model" \
                         "$base_url" "$config_dir" "$config_dir_var"

      # Resolve the logout command (profile override > provider default).
      if [[ -z "$logout_cmd" ]]; then
        logout_cmd="$(_llm_default_logout_cmd "$provider")"
      fi
      if [[ -z "$logout_cmd" ]]; then
        echo "${fg[red]}No logout_cmd configured for profile '$profile' (provider: $provider).${reset_color}" >&2
        echo "Add 'logout_cmd=<command>' to the [$profile] section of $config_file." >&2
        return 1
      fi

      echo "Running: $logout_cmd"
      local -a _logout_parts
      _logout_parts=(${(z)logout_cmd})
      "${_logout_parts[@]}"
      ;;

    # -- unknown subcommand --------------------------------------------------
    *)
      echo "${fg[red]}Unknown subcommand: '$subcommand'. Valid subcommands: login, logout.${reset_color}" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# State persistence (survives new shell sessions)
#
# The state file uses KEY=VALUE lines (one per variable) so that values
# containing spaces or special characters — such as directory paths — are
# stored and restored correctly.
# ---------------------------------------------------------------------------

function _llm_state_file() {
  echo "${LLM_STATE_FILE:-${TMPDIR:-/tmp}/.llm_current_profile_${UID}}"
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
  [[ -z "${LLM_PROFILE:-}" ]] && return

  local info
  info="${ZSH_THEME_LLM_PROFILE_PREFIX:-<llm:}${LLM_PROFILE}${ZSH_THEME_LLM_PROFILE_SUFFIX:->}"

  if [[ -n "${LLM_MODEL:-}" ]]; then
    info+="${ZSH_THEME_LLM_DIVIDER:- }${ZSH_THEME_LLM_MODEL_PREFIX:-[}${LLM_MODEL}${ZSH_THEME_LLM_MODEL_SUFFIX:-]}"
  fi

  echo "$info"
}

if [[ "${SHOW_LLM_PROMPT:-true}" != false && "${RPROMPT:-}" != *'$(llm_prompt_info)'* ]]; then
  RPROMPT='$(llm_prompt_info)'"${RPROMPT:-}"
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
