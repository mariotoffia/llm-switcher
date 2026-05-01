# llm-switcher - oh-my-zsh plugin for switching between LLM provider profiles.
# Per-provider "slot" model: each provider has at most one active profile;
# switching is additive by default.  See README.md for full usage.

# Provider table: api_key_var | config_dir_var | login_cmd | logout_cmd.
typeset -gA _LLM_PROVIDERS=(
  openai     'OPENAI_API_KEY|||'
  anthropic  'ANTHROPIC_API_KEY|CLAUDE_CONFIG_DIR|claude login|claude logout'
  google     'GOOGLE_API_KEY|||'
  mistral    'MISTRAL_API_KEY|||'
  ollama     '|||'
  copilot    '|GH_CONFIG_DIR|gh auth login|gh auth logout'
  codex      'OPENAI_API_KEY|CODEX_HOME|codex login|codex logout'
  groq       'GROQ_API_KEY|||'
  xai        'XAI_API_KEY|||'
  openrouter 'OPENROUTER_API_KEY|||'
  deepseek   'DEEPSEEK_API_KEY|||'
  perplexity 'PERPLEXITY_API_KEY|||'
  cohere     'COHERE_API_KEY|||'
  custom     '|||'
)

# Active per-provider slot state (in-shell mirror of the state file).
typeset -gA _LLM_SLOTS=()

# Reserved tokens that can never be profile names.
typeset -ga _LLM_RESERVED=(clear login logout)

# Internal helpers

function _llm_config_file() { echo "${LLM_SWITCHER_CONFIG:-$HOME/.llm-switcher}"; }
function _llm_state_file()  { echo "${LLM_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/llm-switcher/state}"; }

function _llm_expand_tilde() {
  local path="$1"
  [[ "$path" == '~'* ]] && path="${HOME}${path#\~}"
  echo "$path"
}

# _llm_provider_field <provider> <0..3>  - 0=key_var 1=cfg_var 2=login 3=logout
function _llm_provider_field() {
  local raw="${_LLM_PROVIDERS[$1]:-}"
  [[ -z "$raw" ]] && return 1
  local -a parts; parts=("${(@s/|/)raw}")
  echo "${parts[$2+1]:-}"
}

# Read a key from a named INI section.
function _llm_ini_get() {
  local file="$1" section="$2" key="$3"
  awk -F '=' -v section="$section" -v key="$key" '
    /^\[/ { in_section = ($0 == "[" section "]") }
    in_section && /^[[:space:]]*[^#;[:space:]]/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      if ($1 == key) {
        val = ""
        for (i=2; i<=NF; i++) val = (i==2 ? "" : val "=") $i
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        print val
        exit
      }
    }
  ' "$file"
}

# All [section] names from the config file.
function _llm_ini_sections() {
  local file="$1"
  [[ -r "$file" ]] || return 1
  grep --color=never -E '^\[[^][:space:]][^]]*\]$' "$file" | sed 's/^\[\(.*\)\]$/\1/'
}

# Is <name> a reserved token (clear/login/logout)?
function _llm_is_reserved() {
  local name="$1"
  (( ${_LLM_RESERVED[(I)$name]} ))
}

# llm_profiles - list every profile and group.  Groups get a "(group)" marker.
function llm_profiles() {
  local config_file
  config_file="$(_llm_config_file)"
  [[ -r "$config_file" ]] || return 1
  local section
  while IFS= read -r section; do
    if [[ "$section" == group:* ]]; then
      echo "${section#group:} (group)"
    else
      if _llm_is_reserved "$section"; then
        echo "${fg[yellow]:-}Warning: profile '$section' uses a reserved name and will be ignored. Rename it.${reset_color:-}" >&2
      fi
      echo "$section"
    fi
  done < <(_llm_ini_sections "$config_file")
}

# Names only (for completion / lookup), groups stripped of the marker.
function _llm_all_names() {
  local config_file section
  config_file="$(_llm_config_file)"
  [[ -r "$config_file" ]] || return 1
  while IFS= read -r section; do
    [[ "$section" == group:* ]] && echo "${section#group:}" || echo "$section"
  done < <(_llm_ini_sections "$config_file")
}

