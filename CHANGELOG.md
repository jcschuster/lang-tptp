# Changelog

All notable changes to `tree-sitter-tptp`, `codemirror-lang-tptp` and `monaco-tptp` are
recorded here. The three packages share one version and are released together. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [semantic versioning](https://semver.org/spec/v2.0.0.html) over what the packages
expose: node names and queries, the exported JavaScript API, and Monaco token classes.

The TPTP BNF a release was generated from is recorded in each package's `package.json`
under `tptp.bnf`; it moves when TPTP moves, not when these packages do.

## [0.1.0] - 2026-10-20

### Added

- `tree-sitter-tptp`: a tree-sitter grammar for TPTP problems and TSTP solutions in every
  dialect (THF, TFF, TCF, FOF, CNF, TPI), with highlight and fold queries and a `.wasm`
  build.
- `codemirror-lang-tptp`: a CodeMirror 6 language (Lezer parser) with highlighting,
  folding and indentation.
- `monaco-tptp`: a Monarch tokenizer and language configuration for Monaco.

All three are generated from TPTP BNF v9.3.1.6 through `tptp` 0.3.0.

[0.1.0]: https://github.com/jcschuster/lang-tptp/releases/tag/v0.1.0
