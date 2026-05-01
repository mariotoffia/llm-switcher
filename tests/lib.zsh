# tests/lib.zsh - shared test helpers.
# Sourced by every test file.  Provides assertion primitives and a tiny
# scaffolding API for spinning up an isolated plugin environment per test.

# Resolve repo root from the test file location.
TEST_REPO_ROOT="${TEST_REPO_ROOT:-${0:A:h:h}}"
PLUGIN_FILE="$TEST_REPO_ROOT/llm-switcher.plugin.zsh"

typeset -gi TEST_FAILED=0
typeset -g  TEST_NAME=""

function _test_fail() {
  local msg="$1"
  print -u2 "  FAIL [$TEST_NAME]: $msg"
  TEST_FAILED=1
}

function assert_eq() {
  local expected="$1" actual="$2" label="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    _test_fail "${label:+$label: }expected '$expected' got '$actual'"
  fi
}

function assert_set() {
  local var="$1"
  if [[ -z "${(P)var:-}" ]]; then
    _test_fail "expected \$$var to be set, was empty/unset"
  fi
}

function assert_unset() {
  local var="$1"
  if [[ -n "${(P)var-__UNSET_SENTINEL__}" && "${(P)var-__UNSET_SENTINEL__}" != "__UNSET_SENTINEL__" ]]; then
    _test_fail "expected \$$var to be unset, was '${(P)var}'"
  fi
}

function assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    _test_fail "${label:+$label: }expected '$haystack' to contain '$needle'"
  fi
}

# new_test <name> - declare a new test case.  Resets per-test state.
function new_test() {
  TEST_NAME="$1"
  TEST_FAILED=0
}

# end_test - emit pass/fail line; returns non-zero on failure.
function end_test() {
  if (( TEST_FAILED )); then
    return 1
  fi
  print "  PASS [$TEST_NAME]"
}

# fresh_env - clear every var the plugin reads/writes so each test starts clean.
function fresh_env() {
  unset LLM_PROFILES
  unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
  unset MISTRAL_API_KEY OLLAMA_HOST GH_CONFIG_DIR CLAUDE_CONFIG_DIR CODEX_HOME
  unset GROQ_API_KEY XAI_API_KEY OPENROUTER_API_KEY
  unset DEEPSEEK_API_KEY PERPLEXITY_API_KEY COHERE_API_KEY
  unset LLM_PROFILE_anthropic LLM_PROFILE_openai LLM_PROFILE_google
  unset LLM_PROFILE_mistral  LLM_PROFILE_ollama LLM_PROFILE_copilot
  unset LLM_PROFILE_codex    LLM_PROFILE_groq   LLM_PROFILE_xai
  unset LLM_PROFILE_openrouter LLM_PROFILE_deepseek LLM_PROFILE_perplexity
  unset LLM_PROFILE_cohere   LLM_PROFILE_custom
}

# write_config <content> - dump INI content to the test config file.
function write_config() {
  print -r -- "$1" > "$LLM_SWITCHER_CONFIG"
}

# load_plugin - source the plugin under test.  Each call re-sources, which
# is exactly what a new shell would do.
function load_plugin() {
  source "$PLUGIN_FILE"
}

# setup_isolated_env - create temp config + state files and point the plugin at them.
function setup_isolated_env() {
  TEST_TMPDIR="$(mktemp -d -t llm-switcher-test.XXXXXX)"
  export LLM_SWITCHER_CONFIG="$TEST_TMPDIR/config.ini"
  export LLM_STATE_FILE="$TEST_TMPDIR/state"
  export SHOW_LLM_PROMPT=false
  : > "$LLM_SWITCHER_CONFIG"
  fresh_env
}

function teardown_isolated_env() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  unset TEST_TMPDIR LLM_SWITCHER_CONFIG LLM_STATE_FILE SHOW_LLM_PROMPT
}
