#!/usr/bin/env bash
# The three packages share one version. With no argument, prints it, and fails if any
# file disagrees; with one, sets it everywhere. Run from anywhere in the repository:
#
#     .github/scripts/version.sh          # prints e.g. 0.1.0
#     .github/scripts/version.sh 0.2.0    # sets 0.2.0 (needs the tree-sitter CLI)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ts=packages/tree-sitter-tptp

# One "file version" line per place a version is recorded.
versions() {
  echo "$ts/package.json $(jq -r .version "$ts/package.json")"
  echo "$ts/tree-sitter.json $(jq -r .metadata.version "$ts/tree-sitter.json")"
  echo "$ts/CMakeLists.txt $(sed -nE 's/^ *VERSION "([^"]+)".*/\1/p' "$ts/CMakeLists.txt")"
  echo "$ts/Makefile $(sed -nE 's/^VERSION := (.*)$/\1/p' "$ts/Makefile")"
  for package in codemirror-lang-tptp monaco-tptp; do
    echo "packages/$package/package.json $(jq -r .version "packages/$package/package.json")"
  done
}

if [ $# -eq 0 ]; then
  listed=$(versions)
  distinct=$(cut -d' ' -f2 <<<"$listed" | sort -u)
  if [ "$(wc -l <<<"$distinct")" -ne 1 ]; then
    echo "::error::the packages disagree on their version:" >&2
    sed 's/^/  /' <<<"$listed" >&2
    exit 1
  fi
  echo "$distinct"
  exit 0
fi

new=$1
if ! [[ $new =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "not a version: $new (expected MAJOR.MINOR.PATCH)" >&2
  exit 1
fi

# `tree-sitter version` updates package.json, tree-sitter.json, CMakeLists.txt and the
# Makefile together.
(cd "$ts" && tree-sitter version "$new" >&2)

for package in codemirror-lang-tptp monaco-tptp; do
  sed -i -E "0,/\"version\": \"[^\"]+\"/s//\"version\": \"$new\"/" "packages/$package/package.json"
done

"$0" >/dev/null
