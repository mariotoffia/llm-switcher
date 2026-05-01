# Tests for lgp (list active slots) and llm_prompt_info.

new_test "lgp prints one line per active slot"
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
local out=""
out="$(lgp)"
assert_contains "$out" "openai: openai-dev"     "openai line"
assert_contains "$out" "anthropic: claude-work" "anthropic line"
teardown_isolated_env
end_test || exit 1

new_test "lgp prints nothing when no slots are active"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk
'
load_plugin
local out=""
out="$(lgp)"
assert_eq "" "$out"
teardown_isolated_env
end_test || exit 1

new_test "llm_prompt_info shows comma-joined profile list when multiple slots active"
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
local out=""
out="$(llm_prompt_info)"
assert_contains "$out" "openai-dev"  "openai-dev in prompt"
assert_contains "$out" "claude-work" "claude-work in prompt"
assert_contains "$out" "<llm:"       "default prefix"
teardown_isolated_env
end_test || exit 1