# Slot apply / unset (the core of the per-provider model)

# Unset every env var owned by <provider>'s currently-active profile, and drop
# the slot from _LLM_SLOTS.  Safe to call when the slot is empty.
function _llm_unset_provider() {
  local provider="$1"
  local key_var cfg_var
  key_var="$(_llm_provider_field "$provider" 0)"
  cfg_var="$(_llm_provider_field "$provider" 1)"

  [[ -n "$key_var" ]] && unset "$key_var"
  [[ -n "$cfg_var" ]] && unset "$cfg_var"

  case "$provider" in
    google) unset GEMINI_API_KEY ;;
    ollama) unset OLLAMA_HOST    ;;
  esac

  unset "LLM_PROFILE_$provider"
  unset "_LLM_SLOTS[$provider]"
}

# Apply one profile section into its provider's slot, replacing whatever was
# there.  Other providers' slots are untouched.
# Args: <profile_name>
function _llm_apply_slot() {
  local profile="$1"
  local config_file provider api_key base_url config_dir cfg_var_override
  config_file="$(_llm_config_file)"
  provider="$(_llm_ini_get        "$config_file" "$profile" provider)"
  api_key="$(_llm_ini_get         "$config_file" "$profile" api_key)"
  base_url="$(_llm_ini_get        "$config_file" "$profile" base_url)"
  config_dir="$(_llm_ini_get      "$config_file" "$profile" config_dir)"
  cfg_var_override="$(_llm_ini_get "$config_file" "$profile" config_dir_var)"

  if [[ -z "$provider" ]]; then
    print -u2 "${fg[yellow]:-}Warning: no 'provider' for profile '$profile'. Defaulting to 'custom'.${reset_color:-}"
    provider="custom"
  fi
  if [[ -z "${_LLM_PROVIDERS[$provider]:-}" ]]; then
    print -u2 "${fg[yellow]:-}Warning: unknown provider '$provider'. Only LLM_PROFILE_$provider will be set.${reset_color:-}"
  fi

  # Replace the slot: clear the previous occupant first.
  _llm_unset_provider "$provider"
  _LLM_SLOTS[$provider]="$profile"
  export "LLM_PROFILE_$provider"="$profile"

  # Provider-specific API-key var.
  local key_var
  key_var="$(_llm_provider_field "$provider" 0)"
  if [[ -n "$key_var" && -n "$api_key" ]]; then
    export "$key_var"="$api_key"
  fi
  # Google sets two env vars for the same key.
  [[ "$provider" == google && -n "$api_key" ]] && export GEMINI_API_KEY="$api_key"

  # Provider-specific config-dir var.
  if [[ -n "$config_dir" ]]; then
    local expanded cfg_var
    expanded="$(_llm_expand_tilde "$config_dir")"
    cfg_var="${cfg_var_override:-$(_llm_provider_field "$provider" 1)}"
    [[ -n "$cfg_var" ]] && export "$cfg_var"="$expanded"
  fi

  # ollama: OLLAMA_HOST is only set if the profile supplies an explicit
  # base_url; the `ollama` CLI defaults to http://localhost:11434 on its own.
  if [[ "$provider" == ollama && -n "$base_url" ]]; then
    export OLLAMA_HOST="$base_url"
  fi

  _llm_refresh_profiles_var
  _llm_save_state
}

