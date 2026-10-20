defmodule Mix.Tasks.LangTptp.Gen do
  @shortdoc "Regenerate the editor grammars from the TPTP SyntaxBNF"

  @moduledoc """
  Regenerates every generated file in the repository from the `SyntaxBNF` that the
  `tptp` dependency vendors, and from `gen/categories.exs`:

    * `packages/tree-sitter-tptp/grammar.js` and `queries/highlights.scm`
    * `packages/codemirror-lang-tptp/src/tptp.grammar` and `src/highlight.ts`
    * `packages/monaco-tptp/src/monarch.ts`
    * the `"tptp": {"bnf": …}` field of each package's `package.json`

  Run it from `gen/`:

      mix lang_tptp.gen
      mix lang_tptp.gen --check

  `--check` renders into memory and fails if anything differs from the files on
  disk, which keeps generated files from being edited by hand.

  `tree-sitter generate` is a separate step (run in `packages/tree-sitter-tptp`),
  because it needs the tree-sitter CLI; CI runs both and checks `git diff`.

  The task prints the BNF version and each target's departures from a mechanical
  translation. They come from the back-ends' `departures` functions, which render
  them from the constants that cause them.
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    {options, _rest} = OptionParser.parse!(argv, strict: [check: :boolean])
    root = LangTptp.root()
    outputs = LangTptp.outputs(root)
    ir = LangTptp.IR.build()

    stale =
      for {path, content} <- outputs, File.read(Path.join(root, path)) != {:ok, content}, do: path

    if options[:check] do
      if stale != [] do
        Mix.raise(
          "generated files are out of date; run `mix lang_tptp.gen`:\n" <>
            Enum.map_join(stale, "\n", &("  " <> &1))
        )
      end

      Mix.shell().info("#{length(outputs)} generated files are up to date")
    else
      for {path, content} <- outputs, path in stale do
        full = Path.join(root, path)
        File.mkdir_p!(Path.dirname(full))
        File.write!(full, content)
        Mix.shell().info("wrote #{path}")
      end

      Mix.shell().info("#{length(outputs) - length(stale)} files unchanged")
    end

    describe(ir)
  end

  defp describe(ir) do
    Mix.shell().info("""
    SyntaxBNF v#{ir.version}: #{length(ir.rules)} rules, #{length(ir.token_order)} value tokens, \
    #{length(ir.literals)} literal spellings, #{MapSet.size(ir.transparent)} transparent rules
    inlined: #{Enum.join(ir.inlined, " ")}
    merged spellings: #{Enum.join(ir.merged, " ")}\
    """)

    for {target, departures} <- LangTptp.departures(ir) do
      Mix.shell().info("#{target} departures:")
      Enum.each(departures, &Mix.shell().info("  - " <> &1))
    end
  end
end
