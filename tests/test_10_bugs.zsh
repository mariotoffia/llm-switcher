# Regression tests for the bugs documented in the plan.

new_test "B6: substring 'dev' must NOT match profile 'dev-staging'"
setup_isolated_env
write_config '
[dev-staging]
provider=openai
api_key=sk-staging
'
load_plugin
# Calling lsp dev should be rejected: 'dev' is not a defined profile, even
# though it is a substring of 'dev-staging'.
local stderr_out=""
stderr_out="$(lsp dev 2>&1 >/dev/null)"
local rc=$?
assert_eq 1 "$rc" "exit code"
assert_contains "$stderr_out" "not found" "error message"
# And critically: OPENAI_API_KEY must NOT have been set with the wrong value.
assert_unset OPENAI_API_KEY
teardown_isolated_env
end_test || exit 1

new_test "B6: exact name 'dev-staging' still works"
setup_isolated_env
write_config '
[dev-staging]
provider=openai
api_key=sk-staging
'
load_plugin
lsp dev-staging >/dev/null 2>&1
assert_eq "sk-staging" "${OPENAI_API_KEY:-}" "OPENAI_API_KEY"
teardown_isolated_env
end_test || exit 1

new_test "B5: bare lsp removes (not just truncates) the state file"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk-test
'
load_plugin
lsp demo >/dev/null 2>&1
[[ -f "$LLM_STATE_FILE" ]] || _test_fail "state file should exist after switch"
lsp >/dev/null 2>&1
[[ ! -e "$LLM_STATE_FILE" ]] || _test_fail "state file should be removed after clear, but exists"
teardown_isolated_env
end_test || exit 1

new_test "B7: ollama restore must NOT default OLLAMA_HOST when no base_url was saved"
setup_isolated_env
write_config '
[local-ollama]
provider=ollama
'
# Simulate a saved state from a previous shell with no base_url.
print -r -- "LLM_PROFILE=local-ollama
LLM_PROVIDER=ollama
LLM_MODEL=
LLM_BASE_URL=
LLM_API_KEY=
LLM_CONFIG_DIR=
LLM_CONFIG_DIR_VAR=" > "$LLM_STATE_FILE"
unset OLLAMA_HOST
load_plugin
# OLLAMA_HOST should remain unset when the saved profile had no base_url.
assert_unset OLLAMA_HOST
teardown_isolated_env
end_test || exit 1

new_test "B3: sourcing the plugin must not leak _llm_state_path into global scope"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk-test
'
load_plugin
# After sourcing, the temporary _llm_state_path used during restore must be unset.
assert_unset _llm_state_path
teardown_isolated_env
end_test || exit 1
