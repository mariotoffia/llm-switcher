#!/usr/bin/env zsh
# tests/run.zsh - test runner.  Sources every tests/test_*.zsh in turn and
# tracks pass/fail.  Exits non-zero if any test failed.

emulate -L zsh
setopt extended_glob

TEST_DIR="${0:A:h}"
typeset -i TOTAL=0 PASSED=0 FAILED=0

for test_file in "$TEST_DIR"/test_*.zsh; do
  print "RUN $(basename "$test_file")"
  # Run each test file in a fresh subshell so plugin state cannot leak between files.
  if zsh -f -c "
    source '$TEST_DIR/lib.zsh'
    source '$test_file'
  "; then
    : $((PASSED++))
  else
    : $((FAILED++))
  fi
  : $((TOTAL++))
done

print ""
print "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED"
(( FAILED == 0 ))
