defmodule LangTptp.Monarch do
  @moduledoc """
  Prints a Monarch tokenizer (`monarch.ts`) for Monaco from the IR's token layer.

  Monarch is a regex state machine, not a parser, so the structure it knows is what
  its states encode:

    * `root` — between statements: a statement keyword starts a statement.
    * `statementOpen` → `statementName` → `statementRole` → `formula` — the fixed
      head of an annotated formula, so the name gets the label class and the role
      the role class. Each step replaces the state (`switchTo`) rather than pushing.
    * `formula` — everything after the role; `(` pushes another `formula`, `)`
      pops, so the `)` that closes the statement returns to `root`.
    * `include` — `include(…)`, where a quoted atom is a file name.
    * `comment` — inside `/* … */`, which can span lines.

  Token regexes come from `LangTptp.Regex.to_js/1`, word lists from
  `Tptp.Token` and `Tptp.Bnf.Vocabulary`, and token classes from the highlight
  table, so all three targets agree on categories.
  """

  alias LangTptp.Highlights
  alias LangTptp.IR
  alias LangTptp.Regex, as: Re

  @statement_keywords ~w(thf tff tcf fof cnf tpi)

  @doc "One line per departure: Monarch has no grammar, so it approximates by state."
  @spec departures() :: [binary()]
  def departures do
    [
      "regex state machine: a lower word followed by `(` is a function, otherwise a constant",
      "every $-word is a builtin; $$-words are system words"
    ]
  end

  @doc "Render `monarch.ts`."
  @spec render(IR.t(), Highlights.t()) :: binary()
  def render(%IR{} = ir, table) do
    class = fn category -> Highlights.target(table, category, :monarch) end
    lit = fn spelling -> class.(Highlights.literal_category(table, spelling)) end
    re = fn name -> "/" <> Re.to_js(Map.fetch!(ir.tokens, name)) <> "/" end

    operators =
      ir.literals
      |> Enum.filter(&(Highlights.literal_category(table, &1) == :operator))
      |> Enum.sort_by(&{-byte_size(&1), &1})
      |> Enum.map_join("|", &escape/1)

    vocabulary = Tptp.Bnf.Vocabulary

    defined =
      Enum.sort(
        vocabulary.defined_functor_values() ++
          vocabulary.defined_predicate_values() ++ vocabulary.defined_proposition_values()
      )

    dollar_keywords = Enum.filter(ir.keywords, &String.starts_with?(&1, "$"))
    source_keywords = ~w(inference introduced file)
    check_keywords!(ir, dollar_keywords, source_keywords)

    whitespace = ~s|{ include: "@whitespace" }|

    word_rules = fn ->
      [
        ~s|[#{re.("upper_word")}, #{q(class.(:variable))}]|,
        ~s|[#{re.("dollar_dollar_word")}, #{q(class.(:system))}]|,
        ~s|[#{re.("dollar_word")}, { cases: { "@dollarKeywords": #{q(lit.("$thf"))}, "@definedTypes": #{q(class.(:builtin_type))}, "@default": #{q(class.(:builtin))} } }]|,
        ~s|[/(?:#{Enum.join(source_keywords, "|")})(?=\\s*\\()/, #{q(lit.("inference"))}]|,
        ~s|[/(?:#{Re.to_js(Map.fetch!(ir.tokens, "lower_word"))})(?=\\s*\\()/, #{q(class.(:function))}]|,
        ~s|[#{re.("lower_word")}, #{q(class.(:constant))}]|,
        ~s|[#{re.("single_quoted")}, #{q(class.(:constant))}]|,
        ~s|[#{re.("distinct_object")}, #{q(class.(:string))}]|,
        ~s|[/(?:#{Re.to_js(Map.fetch!(ir.tokens, "real"))})(?![0-9])/, #{q(class.(:number))}]|,
        ~s|[/(?:#{Re.to_js(Map.fetch!(ir.tokens, "rational"))})(?![0-9])/, #{q(class.(:number))}]|,
        ~s|[#{re.("integer")}, #{q(class.(:number))}]|,
        ~s|[/#{operators}/, #{q(class.(:operator))}]|,
        ~s|[/[\\[\\]{}]/, "@brackets"]|,
        ~s|[/[,:\\-.]/, #{q(lit.(","))}]|
      ]
    end

    states = [
      root: [
        whitespace,
        ~s|[/(?:#{Enum.join(@statement_keywords, "|")})(?=\\s*\\()/, #{q(lit.("fof"))}, "@statementOpen"]|,
        ~s|[/include(?=\\s*\\()/, #{q(lit.("include"))}, "@include"]|,
        ~s|[/\\./, #{q(lit.("."))}]|
      ],
      statementOpen: [whitespace, ~s|[/\\(/, { token: "@brackets", switchTo: "@statementName" }]|],
      statementName: [
        whitespace,
        ~s|[/(?:#{name_regex(ir)})/, #{q(class.(:label))}]|,
        ~s|[/,/, { token: #{q(lit.(","))}, switchTo: "@statementRole" }]|
      ],
      statementRole: [
        whitespace,
        ~s|[#{re.("lower_word")}, #{q(class.(:role))}]|,
        ~s|[/-/, #{q(lit.("-"))}]|,
        ~s|[/,/, { token: #{q(lit.(","))}, switchTo: "@formula" }]|
      ],
      formula:
        [whitespace, ~s|[/\\(/, "@brackets", "@push"]|, ~s|[/\\)/, "@brackets", "@pop"]|] ++
          word_rules.(),
      include: [
        whitespace,
        ~s|[/\\(/, "@brackets"]|,
        ~s|[/\\)/, "@brackets", "@pop"]|,
        ~s|[#{re.("single_quoted")}, #{q(class.(:path))}]|,
        ~s|[/(?:#{name_regex(ir)})/, #{q(class.(:label))}]|,
        ~s|[/\\*/, #{q(lit.("*"))}]|,
        ~s|[/[\\[\\]]/, "@brackets"]|,
        ~s|[/,/, #{q(lit.(","))}]|
      ],
      comment: [
        ~s|[/[^*]+/, #{q(class.(:comment))}]|,
        ~s|[/\\*\\//, #{q(class.(:comment))}, "@pop"]|,
        ~s|[/\\*/, #{q(class.(:comment))}]|
      ],
      whitespace: [
        ~s|[/[ \\t\\r\\n]+/, "white"]|,
        ~s|[#{re.("comment_line")}, #{q(class.(:comment))}]|,
        ~s|[/\\/\\*/, #{q(class.(:comment))}, "@comment"]|
      ]
    ]

    tokenizer =
      Enum.map_join(states, ",\n", fn {state, rules} ->
        "    #{state}: [\n" <> Enum.map_join(rules, ",\n", &("      " <> &1)) <> ",\n    ]"
      end)

    """
    // Generated by `mix lang_tptp.gen` from SyntaxBNF-v#{ir.version} and gen/categories.exs. Do not edit.

    import type {languages} from "monaco-editor"

    export const tptpMonarch: languages.IMonarchLanguage = {
      defaultToken: "invalid",
      tokenPostfix: ".tptp",

      dollarKeywords: #{list(dollar_keywords)},
      definedTypes: #{list(vocabulary.defined_type_values())},
      definedWords: #{list(defined)},
      roles: #{list(vocabulary.formula_role_values())},

      brackets: [
        {open: "(", close: ")", token: #{q(lit.("("))}},
        {open: "[", close: "]", token: #{q(lit.("["))}},
        {open: "{", close: "}", token: #{q(lit.("{"))}},
      ],

      tokenizer: {
    #{tokenizer},
      },
    }
    """
  end

  # The words Monarch treats specially must be the words the grammar uses.
  defp check_keywords!(ir, dollar_keywords, source_keywords) do
    expected = Enum.sort(@statement_keywords ++ ["include"] ++ dollar_keywords ++ source_keywords)

    if expected != ir.keywords do
      raise ArgumentError,
            "LangTptp.Monarch knows the keywords #{inspect(expected)}, the grammar uses #{inspect(ir.keywords)}"
    end
  end

  # A statement name: <atomic_word> or <integer>.
  defp name_regex(ir) do
    Enum.map_join(~w(lower_word single_quoted integer), "|", &Re.to_js(Map.fetch!(ir.tokens, &1)))
  end

  # `@` starts an attribute reference inside Monarch regexes, so it is written as \x40.
  defp escape(spelling) do
    spelling
    |> String.graphemes()
    |> Enum.map_join(fn
      "@" -> "\\x40"
      c -> if c =~ ~r/[\\^$.|?*+()\[\]{}\/]/, do: "\\" <> c, else: c
    end)
  end

  defp q(text), do: JSON.encode!(text)
  defp list(words), do: "[" <> Enum.map_join(words, ", ", &q/1) <> "]"
end
