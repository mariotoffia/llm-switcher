# llm-switcher

An [oh-my-zsh](https://ohmyz.sh/) plugin for switching between LLM provider
accounts/profiles in the shell — in the same spirit as the built-in
[aws plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws).

---

## Features

- Switch between named LLM profiles with a single short command (`lsp`)
- **`lsp <profile> login`** — trigger the provider's auth flow in the current shell (sets the config directory, creates it if needed, then runs the login command)
- **`lsp <profile> logout`** — run the provider's logout command against the right config directory
- `config_dir` and `api_key` are both **first-class, independent** auth methods:
  - `config_dir` only — directory-based auth (e.g. after `claude login`), the most common case
  - `api_key` only — traditional key-based auth
  - both — rare, but supported
- Automatically sets the correct env var for each provider (`CLAUDE_CONFIG_DIR`, `OPENAI_API_KEY`, etc.)
- Supported providers: **openai**, **anthropic**, **google**, **mistral**, **ollama**, **custom**
- Optional model and custom base-URL per profile
- Prompt integration — shows the active profile (and model) in `$RPROMPT`
- State persists across shell sessions (can be disabled)
- Tab-completion for profile names

---

## Installation

### oh-my-zsh

1. Clone this repository into your oh-my-zsh custom plugins directory:

   ```zsh
   git clone https://github.com/mariotoffia/llm-switcher \
     ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/llm-switcher
   ```

2. Add `llm-switcher` to the plugins list in your `~/.zshrc`:

   ```zsh
   plugins=(... llm-switcher)
   ```

3. Reload your shell:

   ```zsh
   source ~/.zshrc
   ```

---

## Configuration

Create `~/.llm-switcher` (INI-style, similar to `~/.aws/credentials`).
Override the path with the `LLM_SWITCHER_CONFIG` environment variable.

### Profile format

```ini
[profile_name]
provider=<provider>              # required
config_dir=~/.claude-work        # optional – directory-based auth (first-class)
api_key=<your-api-key>           # optional – key-based auth (first-class)
model=<model-name>               # optional
base_url=<https://...>           # optional – override the default API endpoint
config_dir_var=CLAUDE_CONFIG_DIR # optional – override which env var is set for config_dir
login_cmd=claude login           # optional – override the login command
logout_cmd=claude logout         # optional – override the logout command
```

> `config_dir` and `api_key` are fully independent. Use either one, both, or
> neither (e.g. ollama needs neither).

---

## Usage

### Directory-based auth (most common)

This is the typical workflow for tools like Claude Code that store credentials
in a config directory after a `login` step — no API key required:

```ini
# ~/.llm-switcher

[claude-work]
provider=anthropic
config_dir=~/.claude-work

[claude-personal]
provider=anthropic
config_dir=~/.claude-personal

[claude-oss]
provider=anthropic
config_dir=~/.claude-oss
```

```zsh
# First time: run the login flow — this sets CLAUDE_CONFIG_DIR and calls
# `claude login`, which stores credentials in ~/.claude-work.
lsp claude-work login

# Later shells: just switch — credentials are already in the directory.
lsp claude-work
lsp claude-personal

# Sign out of a profile.
lsp claude-work logout

# See which profile is active.
lgp

# List all profiles.
llm_profiles

# Clear the active profile (unsets all LLM_* env vars).
lsp
```

### API-key-based auth

```ini
[openai-dev]
provider=openai
api_key=sk-...
model=gpt-4o

[mistral-eu]
provider=mistral
api_key=...
model=mistral-large-latest
```

```zsh
lsp openai-dev    # sets OPENAI_API_KEY, LLM_API_KEY, LLM_MODEL
lsp mistral-eu    # sets MISTRAL_API_KEY, LLM_API_KEY, LLM_MODEL
```

### Combined (directory + key)

```ini
[claude-api]
provider=anthropic
api_key=sk-ant-...
config_dir=~/.claude-api
model=claude-opus-4-5
```

Both `ANTHROPIC_API_KEY` and `CLAUDE_CONFIG_DIR` are set when you switch.

### Local / self-hosted

```ini
[local-ollama]
provider=ollama
base_url=http://localhost:11434
model=llama3

[my-gateway]
provider=custom
api_key=secret
base_url=https://my-llm-gateway.example.com/v1
config_dir=/opt/gateway-config
config_dir_var=MY_GATEWAY_CONFIG_DIR
```

---

## Commands

| Command | Description |
|---------|-------------|
| `lsp <profile>` | Switch to a profile (set env vars in the current shell) |
| `lsp <profile> login` | Switch to profile, create `config_dir` if needed, run `login_cmd` |
| `lsp <profile> logout` | Switch to profile, run `logout_cmd` |
| `lsp` | Clear the current profile (unset all `LLM_*` vars) |
| `lgp` | Print the active profile name |
| `llm_profiles` | List all profiles defined in the config file |

Tab-completion is available for profile names after `lsp`.

---

## Environment variables

### Generic (always set)

| Variable | Value |
|---|---|
| `LLM_PROFILE` | Profile name |
| `LLM_PROVIDER` | Provider name |
| `LLM_API_KEY` | `api_key` value (when present) |
| `LLM_MODEL` | `model` value (when present) |
| `LLM_BASE_URL` | `base_url` value (when present) |
| `LLM_CONFIG_DIR` | `config_dir` value, `~` expanded (when present) |
| `LLM_CONFIG_DIR_VAR` | Name of the provider-specific env var set for `config_dir` (used internally for clean-up on profile switch) |

### Provider-specific

| Provider | Variables set |
|---|---|
| `openai` | `OPENAI_API_KEY` |
| `anthropic` | `ANTHROPIC_API_KEY` (key); `CLAUDE_CONFIG_DIR` (config_dir) |
| `google` | `GOOGLE_API_KEY`, `GEMINI_API_KEY` |
| `mistral` | `MISTRAL_API_KEY` |
| `ollama` | `OLLAMA_HOST` (from `base_url`, default `http://localhost:11434`) |
| `custom` | — (use `config_dir_var` to name your own) |

### Provider defaults for login / logout commands

| Provider | `login_cmd` default | `logout_cmd` default |
|---|---|---|
| `anthropic` | `claude login` | `claude logout` |
| all others | *(must set explicitly)* | *(must set explicitly)* |

---

## Prompt integration

`llm_prompt_info` is automatically added to `$RPROMPT`. When a profile is
active it displays:

```
<llm:claude-work> [claude-opus-4-5]
```

Customise with these variables in your `~/.zshrc`:

```zsh
ZSH_THEME_LLM_PROFILE_PREFIX="⚙ "
ZSH_THEME_LLM_PROFILE_SUFFIX=""
ZSH_THEME_LLM_MODEL_PREFIX=" ("
ZSH_THEME_LLM_MODEL_SUFFIX=")"
ZSH_THEME_LLM_DIVIDER=""
```

Disable entirely:

```zsh
SHOW_LLM_PROMPT=false
```

---

## State persistence

By default the active profile is saved to `${TMPDIR:-/tmp}/.llm_current_profile_${UID}` and
restored in every new shell — run `lsp` once and all future terminals inherit
the same profile.

```zsh
# Store state in a permanent location (survives reboots):
LLM_STATE_FILE=~/.llm_current_profile

# Disable persistence entirely:
LLM_PROFILE_STATE_ENABLED=false
```

---

## License

[MIT](LICENSE)
