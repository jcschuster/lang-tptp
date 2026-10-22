defmodule LangTptp do
  @moduledoc """
  Generates editor grammars for TPTP from the `SyntaxBNF` vendored by `tptp`.

      Tptp.Bnf.vendored_path!() ─► LangTptp.IR
                                    ├─► LangTptp.TreeSitter → grammar.js
                                    ├─► LangTptp.Lezer      → tptp.grammar
                                    ├─► LangTptp.Monarch    → monarch.ts
                                    └─► LangTptp.Highlights → highlights.scm, highlight.ts

  `outputs/1` renders every generated file; `mix lang_tptp.gen` writes them or,
  with `--check`, compares them.
  """

  alias LangTptp.Highlights
  alias LangTptp.IR
  alias LangTptp.Lezer
  alias LangTptp.Monarch
  alias LangTptp.TreeSitter

  @packages ~w(tree-sitter-tptp codemirror-lang-tptp monaco-tptp)

  @doc "The repository root (the parent of `gen/`)."
  @spec root() :: Path.t()
  def root, do: Path.expand("..", File.cwd!())

  @doc """
  Every generated file as `{path relative to the repository root, content}`.

  Each package's `package.json` is included with its `"tptp": {"bnf": …}` field set
  to the BNF version, so `--check` also catches a stale version stamp.
  """
  @spec outputs(Path.t()) :: [{Path.t(), binary()}]
  def outputs(root \\ root()) do
    ir = IR.build()
    table = Highlights.load!(ir)

    highlights = Highlights.render_tree_sitter(table, ir)

    [
      {"packages/tree-sitter-tptp/grammar.js", TreeSitter.render(ir)},
      {"packages/tree-sitter-tptp/queries/highlights.scm", highlights},
      {"packages/zed-tptp/languages/tptp/highlights.scm", highlights},
      {"packages/codemirror-lang-tptp/src/tptp.grammar", Lezer.render(ir)},
      {"packages/codemirror-lang-tptp/src/highlight.ts",
       Highlights.render_lezer(table, ir, &Lezer.name(ir, &1))},
      {"packages/monaco-tptp/src/monarch.ts", Monarch.render(ir, table)}
    ] ++
      for package <- @packages do
        path = Path.join(["packages", package, "package.json"])
        {path, stamp_bnf_version(File.read!(Path.join(root, path)), ir.version)}
      end
  end

  @doc "Departures from a mechanical translation, per target."
  @spec departures(IR.t()) :: [{binary(), [binary()]}]
  def departures(%IR{} = ir) do
    [
      {"tree-sitter", TreeSitter.departures()},
      {"Lezer", Lezer.departures(ir)},
      {"Monarch", Monarch.departures()}
    ]
  end

  @doc ~S"""
  Set `"tptp": {"bnf": version}` in a `package.json`, keeping its formatting.

  The field goes after `"license"` when it is not there yet.

      iex> LangTptp.stamp_bnf_version(~s({\n  "license": "MIT",\n  "x": 1\n}\n), "1.2.3.4")
      ~s({\n  "license": "MIT",\n  "tptp": {\n    "bnf": "1.2.3.4"\n  },\n  "x": 1\n}\n)
  """
  @spec stamp_bnf_version(binary(), binary()) :: binary()
  def stamp_bnf_version(json, version) do
    existing = ~r/("tptp":\s*\{\s*"bnf":\s*")[^"]*(")/

    cond do
      Regex.match?(existing, json) ->
        Regex.replace(existing, json, "\\g{1}#{version}\\g{2}")

      Regex.match?(~r/^  "license": "[^"]*",\n/m, json) ->
        Regex.replace(
          ~r/^(  "license": "[^"]*",\n)/m,
          json,
          "\\1  \"tptp\": {\n    \"bnf\": \"#{version}\"\n  },\n"
        )

      Regex.match?(~r/^  "license": "[^"]*"\n}/m, json) ->
        Regex.replace(
          ~r/^(  "license": "[^"]*")\n}/m,
          json,
          "\\1,\n  \"tptp\": {\n    \"bnf\": \"#{version}\"\n  }\n}"
        )

      true ->
        raise ArgumentError, ~s(cannot find where to put "tptp": {"bnf": …} in a package.json)
    end
  end
end
