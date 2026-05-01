# State file location + permissions tests.
# v1 default: $XDG_STATE_HOME/llm-switcher/state
# Fallback:   $HOME/.local/state/llm-switcher/state
# Always:     chmod 600 on the file, parent dir auto-created.

new_test "state default uses \$XDG_STATE_HOME when set"
SBX="$(mktemp -d -t llm-state-loc.XXXXXX)"
mkdir -p "$SBX/xdg-state"
unset LLM_STATE_FILE
export XDG_STATE_HOME="$SBX/xdg-state"
export HOME="$SBX/home"
mkdir -p "$HOME"
export LLM_SWITCHER_CONFIG="$SBX/config"
print -r -- '
[demo]
provider=openai
api_key=sk
' > "$LLM_SWITCHER_CONFIG"
load_plugin
lsp demo >/dev/null 2>&1
[[ -f "$XDG_STATE_HOME/llm-switcher/state" ]] || _test_fail "state file not at \$XDG_STATE_HOME/llm-switcher/state"
unset XDG_STATE_HOME LLM_SWITCHER_CONFIG HOME
rm -rf "$SBX"
end_test || exit 1

new_test "state default falls back to ~/.local/state when XDG_STATE_HOME unset"
SBX="$(mktemp -d -t llm-state-loc.XXXXXX)"
unset LLM_STATE_FILE XDG_STATE_HOME
export HOME="$SBX/home"
mkdir -p "$HOME"
export LLM_SWITCHER_CONFIG="$SBX/config"
print -r -- '
[demo]
provider=openai
api_key=sk
' > "$LLM_SWITCHER_CONFIG"
load_plugin
lsp demo >/dev/null 2>&1
[[ -f "$HOME/.local/state/llm-switcher/state" ]] || _test_fail "state file not at \$HOME/.local/state/llm-switcher/state"
unset HOME LLM_SWITCHER_CONFIG
rm -rf "$SBX"
end_test || exit 1

new_test "parent directory is auto-created on first write"
SBX="$(mktemp -d -t llm-state-loc.XXXXXX)"
unset LLM_STATE_FILE XDG_STATE_HOME
export HOME="$SBX/home"
mkdir -p "$HOME"
# Note: do NOT pre-create ~/.local/state/llm-switcher/.
export LLM_SWITCHER_CONFIG="$SBX/config"
print -r -- '
[demo]
provider=openai
api_key=sk
' > "$LLM_SWITCHER_CONFIG"
load_plugin
lsp demo >/dev/null 2>&1
[[ -d "$HOME/.local/state/llm-switcher" ]] || _test_fail "parent dir was not auto-created"
[[ -f "$HOME/.local/state/llm-switcher/state" ]] || _test_fail "state file not written"
unset HOME LLM_SWITCHER_CONFIG
rm -rf "$SBX"
end_test || exit 1

new_test "state file is chmod 600 after write"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk
'
load_plugin
lsp demo >/dev/null 2>&1
local mode=""
mode="$(stat -f '%OLp' "$LLM_STATE_FILE" 2>/dev/null \
        || stat -c '%a' "$LLM_STATE_FILE" 2>/dev/null)"
assert_eq "600" "$mode" "state file mode"
teardown_isolated_env
end_test || exit 1

new_test "LLM_STATE_FILE override still wins over XDG default"
SBX="$(mktemp -d -t llm-state-loc.XXXXXX)"
export LLM_STATE_FILE="$SBX/explicit-override"
export XDG_STATE_HOME="$SBX/xdg-state"  # should be ignored
export HOME="$SBX/home"
mkdir -p "$HOME"
export LLM_SWITCHER_CONFIG="$SBX/config"
print -r -- '
[demo]
provider=openai
api_key=sk
' > "$LLM_SWITCHER_CONFIG"
load_plugin
lsp demo >/dev/null 2>&1
[[ -f "$LLM_STATE_FILE" ]] || _test_fail "explicit LLM_STATE_FILE not honoured"
[[ ! -f "$XDG_STATE_HOME/llm-switcher/state" ]] || _test_fail "XDG default should not have been used when LLM_STATE_FILE is set"
unset LLM_STATE_FILE XDG_STATE_HOME HOME LLM_SWITCHER_CONFIG
rm -rf "$SBX"
end_test || exit 1
