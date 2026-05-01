# Powerlevel10k segment test.  We mock the `p10k` command (which p10k itself
# provides at runtime as a function) and verify our segment function calls it
# with the right text/args.

# Capture every invocation of the mocked p10k command into this array.
typeset -ga P10K_CALLS

new_test "prompt_llm_switcher emits a p10k segment when LLM_PROFILES is set"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-x

[claude-work]
provider=anthropic
api_key=sk-y
'
load_plugin
# Replace `p10k` with a stub that captures args.
function p10k() { P10K_CALLS+=("$*"); }
P10K_CALLS=()
lsp openai-dev  >/dev/null 2>&1
lsp claude-work >/dev/null 2>&1
prompt_llm_switcher
# Exactly one call to `p10k segment` should have been made.
assert_eq 1 "${#P10K_CALLS}" "p10k call count"
# Must be a `segment` invocation that includes both profile names.
assert_contains "${P10K_CALLS[1]}" "segment" "subcommand"
assert_contains "${P10K_CALLS[1]}" "openai-dev" "openai-dev present"
assert_contains "${P10K_CALLS[1]}" "claude-work" "claude-work present"
unfunction p10k
teardown_isolated_env
end_test || exit 1

new_test "prompt_llm_switcher is a no-op when no slots are active"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk
'
load_plugin
function p10k() { P10K_CALLS+=("$*"); }
P10K_CALLS=()
prompt_llm_switcher
assert_eq 0 "${#P10K_CALLS}" "no p10k call when LLM_PROFILES is empty"
unfunction p10k
teardown_isolated_env
end_test || exit 1

new_test "instant_prompt_llm_switcher delegates to prompt_llm_switcher"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk
'
load_plugin
function p10k() { P10K_CALLS+=("$*"); }
P10K_CALLS=()
lsp demo >/dev/null 2>&1
instant_prompt_llm_switcher
assert_eq 1 "${#P10K_CALLS}" "instant variant calls p10k segment"
assert_contains "${P10K_CALLS[1]}" "demo" "instant variant carries the profile name"
unfunction p10k
teardown_isolated_env
end_test || exit 1

new_test "_llm_p10k_custom outputs space-joined profiles when slots are active"
setup_isolated_env
write_config '
[openai-dev]
provider=openai
api_key=sk-x

[claude-work]
provider=anthropic
api_key=sk-y
'
load_plugin
lsp openai-dev  >/dev/null 2>&1
lsp claude-work >/dev/null 2>&1
local out
out="$(_llm_p10k_custom)"
assert_contains "$out" "openai-dev" "_llm_p10k_custom contains openai-dev"
assert_contains "$out" "claude-work" "_llm_p10k_custom contains claude-work"
teardown_isolated_env
end_test || exit 1

new_test "_llm_p10k_custom produces no output when no slots are active"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk
'
load_plugin
local out
out="$(_llm_p10k_custom)"
assert_eq "" "$out" "_llm_p10k_custom is empty when no profiles active"
teardown_isolated_env
end_test || exit 1
