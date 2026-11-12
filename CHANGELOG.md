# Changelog

All notable changes to `tree-sitter-tptp`, `codemirror-lang-tptp` and `monaco-tptp` are
recorded here. The three packages share one version and are released together. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [semantic versioning](https://semver.org/spec/v2.0.0.html) over what the packages
expose: node names and queries, the exported JavaScript API, and Monaco token classes.

The TPTP BNF a release was generated from is recorded in each package's `package.json`
under `tptp.bnf`; it moves when TPTP moves, not when these packages do.

## [0.1.3] - 2026-11-12

### Fixed

- `codemirror-lang-tptp`: `(`, `[` and `{` now carry `closedBy`/`openedBy`, so CodeMirror
  matches brackets through the syntax tree. `@detectDelim` set none of them.

## [0.1.2] - 2026-11-07

### Changed

- Regenerated from TPTP BNF v10.0.0.0 (through `tptp` 0.3.1); it was v9.3.1.6. Each
  package records the BNF version under `tptp.bnf` in its `package.json`.
  The BNF records what changed:

  ```text
  
  ```

## [0.1.1] - 2026-10-20

### Changed

- No changes to what the packages contain. This is the first release published through
  npm trusted publishing (OIDC) instead of an access token; like 0.1.0, every package
  carries a provenance attestation.

## [0.1.0] - 2026-10-20

### Added

- `tree-sitter-tptp`: a tree-sitter grammar for TPTP problems and TSTP solutions in every
  dialect (THF, TFF, TCF, FOF, CNF, TPI), with highlight and fold queries and a `.wasm`
  build.
- `codemirror-lang-tptp`: a CodeMirror 6 language (Lezer parser) with highlighting,
  folding and indentation.
- `monaco-tptp`: a Monarch tokenizer and language configuration for Monaco.

All three are generated from TPTP BNF v9.3.1.6 through `tptp` 0.3.0.

[0.1.2]: https://github.com/jcschuster/lang-tptp/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/jcschuster/lang-tptp/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jcschuster/lang-tptp/releases/tag/v0.1.0
