# Group / [group:name] tests.

new_test "group applies all members"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-work

[group:dev]
members=openai-dev, claude-work
'
load_plugin
lsp dev >/dev/null 2>&1
assert_eq "sk-openai" "${OPENAI_API_KEY:-}"
assert_eq "sk-work"   "${ANTHROPIC_API_KEY:-}"
teardown_isolated_env
end_test || exit 1

new_test "group with mode=replace clears existing slots before applying members"
setup_isolated_env
write_config '
[mistral-eu]
provider=mistral
api_key=sk-mistral

[openai-dev]
provider=openai
api_key=sk-openai

[claude-work]
provider=anthropic
api_key=sk-work

[group:dev]
members=openai-dev, claude-work
mode=replace
'
load_plugin
lsp mistral-eu >/dev/null 2>&1
lsp dev        >/dev/null 2>&1
assert_unset MISTRAL_API_KEY
assert_eq "sk-openai" "${OPENAI_API_KEY:-}"
assert_eq "sk-work"   "${ANTHROPIC_API_KEY:-}"
teardown_isolated_env
end_test || exit 1

new_test "group is listed by llm_profiles with (group) marker"
setup_isolated_env
write_config '
[openai-dev]
provider=openai

[group:dev]
members=openai-dev
'
load_plugin
local out=""
out="$(llm_profiles)"
assert_contains "$out" "openai-dev"  "openai-dev listed"
assert_contains "$out" "dev"         "group dev listed"
assert_contains "$out" "(group)"     "group marker present"
teardown_isolated_env
end_test || exit 1
