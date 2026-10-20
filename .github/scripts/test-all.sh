#!/usr/bin/env bash
# Runs every check in the repository, keeps going past a failure, and ends with one
# `PASS name` or `FAIL name` line per check. Exits non-zero if any failed. Expects the
# devshell (`nix develop`) and fetched Mix dependencies:
#
#     .github/scripts/test-all.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

results=()
failed=0

check() {
  local name=$1
  shift
  echo "== $name"
  if "$@"; then
    results+=("PASS $name")
  else
    results+=("FAIL $name")
    failed=1
  fi
}

check "LICENSE and NOTICE copies match" bash -c \
  'for p in tree-sitter-tptp codemirror-lang-tptp monaco-tptp; do
     cmp LICENSE "packages/$p/LICENSE" && cmp NOTICE "packages/$p/NOTICE" || exit 1
   done'
check "generated files are current" bash -c 'cd gen && mix lang_tptp.gen --check'
check "mix test" bash -c 'cd gen && mix test'
check "tree-sitter test" bash -c 'cd packages/tree-sitter-tptp && tree-sitter test'
check "pnpm install" pnpm install --frozen-lockfile
check "pnpm build" pnpm -r run build
check "pnpm test" pnpm -r test

echo
printf '%s\n' "${results[@]}"
exit "$failed"
