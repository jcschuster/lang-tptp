# lang-tptp

Editor language support for [TPTP](https://tptp.org), generated from the TPTP World
`SyntaxBNF` (through the [`tptp`](https://hex.pm/packages/tptp) package, which vendors it).

| Package | For |
|---|---|
| [`tree-sitter-tptp`](packages/tree-sitter-tptp) | Zed, Neovim, Helix, and anything else that loads tree-sitter grammars |
| [`codemirror-lang-tptp`](packages/codemirror-lang-tptp) | CodeMirror 6 |
| [`monaco-tptp`](packages/monaco-tptp) | Monaco |

The three packages share one version; see [CHANGELOG.md](CHANGELOG.md).

## Working on it

The devshell (`nix develop`, or direnv) has every tool. Then:

```sh
cd gen && mix deps.get && cd ..
pnpm install
pnpm generate                  # mix lang_tptp.gen, then tree-sitter generate
.github/scripts/test-all.sh    # every check CI runs
```

`gen/` is the generator; the grammars, highlight queries and tokenizer under `packages/`
are its output and are committed. Hand-written parts are listed in each package's README.
`tools/differential` compares the parsers against `tptp` over the TPTP library.

## Releasing

A release is a merged pull request labelled `release`: `release.yml` then publishes the
three packages to npm and creates the GitHub release `vX.Y.Z` (with
`tree-sitter-tptp.wasm`), using the version's CHANGELOG section as release notes.

- **New `tptp` on Hex:** `tptp.yml` checks nightly and opens the pull request itself, with
  the version bumped, the CHANGELOG section written, and a list of what to review.
- **Anything else:** run `.github/scripts/version.sh X.Y.Z`, add a `## [X.Y.Z] - date`
  section to `CHANGELOG.md`, open a pull request and label it `release`.

Repository secrets: `NPM_TOKEN` (or npm trusted publishing for `release.yml`, once the
packages exist on npm), and optionally `TPTP_PR_TOKEN`, a fine-grained token with contents
and pull-request write access, so that the bot's pull requests run CI.

## Licence

MIT; see [LICENSE](LICENSE). The grammars are derived from the TPTP syntax BNF, which is
copyrighted by Geoff Sutcliffe and Christian Suttner; see [NOTICE](NOTICE).