# Refresh the LLM_PROFILES summary var from the slot map.
function _llm_refresh_profiles_var() {
  local -a names
  local p
  for p in "${(@k)_LLM_SLOTS}"; do
    names+=("${_LLM_SLOTS[$p]}")
  done
  if (( ${#names} )); then
    export LLM_PROFILES="${(j:,:)names}"
  else
    unset LLM_PROFILES
  fi
}

# Clear every slot.
function _llm_clear_all_slots() {
  local p
  for p in "${(@k)_LLM_SLOTS}"; do
    _llm_unset_provider "$p"
  done
  unset LLM_PROFILES
  _llm_clear_state
}

# Resolve the effective mode (additive|replace) for a given switch.
function _llm_resolve_mode() {
  local profile="$1" cli_flag="$2"
  case "$cli_flag" in
    --add|-a)     echo additive; return ;;
    --replace|-r) echo replace;  return ;;
  esac
  local profile_mode
  profile_mode="$(_llm_ini_get "$(_llm_config_file)" "$profile" mode)"
  echo "${profile_mode:-additive}"
}

# State persistence: one SLOT_<provider>=<profile> line per active slot.

function _llm_save_state() {
  [[ "${LLM_PROFILE_STATE_ENABLED:-true}" == true ]] || return 0
  local sf p
  sf="$(_llm_state_file)"
  mkdir -p "$(dirname "$sf")" || return 1
  {
    for p in "${(@k)_LLM_SLOTS}"; do
      print "SLOT_$p=${_LLM_SLOTS[$p]}"
    done
  } > "$sf"
  chmod 600 "$sf" 2>/dev/null
}

function _llm_clear_state() {
  [[ "${LLM_PROFILE_STATE_ENABLED:-true}" == true ]] || return 0
  rm -f "$(_llm_state_file)"
}

# Restore slots from the state file (called once at plugin load).
function _llm_restore_state() {
  [[ "${LLM_PROFILE_STATE_ENABLED:-true}" == true ]] || return 0
  local sf line key val
  sf="$(_llm_state_file)"
  [[ -s "$sf" ]] || return 0
  # Slurp first: _llm_apply_slot rewrites the state file, which would truncate
  # the inode the read loop is iterating over and swallow remaining slots.
  local -a lines slot_profiles
  lines=("${(@f)$(<"$sf")}")
  for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    [[ "$key" == SLOT_* && -n "$val" ]] && slot_profiles+=("$val")
  done
  local p
  for p in "${slot_profiles[@]}"; do _llm_apply_slot "$p"; done
}

# Group resolution

# Apply a [group:name] section.  Group mode=replace clears all slots once
# before the first member; otherwise members are applied additively in order.
function _llm_apply_group() {
  local group="$1" cli_flag="$2"
  local config_file members_raw group_mode m
  config_file="$(_llm_config_file)"
  members_raw="$(_llm_ini_get "$config_file" "group:$group" members)"
  if [[ -z "$members_raw" ]]; then
    print -u2 "${fg[red]:-}Group '$group' has no 'members='.${reset_color:-}"
    return 1
  fi
  group_mode="$(_llm_ini_get "$config_file" "group:$group" mode)"
  group_mode="${group_mode:-additive}"
  case "$cli_flag" in
    --replace|-r) group_mode=replace ;;
    --add|-a)     group_mode=additive ;;
  esac
  [[ "$group_mode" == replace ]] && _llm_clear_all_slots
  local -a members
  members=("${(@s/,/)members_raw}")
  for m in "${members[@]}"; do
    m="${m## }"; m="${m%% }"
    [[ -z "$m" ]] && continue
    _llm_apply_slot "$m"
  done
}

# Public functions

# lgp - print all active slots, one per line: "<provider>: <profile>".
function lgp() {
  local p
  for p in "${(@kon)_LLM_SLOTS}"; do
    echo "$p: ${_LLM_SLOTS[$p]}"
  done
}

