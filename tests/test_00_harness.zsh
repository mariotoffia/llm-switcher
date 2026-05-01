# Sanity-check that the harness itself works.

new_test "harness: setup_isolated_env creates temp dir and config file"
setup_isolated_env
[[ -d "$TEST_TMPDIR" ]] || _test_fail "TEST_TMPDIR not created"
[[ -f "$LLM_SWITCHER_CONFIG" ]] || _test_fail "config file not created"
teardown_isolated_env
end_test || exit 1

new_test "harness: load_plugin sources without error"
setup_isolated_env
write_config '
[demo]
provider=openai
api_key=sk-test
'
load_plugin
# llm_profiles should now exist as a function.
if ! typeset -f llm_profiles >/dev/null; then
  _test_fail "llm_profiles function not defined after load_plugin"
fi
teardown_isolated_env
end_test || exit 1
