# llm-switcher

An [oh-my-zsh](https://ohmyz.sh/) plugin for managing multiple LLM provider
accounts in the shell — keep **GitHub Copilot, OpenAI, and one Claude account**
all live at the same time, swap a single account when it runs out of tokens
without disturbing the rest, and group your favourite combinations together.

Modelled on the AWS [`asp`](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws)
plugin in spirit, but with a *per-provider slot* model rather than a single
active profile.

---

## Install

One-liner — clones the plugin into `$ZSH_CUSTOM/plugins/llm-switcher`, probes
your environment for installed CLIs / config dirs / API keys, and writes a
ready-to-use `~/.llm-switcher` (chmod 600):

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mariotoffia/llm-switcher/main/install.sh)"
```

Then add `llm-switcher` to your `plugins=(...)` line in `~/.zshrc` (or pass
`--modify-zshrc` to the installer to do it for you), and reload:

```zsh
source ~/.zshrc
```

If you want the installer to handle the `~/.zshrc` edit too:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mariotoffia/llm-switcher/main/install.sh)" -- --modify-zshrc
```

### Install-script flags

| Flag | Effect |
|---|---|
| `--modify-zshrc` | Add `llm-switcher` to the `plugins=(...)` line in `~/.zshrc` (default: off; backs up the file first). |
| `--force` | Overwrite an existing `~/.llm-switcher`. |
| `--no-autoconfig` | Skip the auto-config probe; only install the plugin. |
| `--autoconfig-only` | Skip the plugin install; only (re-)run the probe. Useful after installing a new CLI. |
| `--plugins-dir DIR` | Install elsewhere than `$ZSH_CUSTOM/plugins`. |
| `--config FILE` | Write the config somewhere else than `~/.llm-switcher`. |
| `--repo URL` | Clone from a different fork. |

### Auto-config: what gets detected

For each provider, **any one** of: a known config directory, a CLI in `$PATH`, or
a recognised API-key env var is enough to emit a profile. Detected sources are
combined into one profile per provider — e.g. `~/.claude` *and* `claude` *and*
`$ANTHROPIC_API_KEY` all roll up into one `[claude]` section.

