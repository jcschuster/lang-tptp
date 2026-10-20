defmodule LangTptp.IR do
  @moduledoc """
  The `SyntaxBNF` as a grammar IR that every back-end prints from.

  Built from the public parts of `Tptp.Bnf` (`read!/1`, `merge_alternatives/1`,
  `definitions/1`) and `Tptp.Token`. The resolution steps follow
  `Tptp.Bnf.Generator`, which keeps them private:

    * **Repetition.** `<x>*` in a `::=` rule becomes `{:repeat, symbol}`. Both
      tree-sitter and Lezer have repetition, so no helper nonterminal is needed.
    * **Literals.** Literal runs are split against `Tptp.Token.spellings/0`, longest
      match first, so `tpi(` becomes `"tpi"` `"("`.
    * **Fixed-spelling token rules** referenced from `::=` rules (`<vline>`,
      `<star>`, `<plus>`, `<arrow>`, `<less_sign>`, `<hash>`) become literals, and
      literal runs that came apart only because of such a reference are merged back
      into one spelling: `~<vline>` is `"~|"`, `<less_sign>.<arrow>` is `"<.>"`.
      This is what `Tptp.Bnf.Generator`'s `rewrite_sequences` does by hand.
    * **`<nothing>`** as the only symbol of an alternative becomes `[]`.
    * **Single-terminal rules** such as `<assignment> ::= :=` are inlined, except
      for the root and the significant names.
    * **Pruning.** Rules not reachable from `TPTP_file` are dropped.

  A symbol is `{:nt, name}`, `{:token, name}` (a value token: `<lower_word>`,
  `<integer>`, …), `{:lit, spelling}` or `{:repeat, symbol}`.
  """

  alias Tptp.Bnf
  alias Tptp.Token
  alias LangTptp.Regex, as: Re

  @root "TPTP_file"

  @typedoc "A grammar symbol."
  @type symbol ::
          {:nt, binary()} | {:token, binary()} | {:lit, binary()} | {:repeat, symbol()}

  @type t :: %__MODULE__{
          version: binary(),
          bnf_path: Path.t(),
          root: binary(),
          rules: [{binary(), [[symbol()]]}],
          tokens: %{binary() => Re.t()},
          token_order: [binary()],
          literals: [binary()],
          keywords: [binary()],
          nullable: MapSet.t(binary()),
          transparent: MapSet.t(binary()),
          significant: [binary()],
          inlined: [binary()],
          pruned: [binary()],
          merged: [binary()]
        }

  defstruct [
    :version,
    :bnf_path,
    :root,
    :rules,
    :tokens,
    :token_order,
    :literals,
    :keywords,
    :nullable,
    :transparent,
    :significant,
    :inlined,
    :pruned,
    :merged
  ]

  @doc "Build the IR from the vendored BNF."
  @spec build() :: t()
  def build, do: build(Bnf.vendored_path!())

  @doc "Build the IR from a `SyntaxBNF` file."
  @spec build(Path.t()) :: t()
  def build(bnf_path) do
    rules = bnf_path |> Bnf.read!() |> Bnf.merge_alternatives()
    definitions = Bnf.definitions(rules)

    token_asts =
      for rule <- rules, rule.separator in ["::-", ":::"], into: %{} do
        {rule.lhs, Re.parse(rule.raw)}
      end

    tokens = Map.new(token_asts, fn {name, ast} -> {name, Re.resolve(ast, token_asts)} end)

    significant = Enum.map(Tptp.Bnf.Generator.significant(), &Atom.to_string/1)

    syntactic =
      rules
      |> Enum.filter(&(&1.separator == "::=" and &1.lhs != "nothing"))

    {resolved, merged} =
      Enum.map_reduce(syntactic, [], fn rule, merged ->
        {alts, new} =
          Enum.map_reduce(rule.alternatives, [], fn alt, acc ->
            {symbols, merges} = resolve_alternative(alt, rule, definitions, tokens)
            {symbols, acc ++ merges}
          end)

        {{rule.lhs, alts}, merged ++ new}
      end)

    {resolved, inlined} = inline_terminal_rules(resolved, significant)

    reachable = reachable(resolved, @root)
    pruned = for {name, _} <- resolved, not MapSet.member?(reachable, name), do: name
    kept = Enum.filter(resolved, fn {name, _} -> MapSet.member?(reachable, name) end)

    used_tokens =
      for {_, alts} <- kept,
          alt <- alts,
          sym <- alt,
          name <- token_names(sym),
          uniq: true,
          do: name

    literals =
      for {_, alts} <- kept,
          alt <- alts,
          sym <- alt,
          lit <- literal_spellings(sym),
          uniq: true,
          do: lit

    %__MODULE__{
      version: Bnf.version!(bnf_path),
      bnf_path: bnf_path,
      root: @root,
      rules: kept,
      tokens: tokens,
      token_order: Enum.sort(used_tokens),
      literals: Enum.sort(literals),
      keywords: literals |> Enum.filter(&word?/1) |> Enum.sort(),
      nullable: nullable(kept),
      transparent: transparent(kept, significant),
      significant: Enum.filter(significant, &MapSet.member?(reachable, &1)),
      inlined: Enum.sort(inlined),
      pruned: Enum.sort(pruned),
      merged: merged |> Enum.uniq() |> Enum.sort()
    }
  end

  @doc "Alternatives of one rule. Raises for an unknown name."
  @spec alternatives(t(), binary()) :: [[symbol()]]
  def alternatives(%__MODULE__{rules: rules}, name) do
    case List.keyfind(rules, name, 0) do
      {^name, alts} -> alts
      nil -> raise ArgumentError, "no rule <#{name}> in the IR"
    end
  end

  @doc "Whether a name is a rule (nonterminal) of the IR."
  @spec rule?(t(), binary()) :: boolean()
  def rule?(%__MODULE__{rules: rules}, name), do: List.keymember?(rules, name, 0)

  @doc "Whether a spelling is a word (a keyword) rather than punctuation or an operator."
  @spec word?(binary()) :: boolean()
  def word?(spelling), do: Regex.match?(~r/^\$?[a-z]/, spelling)

  ## Resolution

  defp resolve_alternative([{:ref, "nothing"}], _rule, _definitions, _tokens), do: {[], []}

  defp resolve_alternative(symbols, rule, definitions, tokens) do
    symbols
    |> mark_repetition([])
    |> Enum.flat_map(&resolve_symbol(&1, rule, definitions, tokens))
    |> merge_literals([], [])
  end

  defp mark_repetition([], acc), do: Enum.reverse(acc)

  defp mark_repetition([{:ref, name}, {:literal, "*"} | rest], acc),
    do: mark_repetition(rest, [{:repeat_ref, name} | acc])

  defp mark_repetition([symbol | rest], acc), do: mark_repetition(rest, [symbol | acc])

  # A literal that came from a token reference is tagged `:from_ref` until merging.
  defp resolve_symbol({:repeat_ref, name}, rule, definitions, tokens) do
    [sym] = resolve_symbol({:ref, name}, rule, definitions, tokens)
    [{:repeat, untag(sym)}]
  end

  defp resolve_symbol({:ref, name}, rule, definitions, tokens) do
    case Map.fetch(definitions, name) do
      {:ok, "::="} ->
        [{:nt, name}]

      {:ok, sep} when sep in ["::-", ":::"] ->
        case Re.fixed_string(Map.fetch!(tokens, name)) do
          nil -> [{:token, name}]
          spelling -> [{:lit_from_ref, spelling}]
        end

      {:ok, ":=="} ->
        raise ArgumentError,
              "<#{name}> is referenced from the syntactic rule <#{rule.lhs}> on line #{rule.line} " <>
                "but only defined by a :== semantic rule"

      :error ->
        raise ArgumentError,
              "<#{name}> is referenced from <#{rule.lhs}> on line #{rule.line} but never defined"
    end
  end

  defp resolve_symbol({:literal, text}, rule, _definitions, _tokens) do
    Enum.map(split_literal(text, rule), &{:lit, &1})
  end

  defp untag({:lit_from_ref, s}), do: {:lit, s}
  defp untag(sym), do: sym

  # Merge a run of adjacent literals into one known spelling when at least one of them
  # came from a token reference. Only such runs can have been split artificially.
  defp merge_literals([], acc, merges), do: {Enum.reverse(acc), merges}

  defp merge_literals(symbols, acc, merges) do
    case longest_merge(symbols) do
      {spelling, n} ->
        merge_literals(Enum.drop(symbols, n), [{:lit, spelling} | acc], [spelling | merges])

      nil ->
        [sym | rest] = symbols
        merge_literals(rest, [untag(sym) | acc], merges)
    end
  end

  defp longest_merge(symbols) do
    run = Enum.take_while(symbols, &match?({tag, _} when tag in [:lit, :lit_from_ref], &1))

    if length(run) >= 2 do
      spellings = MapSet.new(Token.spellings(), &elem(&1, 1))

      Enum.find_value(length(run)..2//-1, fn n ->
        prefix = Enum.take(run, n)
        joined = Enum.map_join(prefix, fn {_, s} -> s end)

        if Enum.any?(prefix, &match?({:lit_from_ref, _}, &1)) and
             MapSet.member?(spellings, joined),
           do: {joined, n}
      end)
    end
  end

  defp split_literal("", _rule), do: []

  defp split_literal(<<c, _::binary>> = text, rule)
       when c == ?$ or c in ?a..?z or c in ?A..?Z do
    [word] = Regex.run(~r/^\$?[A-Za-z0-9_]+/, text)

    if Token.category_for(word) == nil do
      raise ArgumentError,
            "#{inspect(word)} on line #{rule.line} of the BNF is not a keyword Tptp.Token knows"
    end

    [word | split_literal(drop(text, word), rule)]
  end

  defp split_literal(text, rule) do
    case Enum.find(Token.spellings(), fn {_c, s} -> String.starts_with?(text, s) end) do
      {_category, spelling} ->
        [spelling | split_literal(drop(text, spelling), rule)]

      nil ->
        raise ArgumentError,
              "no terminal matches #{inspect(text)} on line #{rule.line} of the BNF"
    end
  end

  defp drop(text, prefix),
    do: binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix))

  ## Passes

  defp inline_terminal_rules(resolved, significant),
    do: inline_terminal_rules(resolved, significant, [])

  defp inline_terminal_rules(resolved, significant, done) do
    candidates =
      for {lhs, [[{tag, _} = terminal]]} <- resolved,
          tag in [:lit, :token],
          lhs != @root,
          lhs not in significant,
          into: %{},
          do: {lhs, terminal}

    if candidates == %{} do
      {resolved, done}
    else
      resolved
      |> Enum.reject(fn {lhs, _} -> Map.has_key?(candidates, lhs) end)
      |> Enum.map(fn {lhs, alts} ->
        {lhs, Enum.map(alts, fn alt -> Enum.map(alt, &substitute(&1, candidates)) end)}
      end)
      |> inline_terminal_rules(significant, done ++ Map.keys(candidates))
    end
  end

  defp substitute({:nt, name} = sym, candidates), do: Map.get(candidates, name, sym)
  defp substitute({:repeat, sym}, candidates), do: {:repeat, substitute(sym, candidates)}
  defp substitute(sym, _candidates), do: sym

  defp reachable(resolved, root) do
    by_name = Map.new(resolved)
    reach(by_name, [root], MapSet.new())
  end

  defp reach(_by_name, [], seen), do: seen

  defp reach(by_name, [name | rest], seen) do
    if MapSet.member?(seen, name) do
      reach(by_name, rest, seen)
    else
      next = for alt <- Map.get(by_name, name, []), sym <- alt, n <- nt_names(sym), do: n
      reach(by_name, next ++ rest, MapSet.put(seen, name))
    end
  end

  @doc false
  def nt_names({:nt, name}), do: [name]
  def nt_names({:repeat, sym}), do: nt_names(sym)
  def nt_names(_sym), do: []

  defp token_names({:token, name}), do: [name]
  defp token_names({:repeat, sym}), do: token_names(sym)
  defp token_names(_sym), do: []

  defp literal_spellings({:lit, s}), do: [s]
  defp literal_spellings({:repeat, sym}), do: literal_spellings(sym)
  defp literal_spellings(_sym), do: []

  # Fixpoint: a rule is nullable when some alternative consists only of nullable symbols.
  defp nullable(rules), do: nullable(rules, MapSet.new())

  defp nullable(rules, known) do
    next =
      for {name, alts} <- rules,
          Enum.any?(alts, fn alt -> Enum.all?(alt, &nullable_symbol?(&1, known)) end),
          into: known,
          do: name

    if MapSet.equal?(next, known), do: known, else: nullable(rules, next)
  end

  @doc false
  def nullable_symbol?({:repeat, _}, _known), do: true
  def nullable_symbol?({:nt, name}, known), do: MapSet.member?(known, name)
  def nullable_symbol?(_sym, _known), do: false

  # A rule is transparent when every alternative has exactly one child (a nonterminal,
  # a repetition or a value token), so a node for it carries no information.
  defp transparent(rules, significant) do
    for {name, alts} <- rules,
        name not in significant,
        name != @root,
        alts != [],
        Enum.all?(alts, &match?([_], children(&1))),
        into: MapSet.new(),
        do: name
  end

  defp children(alt), do: Enum.reject(alt, &match?({:lit, _}, &1))
end
