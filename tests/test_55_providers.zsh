# Built-in third-party provider tests (groq, xai, openrouter, deepseek,
# perplexity, cohere, codex).  Each one should set its own API-key env var
# without conflicting with the others.

new_test "groq sets GROQ_API_KEY"
setup_isolated_env
write_config '
[g]
provider=groq
api_key=gsk-test
'
load_plugin
lsp g >/dev/null 2>&1
assert_eq "gsk-test" "${GROQ_API_KEY:-}"
teardown_isolated_env
end_test || exit 1

new_test "xai sets XAI_API_KEY"
setup_isolated_env
write_config '
[x]
provider=xai
api_key=xai-test
'
load_plugin
lsp x >/dev/null 2>&1
assert_eq "xai-test" "${XAI_API_KEY:-}"
teardown_isolated_env
end_test || exit 1

new_test "all third-party providers can be active concurrently"
setup_isolated_env
write_config '
[a]
provider=groq
api_key=g-1

[b]
provider=xai
api_key=x-1

[c]
provider=openrouter
api_key=or-1

[d]
provider=deepseek
api_key=d-1

[e]
provider=perplexity
api_key=p-1

[f]
provider=cohere
api_key=c-1
'
load_plugin
lsp a >/dev/null 2>&1
lsp b >/dev/null 2>&1
lsp c >/dev/null 2>&1
lsp d >/dev/null 2>&1
lsp e >/dev/null 2>&1
lsp f >/dev/null 2>&1
assert_eq "g-1"  "${GROQ_API_KEY:-}"
assert_eq "x-1"  "${XAI_API_KEY:-}"
assert_eq "or-1" "${OPENROUTER_API_KEY:-}"
assert_eq "d-1"  "${DEEPSEEK_API_KEY:-}"
assert_eq "p-1"  "${PERPLEXITY_API_KEY:-}"
assert_eq "c-1"  "${COHERE_API_KEY:-}"
teardown_isolated_env
end_test || exit 1

new_test "codex sets OPENAI_API_KEY and CODEX_HOME"
setup_isolated_env
write_config '
[cx]
provider=codex
api_key=sk-codex
config_dir=/tmp/codex-home
'
load_plugin
lsp cx >/dev/null 2>&1
assert_eq "sk-codex"        "${OPENAI_API_KEY:-}"
assert_eq "/tmp/codex-home" "${CODEX_HOME:-}"
teardown_isolated_env
end_test || exit 1
