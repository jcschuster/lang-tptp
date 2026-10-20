#!/usr/bin/env bash
# Moves gen/ to the newest `tptp` on Hex, if it is newer than the one in gen/mix.lock,
# regenerates every grammar from the BNF that release vendors, and prepares the release
# that ships them. Run from the repository root, in the devshell:
#
#     .github/scripts/tptp-bump.sh REVIEW_FILE
#
# Writes to $GITHUB_OUTPUT (stdout outside Actions):
#   tptp, old          the new and the previous `tptp` version; `tptp` is empty when
#                      gen/mix.lock is already current, and nothing else is written
#   bnf, old_bnf       the BNF version each of them vendors
#   generated          `ok`, or `failed` when `mix lang_tptp.gen` or `tree-sitter
#                      generate` failed (the pull request then needs a hand-written fix)
#   version, bump      the packages' new version and `minor` or `patch`; both empty when
#                      the generated files did not change, so there is nothing to release
#
# REVIEW_FILE receives what a maintainer has to look at before merging: what the new
# BNF takes away, hand-written code that still names a rule or a $-word it dropped, and
# prose that still names the old BNF version.
set -euo pipefail

review=${1:?usage: tptp-bump.sh REVIEW_FILE}
project=${GITHUB_REPOSITORY:-jcschuster/lang-tptp}
out=${GITHUB_OUTPUT:-/dev/stdout}
today=$(date -u +%F)
work=$(mktemp -d)
scripts=$(cd "$(dirname "$0")" && pwd)

