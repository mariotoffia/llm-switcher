# Tests for the per-provider slot model (additive switching).

new_test "additive: switching openai then anthropic leaves both keys live"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-ant
'
load_plugin
lsp openai-dev   >/dev/null 2>&1
lsp claude-work  >/dev/null 2>&1
assert_eq "sk-openai" "${OPENAI_API_KEY:-}"    "OPENAI_API_KEY"
assert_eq "sk-ant"    "${ANTHROPIC_API_KEY:-}" "ANTHROPIC_API_KEY"
teardown_isolated_env
end_test || exit 1

new_test "within-provider: switching two anthropic profiles replaces the slot"
setup_isolated_env
write_config '
[claude-work]
provider=anthropic
api_key=sk-work

[claude-personal]
provider=anthropic
api_key=sk-personal
'
load_plugin
lsp claude-work     >/dev/null 2>&1
lsp claude-personal >/dev/null 2>&1
assert_eq "sk-personal" "${ANTHROPIC_API_KEY:-}" "ANTHROPIC_API_KEY"
teardown_isolated_env
end_test || exit 1

new_test "additive default keeps copilot+openai when swapping claude"
setup_isolated_env
write_config '
[copilot-personal]
provider=copilot
config_dir=/tmp/test-gh

[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-work

[claude-personal]
provider=anthropic
api_key=sk-personal
'
load_plugin
lsp copilot-personal >/dev/null 2>&1
lsp openai-dev       >/dev/null 2>&1
lsp claude-work      >/dev/null 2>&1
# Now swap claude only.
lsp claude-personal  >/dev/null 2>&1
assert_eq "/tmp/test-gh" "${GH_CONFIG_DIR:-}"   "GH_CONFIG_DIR survives swap"
assert_eq "sk-openai"    "${OPENAI_API_KEY:-}"  "OPENAI_API_KEY survives swap"
assert_eq "sk-personal"  "${ANTHROPIC_API_KEY:-}" "ANTHROPIC_API_KEY swapped"
teardown_isolated_env
end_test || exit 1

new_test "--replace flag clears all other slots before applying"
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
lsp openai-dev               >/dev/null 2>&1
lsp claude-work --replace    >/dev/null 2>&1
assert_unset OPENAI_API_KEY
assert_eq "sk-work" "${ANTHROPIC_API_KEY:-}" "ANTHROPIC_API_KEY"
teardown_isolated_env
end_test || exit 1

new_test "mode=replace in profile section forces replace semantics"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-work
mode=replace
'
load_plugin
lsp openai-dev   >/dev/null 2>&1
lsp claude-work  >/dev/null 2>&1
assert_unset OPENAI_API_KEY
assert_eq "sk-work" "${ANTHROPIC_API_KEY:-}"
teardown_isolated_env
end_test || exit 1

new_test "--add overrides mode=replace from profile section"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-work
mode=replace
'
load_plugin
lsp openai-dev          >/dev/null 2>&1
lsp claude-work --add   >/dev/null 2>&1
assert_eq "sk-openai" "${OPENAI_API_KEY:-}"
assert_eq "sk-work"   "${ANTHROPIC_API_KEY:-}"
teardown_isolated_env
end_test || exit 1

new_test "lsp clear <provider> unsets only that provider's vars"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-work

[copilot-personal]
provider=copilot
config_dir=/tmp/test-gh
'
load_plugin
lsp openai-dev       >/dev/null 2>&1
lsp claude-work      >/dev/null 2>&1
lsp copilot-personal >/dev/null 2>&1
lsp clear anthropic  >/dev/null 2>&1
assert_unset ANTHROPIC_API_KEY
assert_eq "sk-openai"    "${OPENAI_API_KEY:-}"
assert_eq "/tmp/test-gh" "${GH_CONFIG_DIR:-}"
teardown_isolated_env
end_test || exit 1

new_test "bare lsp clears all slots"
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
lsp             >/dev/null 2>&1
assert_unset OPENAI_API_KEY
assert_unset ANTHROPIC_API_KEY
assert_unset LLM_PROFILE_openai
assert_unset LLM_PROFILE_anthropic
teardown_isolated_env
end_test || exit 1

new_test "LLM_PROFILE_<provider> tracks the active slot"
setup_isolated_env
write_config '
[claude-work]
provider=anthropic
api_key=sk-work
'
load_plugin
lsp claude-work >/dev/null 2>&1
assert_eq "claude-work" "${LLM_PROFILE_anthropic:-}" "LLM_PROFILE_anthropic"
teardown_isolated_env
end_test || exit 1

new_test "LLM_PROFILES is comma-joined list of all live profile names"
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
# Order doesn't matter; just check both names appear.
assert_contains "${LLM_PROFILES:-}" "openai-dev"   "LLM_PROFILES contains openai-dev"
assert_contains "${LLM_PROFILES:-}" "claude-work"  "LLM_PROFILES contains claude-work"
teardown_isolated_env
end_test || exit 1
