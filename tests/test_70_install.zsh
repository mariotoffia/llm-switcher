# install.sh auto-config tests.  The script is invoked with --autoconfig-only
# against a sandboxed $HOME so we can assert on what it generates without
# touching the real config.

INSTALL_SH="$TEST_REPO_ROOT/install.sh"

# Create a fresh sandbox $HOME with an empty bin/.  Sets $SANDBOX_HOME and
# $SANDBOX_PATH for use by fake_cli/run_autoconfig.
init_sandbox() {
  SANDBOX_HOME="$(mktemp -d -t llm-switcher-install.XXXXXX)"
  SANDBOX_PATH="$SANDBOX_HOME/bin"
  mkdir -p "$SANDBOX_PATH"
  export SANDBOX_HOME SANDBOX_PATH
}

cleanup_sandbox() {
  [[ -n "${SANDBOX_HOME:-}" && -d "$SANDBOX_HOME" ]] && rm -rf "$SANDBOX_HOME"
  unset SANDBOX_HOME SANDBOX_PATH
}

# Drop a fake CLI into the sandbox PATH.
fake_cli() {
  local name="$1"
  print -r -- '#!/bin/sh' > "$SANDBOX_PATH/$name"
  print -r -- 'exit 0'    >> "$SANDBOX_PATH/$name"
  chmod +x "$SANDBOX_PATH/$name"
}

# Run install.sh --autoconfig-only --force against the current sandbox.
# Args:  <env-string>   e.g. "OPENAI_API_KEY=sk-x GROQ_API_KEY=gsk-x"
run_autoconfig() {
  local env_string="$1"
  env -i HOME="$SANDBOX_HOME" \
        PATH="$SANDBOX_PATH:/usr/bin:/bin" \
        LLM_SWITCHER_CONFIG="$SANDBOX_HOME/.llm-switcher" \
        ${=env_string} \
        sh "$INSTALL_SH" --autoconfig-only --force \
        --config "$SANDBOX_HOME/.llm-switcher" >/dev/null 2>&1
}

new_test "autoconfig: detects ~/.claude dir and writes [claude] profile"
init_sandbox
mkdir -p "$SANDBOX_HOME/.claude"
run_autoconfig ""
local out=""
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_contains "$out" "[claude]"            "claude section"
assert_contains "$out" "provider=anthropic"  "anthropic provider"
assert_contains "$out" "config_dir=~/.claude" "config_dir line"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: detects \`claude\` CLI even without ~/.claude dir"
init_sandbox
fake_cli claude
run_autoconfig ""
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_contains "$out" "[claude]"
assert_contains "$out" "provider=anthropic"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: ANTHROPIC_API_KEY env adds api_key to claude profile"
init_sandbox
mkdir -p "$SANDBOX_HOME/.claude"
run_autoconfig "ANTHROPIC_API_KEY=sk-ant-test"
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_contains "$out" "api_key=sk-ant-test"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: detects ~/.config/gh and writes [copilot] profile"
init_sandbox
mkdir -p "$SANDBOX_HOME/.config/gh"
run_autoconfig ""
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_contains "$out" "[copilot]"
assert_contains "$out" "provider=copilot"
assert_contains "$out" "config_dir=~/.config/gh"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: detects ~/.codex and writes [codex] profile"
init_sandbox
mkdir -p "$SANDBOX_HOME/.codex"
run_autoconfig "OPENAI_API_KEY=sk-codex"
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_contains "$out" "[codex]"
assert_contains "$out" "provider=codex"
assert_contains "$out" "config_dir=~/.codex"
assert_contains "$out" "api_key=sk-codex"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: third-party env keys generate their own profiles"
init_sandbox
run_autoconfig "GROQ_API_KEY=gsk-1 XAI_API_KEY=xai-1 OPENROUTER_API_KEY=or-1"
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_contains "$out" "[groq]"
assert_contains "$out" "api_key=gsk-1"
assert_contains "$out" "[xai]"
assert_contains "$out" "api_key=xai-1"
assert_contains "$out" "[openrouter]"
assert_contains "$out" "api_key=or-1"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: emits [group:default] listing all detected providers"
init_sandbox
mkdir -p "$SANDBOX_HOME/.claude"
mkdir -p "$SANDBOX_HOME/.config/gh"
run_autoconfig "OPENAI_API_KEY=sk-1 GROQ_API_KEY=gsk-1"
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_contains "$out" "[group:default]"
assert_contains "$out" "claude"
assert_contains "$out" "copilot"
assert_contains "$out" "openai"
assert_contains "$out" "groq"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: writes file with chmod 600"
init_sandbox
mkdir -p "$SANDBOX_HOME/.claude"
run_autoconfig ""
local mode=""
mode="$(stat -f '%OLp' "$SANDBOX_HOME/.llm-switcher" 2>/dev/null \
        || stat -c '%a' "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
assert_eq "600" "$mode" "file mode"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: --force overwrites an existing config"
init_sandbox
mkdir -p "$SANDBOX_HOME/.claude"
print -r -- "old content" > "$SANDBOX_HOME/.llm-switcher"
run_autoconfig "ANTHROPIC_API_KEY=sk-new"
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
if [[ "$out" == *"old content"* ]]; then _test_fail "old content survived --force"; fi
assert_contains "$out" "sk-new" "new key written"
cleanup_sandbox
end_test || exit 1

new_test "autoconfig: detects nothing when env is empty and HOME is bare"
init_sandbox
run_autoconfig ""
out="$(cat "$SANDBOX_HOME/.llm-switcher" 2>/dev/null)"
# No profile sections should be written.
if [[ "$out" == *"["*"]"* && "$out" == *"provider="* ]]; then
  _test_fail "expected no [profile] sections, got: $out"
fi
cleanup_sandbox
end_test || exit 1

new_test "generated config can be loaded by the plugin and switched to"
init_sandbox
mkdir -p "$SANDBOX_HOME/.claude"
run_autoconfig "ANTHROPIC_API_KEY=sk-loadable GROQ_API_KEY=gsk-loadable"
# Now use the generated config with the real plugin and verify lsp works.
setup_isolated_env
cp "$SANDBOX_HOME/.llm-switcher" "$LLM_SWITCHER_CONFIG"
chmod 600 "$LLM_SWITCHER_CONFIG"
load_plugin
lsp default >/dev/null 2>&1
assert_eq "sk-loadable"  "${ANTHROPIC_API_KEY:-}" "ANTHROPIC_API_KEY"
assert_eq "gsk-loadable" "${GROQ_API_KEY:-}"      "GROQ_API_KEY"
teardown_isolated_env
cleanup_sandbox
end_test || exit 1