old=$(sed -nE 's/.*"tptp": \{:hex, :tptp, "([^"]+)".*/\1/p' gen/mix.lock)
new=$(curl -sSf https://hex.pm/api/packages/tptp | jq -r .latest_stable_version)

if [ -z "$old" ] || [ -z "$new" ] || [ "$new" = null ]; then
  echo "::error::could not read the tptp versions (locked: '$old', on Hex: '$new')"
  exit 1
fi

if [ "$(printf '%s\n' "$old" "$new" | sort -V | tail -n 1)" = "$old" ]; then
  echo "gen/mix.lock has tptp $old, the newest on Hex is $new: nothing to do" >&2
  echo "tptp=" >>"$out"
  exit 0
fi

# The BNF before and after, kept outside deps/, which the update replaces.
(cd gen && mix deps.get >&2)
old_path=$(ls gen/deps/tptp/priv/bnf/SyntaxBNF-v*)
old_bnf=${old_path##*SyntaxBNF-v}
cp "$old_path" "$work/"
old_path=$work/SyntaxBNF-v$old_bnf

sed -i -E "s/\{:tptp, \"~> [^\"]+\"/{:tptp, \"~> $new\"/" gen/mix.exs
(cd gen && mix deps.update tptp >&2 && mix compile >&2)
new_path=$(ls "$PWD"/gen/deps/tptp/priv/bnf/SyntaxBNF-v*)
bnf=${new_path##*SyntaxBNF-v}

if [ "$bnf" = "$old_bnf" ]; then
  breaks=""
else
  breaks=$(cd gen && mix run --no-start --no-compile "$scripts/bnf-breaks.exs" "$old_path" "$new_path")
fi

# Regenerate. A failure here is a finding for the review, not a reason to stop: the
# pull request is still opened, as a draft, with the error in its description.
generated=ok
if ! (cd gen && mix lang_tptp.gen) >"$work/gen.log" 2>&1 ||
  ! (cd packages/tree-sitter-tptp && tree-sitter generate) >>"$work/gen.log" 2>&1; then
  generated=failed
fi
cat "$work/gen.log" >&2

# Generated files are everything under packages/ that `mix lang_tptp.gen` and
# `tree-sitter generate` write; hand-written files are the rest of the repository.
generated_files=(':!packages/tree-sitter-tptp/grammar.js' ':!packages/tree-sitter-tptp/src'
  ':!packages/tree-sitter-tptp/queries/highlights.scm'
  ':!packages/codemirror-lang-tptp/src/tptp.grammar'
  ':!packages/codemirror-lang-tptp/src/highlight.ts'
  ':!packages/monaco-tptp/src/monarch.ts' ':!CHANGELOG.md' ':!gen/mix.lock'
  ':!**/package.json' ':!pnpm-lock.yaml')

rules() { grep -oE '^<[A-Za-z0-9_]+>' "$1" | tr -d '<>' | sort -u; }
words() { grep -v '^%' "$1" | grep -oE '\$[a-z_]+' | sort -u; }
camel() { awk -F_ '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2); print "" }' <<<"$1"; }

{
  echo "### What BNF v$bnf takes away from v$old_bnf"
  echo
  if [ "$bnf" = "$old_bnf" ]; then
    echo "Nothing: tptp $new vendors the same BNF as $old."
  elif [ -n "$breaks" ]; then
    sed 's/^/- /' <<<"$breaks"
  else
    echo "Nothing: every rule and alternative of v$old_bnf is still there."
  fi
  echo
  echo "### Removed rules and \$-words still named by hand-written code"
  echo
  echo "A rule is a node name: \`rule\` or \`_rule\` in tree-sitter, \`Rule\` (CamelCase) in Lezer."
  echo
  echo '```text'
  comm -23 <(rules "$old_path") <(rules "$new_path") | while read -r name; do
    git grep -nwE "_?$name|$(camel "$name")" -- . "${generated_files[@]}" || true
  done
  comm -23 <(words "$old_path") <(words "$new_path") | while read -r word; do
    git grep -nwF "$word" -- . "${generated_files[@]}" || true
  done
  echo '```'
  echo
  echo "### Hand-written prose still naming v$old_bnf"
  echo
  echo '```text'
  git grep -nF "$old_bnf" -- . "${generated_files[@]}" ':!fixtures' || true
  echo '```'
} >"$review"

{
  echo "tptp=$new"
  echo "old=$old"
  echo "bnf=$bnf"
  echo "old_bnf=$old_bnf"
  echo "generated=$generated"
} >>"$out"

# Nothing to release when no generated file changed (a `tptp` release that only touches
# its own library): the pull request then just moves the dependency.
if [ "$generated" = ok ] && [ -z "$(git status --porcelain -- packages)" ]; then
  echo "the generated files are unchanged; no release" >&2
  echo "version=" >>"$out"
  echo "bump=" >>"$out"
  exit 0
fi

current=$("$scripts/version.sh")
IFS=. read -r major minor patch <<<"$current"
if [ -n "$breaks" ] || [ "$generated" = failed ]; then
  bump="minor"
  next=$major.$((minor + 1)).0
else
  bump="patch"
  next=$major.$minor.$((patch + 1))
fi

"$scripts/version.sh" "$next"
if [ "$generated" = ok ]; then
  # Restamps each package.json with the BNF version, after the version change above.
  (cd gen && mix lang_tptp.gen >&2)
fi

# The BNF's history entries after the old version, up to the banner closing them.
history=$(awk -v old="% v$old_bnf " '
  /^% v/ { on = seen; if (index($0, old) == 1) seen = 1 }
  NR > 1 && /^%-/ { on = 0; seen = 0 }
  on' "$new_path")

section=$work/section.md
if [ "$bnf" = "$old_bnf" ]; then
  cat >"$section" <<EOF
## [$next] - $today

### Changed

- Regenerated with \`tptp\` $new (was $old). The BNF is unchanged at v$bnf.

EOF
else
  cat >"$section" <<EOF
## [$next] - $today

### Changed

- Regenerated from TPTP BNF v$bnf (through \`tptp\` $new); it was v$old_bnf. Each
  package records the BNF version under \`tptp.bnf\` in its \`package.json\`.$([ -n "$breaks" ] && echo " This
  breaks queries and highlighters that name what the BNF removed:
$(sed 's/^/  - /' <<<"$breaks")
")
  The BNF records what changed:

  \`\`\`text
$(sed 's/^/  /' <<<"$history")
  \`\`\`

EOF
fi

awk -v section="$section" \
  -v link="[$next]: https://github.com/$project/compare/v$current...v$next" '
  !s && /^## \[/ { while ((getline line < section) > 0) print line; s = 1 }
  !k && /^\[[0-9]/ { print link; k = 1 }
  { print }
  END { if (!k) { print ""; print link } }' CHANGELOG.md >"$work/CHANGELOG.md"
mv "$work/CHANGELOG.md" CHANGELOG.md

{
  echo "version=$next"
  echo "bump=$bump"
} >>"$out"