| Profile name | Triggers if any of these is present |
|---|---|
| `[claude]` | `~/.claude` directory · `claude` CLI · `$ANTHROPIC_API_KEY` |
| `[codex]` | `~/.codex` directory · `codex` CLI · (uses `$OPENAI_API_KEY`) |
| `[copilot]` | `~/.config/gh` or `~/.copilot` · `gh` CLI |
| `[openai]` | `$OPENAI_API_KEY` (only if codex isn't already covering it) |
| `[google]` | `$GOOGLE_API_KEY` or `$GEMINI_API_KEY` |
| `[mistral]` | `$MISTRAL_API_KEY` |
| `[ollama]` | `ollama` CLI · `$OLLAMA_HOST` |
| `[groq]` | `$GROQ_API_KEY` |
| `[xai]` | `$XAI_API_KEY` |
| `[openrouter]` | `$OPENROUTER_API_KEY` |
| `[deepseek]` | `$DEEPSEEK_API_KEY` |
| `[perplexity]` | `$PERPLEXITY_API_KEY` |
| `[cohere]` | `$COHERE_API_KEY` |

A `[group:default]` group is also emitted, listing every detected profile, so
`lsp default` activates them all in one go.

### Manual install

```zsh
git clone https://github.com/mariotoffia/llm-switcher \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/llm-switcher
# add `llm-switcher` to plugins=(...) in ~/.zshrc, then:
source ~/.zshrc
```

---

## The slot model in 30 seconds

Each provider has at most one active profile — its **slot**. Switching is:

- **Additive across providers** (default): swapping the `anthropic` slot from
  `claude-work` to `claude-personal` leaves your `openai` and `copilot` slots
  untouched.
- **Replacing within a provider**: only one Claude account can be live at once
  (env vars conflict by definition), so the new profile replaces the old one in
  that slot.
- **Optionally replacing across providers** via `mode=replace` in a profile or
  `--replace` on the command line.

---

## The user's scenario, end-to-end

You have GitHub Copilot, an OpenAI key, and two Claude Code accounts (work and
personal). You want all three providers live at the same time, and you want to
swap the Claude account when one runs out of tokens.

```ini
# ~/.llm-switcher

[copilot]
provider=copilot
config_dir=~/.config/gh

[openai]
provider=openai
api_key=sk-...

[claude-work]
provider=anthropic
config_dir=~/.claude-work

[claude-personal]
provider=anthropic
config_dir=~/.claude-personal
```

```zsh
# First-time setup: log in once per directory-based profile.
lsp copilot         login    # gh auth login against ~/.config/gh
lsp claude-work     login    # claude login against ~/.claude-work
lsp claude-personal login    # claude login against ~/.claude-personal

# Daily use: activate all three in any order.
lsp copilot
lsp openai
lsp claude-work

# Now GH_CONFIG_DIR, OPENAI_API_KEY, and CLAUDE_CONFIG_DIR are all set.
lgp
# anthropic: claude-work
# copilot:   copilot
# openai:    openai

# Tokens run out on the work Claude account.  Swap just that slot.
lsp claude-personal
# Copilot and OpenAI are untouched; only CLAUDE_CONFIG_DIR changed.

# Need to log out of GitHub temporarily?
lsp clear copilot
# GH_CONFIG_DIR is gone; the others remain.

# Take everything down at end of day:
lsp
# All slots cleared.
```

---

## Configuration

The config file is `~/.llm-switcher` by default; override with
`LLM_SWITCHER_CONFIG=path`.

### Profile section

```ini
[profile_name]
provider=<provider>              # required
config_dir=~/.claude-work        # optional - directory-based auth
api_key=<your-api-key>           # optional - key-based auth
base_url=<https://...>           # optional - override default endpoint
config_dir_var=CLAUDE_CONFIG_DIR # optional - override the env var name
login_cmd=claude login           # optional - override the login command
logout_cmd=claude logout         # optional - override the logout command
mode=additive                    # optional - additive (default) | replace
```

`config_dir` and `api_key` are independent — use either, both, or neither.

### Group section

A *group* is a named bundle of profiles applied together. `lsp <group>` is a
macro for "run `lsp <name>` for each name in `members=`, in order".

```ini
[group:dev]
members=copilot, openai, claude-work
mode=replace                       # optional - default: additive
```

- `mode=additive` (default) → each member is applied to its provider's slot,
  leaving any pre-existing slots from other providers intact.
- `mode=replace` → all current slots are cleared once before the first member
  is applied; subsequent members are then applied additively (otherwise
  members would clobber each other within the group).

Members must be the names of regular `[profile]` sections elsewhere in the
same config file.

---

## Commands

| Command | Description |
|---|---|
| `lsp <profile>` | Switch the profile's provider slot (additive by default). |
| `lsp <profile> --add` / `-a` | Force additive for this invocation. |
| `lsp <profile> --replace` / `-r` | Clear every other slot first. |
| `lsp <profile> login` | Switch + run `login_cmd` (creates `config_dir` if needed). |
| `lsp <profile> logout` | Switch + run `logout_cmd`. |
| `lsp <group>` | Apply every member of `[group:<name>]`. |
| `lsp clear <provider>` | Clear only that provider's slot. |
| `lsp` | Clear every slot. |
| `lgp` | List every active slot, one per line: `<provider>: <profile>`. |
| `llm_profiles` | List every profile and group in the config. |

> **Reserved names.** `clear`, `login`, and `logout` cannot be used as profile
> or group names. The plugin warns if it spots one and refuses to apply it.

---

## Built-in providers

| Provider | API-key env var | Default `config_dir_var` | Default `login_cmd` | Default `logout_cmd` |
|---|---|---|---|---|
| `openai` | `OPENAI_API_KEY` | — | — | — |
| `anthropic` | `ANTHROPIC_API_KEY` | `CLAUDE_CONFIG_DIR` | `claude login` | `claude logout` |
| `copilot` | — | `GH_CONFIG_DIR` | `gh auth login` | `gh auth logout` |
| `codex` | `OPENAI_API_KEY` | `CODEX_HOME` | `codex login` | `codex logout` |
| `google` | `GOOGLE_API_KEY` (+ `GEMINI_API_KEY`) | — | — | — |
| `mistral` | `MISTRAL_API_KEY` | — | — | — |
| `ollama` | — | — | — | — |
| `groq` | `GROQ_API_KEY` | — | — | — |
| `xai` | `XAI_API_KEY` | — | — | — |
| `openrouter` | `OPENROUTER_API_KEY` | — | — | — |
| `deepseek` | `DEEPSEEK_API_KEY` | — | — | — |
| `perplexity` | `PERPLEXITY_API_KEY` | — | — | — |
| `cohere` | `COHERE_API_KEY` | — | — | — |
| `custom` | — | — | — | — |

For `ollama`, set `base_url=` to export `OLLAMA_HOST`; otherwise the plugin
leaves `OLLAMA_HOST` alone (the `ollama` CLI defaults to `http://localhost:11434`).

For `custom`, supply your own `config_dir_var`, `login_cmd`, `logout_cmd` —
useful for any provider not in the table above.

> **Codex vs OpenAI:** both write `OPENAI_API_KEY`, so they share the same
> physical env var. Activating a `[codex]` profile will overwrite the
> `OPENAI_API_KEY` set by an `[openai]` profile (and vice versa). Pick whichever
> matches the tool you're driving.

---

## Environment variables

### Per-slot (set when a slot is active)

| Variable | Value |
|---|---|
| `LLM_PROFILE_<provider>` | Active profile name for this provider's slot. |
| `LLM_PROFILES` | Comma-joined list of every active profile name. |

### Provider-specific (set when the slot's profile supplies them)

The provider table above. Multiple providers can be set simultaneously.

---

## Prompt integration

### Plain themes (`robbyrussell`, `agnoster`, …)

`llm_prompt_info` is automatically added to `$RPROMPT`. With multiple slots
active it shows:

```
<llm:openai,claude-work,copilot>
```

Customise with these variables in your `~/.zshrc`:

```zsh
ZSH_THEME_LLM_PROFILE_PREFIX="⚙ "
ZSH_THEME_LLM_PROFILE_SUFFIX=""
```

Disable entirely with `SHOW_LLM_PROMPT=false`.

### Powerlevel10k

p10k replaces `$RPROMPT` entirely, so the plain-theme injection above is
invisible. Follow these steps to add a native p10k segment.

**Step 1 — add the element name**

Open `~/.p10k.zsh` and find `POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS`. Add
`llm_switcher` wherever you want it to appear (after `aws` is a natural spot):

```zsh
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
  ...
  aws
  llm_switcher          # ← add this line
  ...
)
```

**Step 2 — add styling** *(optional but recommended)*

Anywhere inside the same file (e.g. near the `aws` styling block), add:

```zsh
typeset -g POWERLEVEL9K_LLM_SWITCHER_FOREGROUND=7
typeset -g POWERLEVEL9K_LLM_SWITCHER_BACKGROUND=4
typeset -g POWERLEVEL9K_LLM_SWITCHER_VISUAL_IDENTIFIER_EXPANSION='⚙'
```

**Step 3 — reload**

```zsh
source ~/.p10k.zsh
```

Or open a new terminal. The ⚙ segment will appear whenever at least one LLM
slot is active, and disappear automatically when all slots are cleared.

---

## State persistence

Active slots are saved to `${XDG_STATE_HOME:-$HOME/.local/state}/llm-switcher/state`
and restored in every new shell. The parent directory is auto-created on first
write and the file is chmod 600. Format is one `SLOT_<provider>=<profile>` line
per slot — **profile names only**, no API keys or paths (those live in the config
file).

```zsh
# Override location entirely:
LLM_STATE_FILE=~/some/other/path

# Disable persistence:
LLM_PROFILE_STATE_ENABLED=false
```

---

## Development

```zsh
make install     # run install.sh (clone/symlink + auto-config)
make autoconfig  # re-run only the auto-config probe
make test        # run the zsh test suite
make lint        # syntax-check the plugin, tests, and install.sh
make clean       # remove temp test artifacts
```

The test suite exercises the slot model end-to-end: per-provider sticky
switching, `mode`/`--add`/`--replace`, groups with per-member overrides,
state file round-trip across shell restart, all built-in providers (including
the third-party ones), the reserved-name guard, and the install script's
auto-config behaviour against a sandboxed `$HOME`.

---

## License

[MIT](LICENSE)
