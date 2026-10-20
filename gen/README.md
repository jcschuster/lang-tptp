# gen — the lang-tptp generator

Generates the editor grammars in `packages/` from the TPTP `SyntaxBNF` vendored by the
[`tptp`](https://hex.pm/packages/tptp) dependency, plus the hand-written highlight table
`categories.exs`.

```sh
mix deps.get
mix lang_tptp.gen          # write every generated file
mix lang_tptp.gen --check  # fail if any generated file is stale
mix test
```

After `mix lang_tptp.gen`, run `tree-sitter generate` in `packages/tree-sitter-tptp` to
regenerate the committed `src/` (or run `pnpm generate` from the repository root).

| Module | Does |
|---|---|
| `LangTptp.Regex` | `::-`/`:::` rules → regex AST; JS and Lezer printers |
| `LangTptp.IR` | `::=` rules → grammar IR (literals split, repetition, nullable, transparent rules) |
| `LangTptp.TreeSitter` | IR → `grammar.js` |
| `LangTptp.Lezer` | IR → `tptp.grammar` |
| `LangTptp.Monarch` | token layer → `monarch.ts` |
| `LangTptp.Highlights` | `categories.exs` → `highlights.scm`, `highlight.ts`, Monarch classes |

Each back-end lists its departures from a mechanical translation; the Mix task prints them.
