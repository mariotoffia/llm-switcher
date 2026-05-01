# llm-switcher

An [oh-my-zsh](https://ohmyz.sh/) plugin for switching between LLM provider
accounts/profiles in the shell — in the same spirit as the built-in
[aws plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws).

---

## Features

- Switch between named LLM profiles with a single short command (`lsp`)
- Automatically sets the correct API-key environment variable for each provider
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
A different path can be specified with the `LLM_SWITCHER_CONFIG` environment variable.

### Profile format

```ini
[profile_name]
provider=<provider>         # required
api_key=<your-api-key>      # required for all providers except ollama
model=<model-name>          # optional
base_url=<https://...>      # optional – override the default API endpoint
```

### Example config

```ini
[openai-personal]
provider=openai
api_key=sk-...
model=gpt-4o

[claude-work]
provider=anthropic
api_key=sk-ant-...
model=claude-opus-4-5

[gemini-free]
provider=google
api_key=AIza...

[mistral-eu]
provider=mistral
api_key=...
model=mistral-large-latest

[local-ollama]
provider=ollama
base_url=http://localhost:11434
model=llama3

[my-custom-llm]
provider=custom
api_key=secret
base_url=https://my-llm-gateway.example.com/v1
model=my-model
```

### Environment variables set per provider

| Provider    | Variables set                                      |
|-------------|---------------------------------------------------|
| `openai`    | `OPENAI_API_KEY`                                   |
| `anthropic` | `ANTHROPIC_API_KEY`                                |
| `google`    | `GOOGLE_API_KEY`, `GEMINI_API_KEY`                 |
| `mistral`   | `MISTRAL_API_KEY`                                  |
| `ollama`    | `OLLAMA_HOST` (from `base_url`, default `http://localhost:11434`) |
| `custom`    | —                                                  |

In **all** cases the following generic variables are also set:

| Variable      | Value                                           |
|---------------|-------------------------------------------------|
| `LLM_PROFILE` | Profile name                                    |
| `LLM_PROVIDER`| Provider name                                   |
| `LLM_API_KEY` | `api_key` value (unset for ollama)              |
| `LLM_MODEL`   | `model` value (unset when not in profile)       |
| `LLM_BASE_URL`| `base_url` value (unset when not in profile)    |

---

## Usage

### `lsp [profile]` — set / switch profile

```zsh
lsp openai-personal    # switch to the "openai-personal" profile
lsp                    # clear the current profile (unsets all LLM_* vars)
```

Tab-completion is available for profile names.

### `lgp` — get current profile

```zsh
lgp                    # prints the active profile name (empty if none)
```

### `llm_profiles` — list all profiles

```zsh
llm_profiles           # prints all profile names from the config file
```

### `llm_prompt_info` — prompt helper

Automatically added to `$RPROMPT`. When a profile is active it displays:

```
<llm:openai-personal> [gpt-4o]
```

You can customise the appearance with these variables in your `~/.zshrc`:

```zsh
ZSH_THEME_LLM_PROFILE_PREFIX="⚙ "
ZSH_THEME_LLM_PROFILE_SUFFIX=""
ZSH_THEME_LLM_MODEL_PREFIX=" ("
ZSH_THEME_LLM_MODEL_SUFFIX=")"
ZSH_THEME_LLM_DIVIDER=""
```

To disable the prompt addition entirely:

```zsh
SHOW_LLM_PROMPT=false
```

---

## State persistence

By default the active profile is saved to `/tmp/.llm_current_profile` and
restored automatically in every new shell. This means you only need to run
`lsp` once and all future terminals will inherit the same profile.

Override the state-file path:

```zsh
LLM_STATE_FILE=~/.llm_current_profile   # survives reboots
```

Disable persistence entirely:

```zsh
LLM_PROFILE_STATE_ENABLED=false
```

---

## License

[MIT](LICENSE)