# lsp - the main entry point.  See header comment for grammar.
function lsp() {
  if [[ -z "${1:-}" ]]; then
    _llm_clear_all_slots
    echo "All LLM slots cleared."
    return
  fi

  local config_file
  config_file="$(_llm_config_file)"
  if [[ ! -r "$config_file" ]]; then
    print -u2 "${fg[red]:-}Config file not found: $config_file${reset_color:-}"
    print -u2 "Create it with at least one [profile] section. See README for details."
    return 1
  fi

  # Reserved subcommand: clear <provider>
  if [[ "$1" == clear ]]; then
    if [[ -z "${2:-}" ]]; then
      print -u2 "${fg[red]:-}lsp clear: missing provider name. Use bare 'lsp' to clear all slots.${reset_color:-}"
      return 1
    fi
    if [[ -z "${_LLM_PROVIDERS[$2]:-}" ]]; then
      print -u2 "${fg[red]:-}Unknown provider: '$2'. Known: ${(j:, :)${(@k)_LLM_PROVIDERS}}${reset_color:-}"
      return 1
    fi
    _llm_unset_provider "$2"
    _llm_refresh_profiles_var
    _llm_save_state
    echo "Cleared LLM slot: $2"
    return
  fi

  # Resolve the section name (profile or group).
  local target="$1" subcommand="${2:-}" cli_flag=""
  # Subcommand can be login/logout (after a profile) or a mode flag.
  case "$subcommand" in
    --add|-a|--replace|-r) cli_flag="$subcommand"; subcommand="" ;;
    login|logout|"")       ;;
    *) print -u2 "${fg[red]:-}Unknown subcommand: '$subcommand'. Valid: login, logout, --add, --replace.${reset_color:-}"; return 1 ;;
  esac

  if _llm_is_reserved "$target"; then
    print -u2 "${fg[red]:-}'$target' is a reserved name and cannot be a profile.${reset_color:-}"
    return 1
  fi

  local config_file_sections
  config_file_sections="$(_llm_ini_sections "$config_file")"
  local is_group=0 is_profile=0
  echo "$config_file_sections" | grep -qx "group:$target" && is_group=1
  echo "$config_file_sections" | grep -qx "$target"       && is_profile=1

  if (( ! is_group && ! is_profile )); then
    local -a available; available=($(_llm_all_names))
    print -u2 "${fg[red]:-}Profile '$target' not found in '$config_file'${reset_color:-}"
    print -u2 "Available: ${(j:, :)available:-none}"
    return 1
  fi

  if (( is_group )); then
    _llm_apply_group "$target" "$cli_flag"
    echo "Applied LLM group: $target"
    return
  fi

  # Single profile.
  local mode
  mode="$(_llm_resolve_mode "$target" "$cli_flag")"
  if [[ "$mode" == replace ]]; then
    _llm_clear_all_slots
  fi
  _llm_apply_slot "$target"

  local provider
  provider="$(_llm_ini_get "$config_file" "$target" provider)"
  echo "Switched to LLM profile: $target (provider: ${provider:-custom}, mode: $mode)"

  # login / logout subcommands run after the slot is applied.
  case "$subcommand" in
    login|logout) _llm_run_auth_cmd "$target" "$subcommand" ;;
  esac
}

# Run the configured login_cmd or logout_cmd for a profile.
function _llm_run_auth_cmd() {
  local profile="$1" action="$2"
  local config_file provider config_dir field_idx cmd
  config_file="$(_llm_config_file)"
  provider="$(_llm_ini_get "$config_file" "$profile" provider)"
  config_dir="$(_llm_ini_get "$config_file" "$profile" config_dir)"
  cmd="$(_llm_ini_get "$config_file" "$profile" "${action}_cmd")"
  if [[ -z "$cmd" ]]; then
    [[ "$action" == login ]] && field_idx=2 || field_idx=3
    cmd="$(_llm_provider_field "$provider" $field_idx)"
  fi
  if [[ -z "$cmd" ]]; then
    print -u2 "${fg[red]:-}No ${action}_cmd configured for profile '$profile' (provider: $provider).${reset_color:-}"
    print -u2 "Add '${action}_cmd=<command>' to the [$profile] section of $config_file."
    return 1
  fi
  if [[ "$action" == login && -n "$config_dir" ]]; then
    mkdir -p "$(_llm_expand_tilde "$config_dir")"
  fi
  echo "Running: $cmd"
  local -a parts; parts=(${(z)cmd})
  "${parts[@]}"
}

# Prompt integration

function llm_prompt_info() {
  [[ -z "${LLM_PROFILES:-}" ]] && return
  echo "${ZSH_THEME_LLM_PROFILE_PREFIX:-<llm:}${LLM_PROFILES}${ZSH_THEME_LLM_PROFILE_SUFFIX:->}"
}

if [[ "${SHOW_LLM_PROMPT:-true}" != false && "${RPROMPT:-}" != *'$(llm_prompt_info)'* ]]; then
  RPROMPT='$(llm_prompt_info)'"${RPROMPT:-}"
fi

# Tab completion - the _lsp file is autoloaded from $fpath.
(( $+functions[compdef] )) && compdef _lsp lsp 2>/dev/null

# Restore state from previous session
_llm_restore_state
