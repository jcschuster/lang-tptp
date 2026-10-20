# Differential corpus test

Checks that the reference parser (`Tptp`), tree-sitter and Lezer accept and reject the same
TPTP library files. A tree with an `ERROR`/`MISSING` node (tree-sitter) or an error node
(Lezer) counts as a reject. Monarch is not included; it has no notion of accept/reject.

Needs the tree-sitter CLI on `PATH`, Node, and the built Lezer package
(`pnpm --filter codemirror-lang-tptp run build`).

```sh
cd gen
mix run ../tools/differential/differential.exs --sample 5   # one file in five
mix run ../tools/differential/differential.exs              # the whole library
```

Options: `--tptp DIR` (default `$TPTP`, then `/opt/TPTP`), `--sample N`, `--max-size BYTES`
(default 5 MB), `--jobs N` (parallel tree-sitter and Lezer processes; default: the number
of cores), `--report FILE` (default `gen/_build/differential.tsv`, one row per file
with the three verdicts).

The run fails on any disagreement that `allowlist.txt` does not list with a reason.
