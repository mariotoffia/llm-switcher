# State persistence tests.

new_test "multiple slots round-trip across a fresh shell load"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-work
'
load_plugin
lsp openai-dev  >/dev/null 2>&1
lsp claude-work >/dev/null 2>&1
# Simulate a new shell: clear env, re-source.
fresh_env
load_plugin
assert_eq "sk-openai" "${OPENAI_API_KEY:-}"    "OPENAI_API_KEY restored"
assert_eq "sk-work"   "${ANTHROPIC_API_KEY:-}" "ANTHROPIC_API_KEY restored"
teardown_isolated_env
end_test || exit 1

new_test "no legacy single-profile env vars are set after a switch"
setup_isolated_env
write_config '
[claude-work]
provider=anthropic
api_key=sk-work
model=claude-opus-4-7
config_dir=~/.claude-work
base_url=https://api.anthropic.com
'
load_plugin
lsp claude-work >/dev/null 2>&1
# These were exported by v0.x; v1 must not set them.
assert_unset LLM_PROFILE
assert_unset LLM_PROVIDER
assert_unset LLM_API_KEY
assert_unset LLM_MODEL
assert_unset LLM_BASE_URL
assert_unset LLM_CONFIG_DIR
assert_unset LLM_CONFIG_DIR_VAR
# But the v1 vars must be set.
assert_eq "claude-work"        "${LLM_PROFILE_anthropic:-}"
assert_eq "claude-work"        "${LLM_PROFILES:-}"
assert_eq "sk-work"            "${ANTHROPIC_API_KEY:-}"
assert_eq "$HOME/.claude-work" "${CLAUDE_CONFIG_DIR:-}"
teardown_isolated_env
end_test || exit 1
