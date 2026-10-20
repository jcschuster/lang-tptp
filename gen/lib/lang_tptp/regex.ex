defmodule LangTptp.Regex do
  @moduledoc """
  The BNF's token layer (`::-` and `:::` rules) as a small regex AST, with one printer
  per target syntax.

  `Tptp.Bnf.Oracle` substitutes raw text into PCRE, which is enough for Elixir. The
  editor targets need three different syntaxes (a JS regex for tree-sitter and Monarch,
  Lezer's `@tokens` notation), so the raw text is parsed once and printed per target.

  The AST:

    * `{:seq, [node]}` and `{:alt, [node]}`
    * `{:star, node}`
    * `{:class, negated?, [{from, to}]}` — character ranges, inclusive, as code points
    * `{:char, c}` — a single literal character outside a class
    * `:any` — `.`, any character except a newline (as in PCRE without `/s`)
    * `{:ref, name}` — a `<name>` reference, removed by `resolve/2`

  The BNF's notation is a small subset of PCRE: groups, `|`, `*`, classes with ranges
  and negation, `.`, and octal escapes such as `\\40`. Anything else raises, because a
  new construct in a future BNF should stop generation rather than be misread.
  """

  @type t ::
          {:seq, [t()]}
          | {:alt, [t()]}
          | {:star, t()}
          | {:class, boolean(), [{char(), char()}]}
          | {:char, char()}
          | :any
          | {:ref, binary()}

  ## Parsing

  @doc """
  Parse the raw right-hand side of a `::-` or `:::` rule.

      iex> LangTptp.Regex.parse("<lower_alpha><alpha_numeric>*")
      {:seq, [{:ref, "lower_alpha"}, {:star, {:ref, "alpha_numeric"}}]}

      iex> LangTptp.Regex.parse("[+-]")
      {:class, false, [{?+, ?+}, {?-, ?-}]}
  """
  @spec parse(binary()) :: t()
  def parse(raw) when is_binary(raw) do
    case parse_alt(raw) do
      {node, ""} ->
        node

      {_node, rest} ->
        raise ArgumentError, "unexpected #{inspect(rest)} in token rule #{inspect(raw)}"
    end
  end

  defp parse_alt(text) do
    {first, rest} = parse_seq(text, [])
    parse_alt_rest(rest, [first])
  end

  defp parse_alt_rest(<<"|", rest::binary>>, acc) do
    {next, rest} = parse_seq(rest, [])
    parse_alt_rest(rest, [next | acc])
  end

  defp parse_alt_rest(rest, [single]), do: {single, rest}
  defp parse_alt_rest(rest, acc), do: {{:alt, Enum.reverse(acc)}, rest}

  defp parse_seq(<<c, _::binary>> = text, acc) when c in [?|, ?)], do: {seq(acc), text}
  defp parse_seq("", acc), do: {seq(acc), ""}

  defp parse_seq(text, acc) do
    {atom, rest} = parse_atom(text)

    case rest do
      <<"*", rest::binary>> -> parse_seq(rest, [{:star, atom} | acc])
      _ -> parse_seq(rest, [atom | acc])
    end
  end

  defp seq([single]), do: single
  defp seq(acc), do: {:seq, Enum.reverse(acc)}

  defp parse_atom(<<"(", rest::binary>>) do
    case parse_alt(rest) do
      {node, <<")", rest::binary>>} -> {node, rest}
      {_node, rest} -> raise ArgumentError, "unclosed group before #{inspect(rest)}"
    end
  end

  defp parse_atom(<<"[^", rest::binary>>), do: parse_class(rest, true, [])
  defp parse_atom(<<"[", rest::binary>>), do: parse_class(rest, false, [])
  defp parse_atom(<<".", rest::binary>>), do: {:any, rest}

  defp parse_atom(<<"<", _::binary>> = text) do
    case Regex.run(~r/^<([A-Za-z_][A-Za-z_0-9]*)>/, text) do
      [whole, name] ->
        {{:ref, name}, binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))}

      nil ->
        {{:char, ?<}, binary_part(text, 1, byte_size(text) - 1)}
    end
  end

  defp parse_atom(<<"\\", _::binary>> = text) do
    {c, rest} = escape(text)
    {{:char, c}, rest}
  end

  # Regex syntax the BNF does not use (`+`, `?`, `{n}`, anchors) is rejected rather
  # than read as a literal character.
  defp parse_atom(<<c::utf8, rest::binary>>) when c not in ~c"*)|]{}+?^$", do: {{:char, c}, rest}
  defp parse_atom(text), do: raise(ArgumentError, "cannot parse token rule at #{inspect(text)}")

  defp parse_class(<<"]", rest::binary>>, negated, acc) when acc != [] do
    {{:class, negated, Enum.reverse(acc)}, rest}
  end

  defp parse_class("", _negated, _acc), do: raise(ArgumentError, "unclosed character class")

  defp parse_class(text, negated, acc) do
    {from, rest} = class_char(text)

    case rest do
      <<"-", next, _::binary>> = with_dash when next != ?] ->
        {to, rest} = class_char(binary_part(with_dash, 1, byte_size(with_dash) - 1))
        parse_class(rest, negated, [{from, to} | acc])

      _ ->
        parse_class(rest, negated, [{from, from} | acc])
    end
  end

  defp class_char(<<"\\", _::binary>> = text), do: escape(text)
  defp class_char(<<c::utf8, rest::binary>>), do: {c, rest}

  # `\40` (octal, as in the BNF), `\\`, `\n`, `\t`, `\r`; any other escaped character
  # stands for itself.
  defp escape(<<"\\", rest::binary>>) do
    case Regex.run(~r/^[0-7]{1,3}/, rest) do
      [digits] ->
        {String.to_integer(digits, 8),
         binary_part(rest, byte_size(digits), byte_size(rest) - byte_size(digits))}

      nil ->
        case rest do
          <<"n", rest::binary>> -> {?\n, rest}
          <<"t", rest::binary>> -> {?\t, rest}
          <<"r", rest::binary>> -> {?\r, rest}
          <<c::utf8, rest::binary>> -> {c, rest}
        end
    end
  end

  ## Resolution

  @doc """
  Replace every `{:ref, name}` with the referenced rule's AST, recursively.

  Raises on a cycle or an undefined name, like `Tptp.Bnf.Oracle` does.
  """
  @spec resolve(t(), %{binary() => t()}) :: t()
  def resolve(node, defs), do: resolve(node, defs, [])

  defp resolve({:ref, name}, defs, seen) do
    if name in seen,
      do: raise(ArgumentError, "token rules are cyclic through <#{name}>: #{inspect(seen)}")

    case Map.fetch(defs, name) do
      {:ok, node} ->
        resolve(node, defs, [name | seen])

      :error ->
        raise ArgumentError, "<#{name}> is referenced by a token rule but has none of its own"
    end
  end

  defp resolve({:seq, nodes}, defs, seen), do: {:seq, Enum.map(nodes, &resolve(&1, defs, seen))}
  defp resolve({:alt, nodes}, defs, seen), do: {:alt, Enum.map(nodes, &resolve(&1, defs, seen))}
  defp resolve({:star, node}, defs, seen), do: {:star, resolve(node, defs, seen)}
  defp resolve(node, _defs, _seen), do: node

  @doc """
  The one string a pattern matches, if it matches exactly one.

      iex> LangTptp.Regex.fixed_string({:class, false, [{?|, ?|}]})
      "|"

      iex> LangTptp.Regex.fixed_string({:class, false, [{?a, ?z}]})
      nil
  """
  @spec fixed_string(t()) :: binary() | nil
  def fixed_string({:char, c}), do: <<c::utf8>>
  def fixed_string({:class, false, [{c, c}]}), do: <<c::utf8>>

  def fixed_string({:seq, nodes}) do
    parts = Enum.map(nodes, &fixed_string/1)
    if Enum.all?(parts), do: Enum.join(parts)
  end

  def fixed_string({:alt, [single]}), do: fixed_string(single)
  def fixed_string(_node), do: nil

  ## Printers

  @doc """
  Print as a JavaScript regex body (no slashes), for tree-sitter and Monarch.

  Only syntax that PCRE reads the same way is used — `(?:…)`, `[…]`, `\\xNN` — so the
  output can be compiled with Elixir's `Regex` and compared against the oracle. `/` is
  escaped so the result can sit inside a `/…/` literal; `.` is printed as `[^\\n]`
  because JS's `.` also excludes `\\r`, while the BNF's (PCRE's) does not.

      iex> LangTptp.Regex.to_js({:seq, [{:class, false, [{?a, ?z}]}, {:star, {:class, false, [{?0, ?9}, {?_, ?_}]}}]})
      "[a-z][0-9_]*"
  """
  @spec to_js(t()) :: binary()
  def to_js(node), do: js(node, :top)

  defp js({:seq, nodes}, ctx) do
    body = Enum.map_join(nodes, &js(&1, :seq))
    if ctx == :star, do: "(?:#{body})", else: body
  end

  defp js({:alt, nodes}, ctx) do
    body = Enum.map_join(nodes, "|", &js(&1, :alt))
    if ctx == :top, do: body, else: "(?:#{body})"
  end

  defp js({:star, node}, _ctx), do: js(node, :star) <> "*"
  defp js(:any, _ctx), do: "[^\\n]"
  defp js({:char, c}, _ctx), do: js_char(c, :outside)
  defp js({:class, false, [{c, c}]}, _ctx), do: js_char(c, :outside)

  defp js({:class, negated, ranges}, _ctx) do
    "[" <> if(negated, do: "^", else: "") <> Enum.map_join(ranges, &js_range/1) <> "]"
  end

  defp js({:ref, name}, _ctx), do: raise(ArgumentError, "unresolved reference <#{name}>")

  defp js_range({c, c}), do: js_char(c, :class)
  defp js_range({from, to}), do: js_char(from, :class) <> "-" <> js_char(to, :class)

  @js_meta ~c"\\^$.|?*+()[]{}/"
  @js_class_meta ~c"\\]^-[/"

  defp js_char(?\n, _where), do: "\\n"
  defp js_char(?\t, _where), do: "\\t"
  defp js_char(?\r, _where), do: "\\r"
  defp js_char(?\s, _where), do: "\\x20"
  defp js_char(c, _where) when c < 0x20 or c == 0x7F, do: "\\x" <> hex2(c)
  defp js_char(c, :outside) when c in @js_meta, do: <<?\\, c>>
  defp js_char(c, :class) when c in @js_class_meta, do: <<?\\, c>>
  defp js_char(c, _where), do: <<c::utf8>>

  defp hex2(c), do: c |> Integer.to_string(16) |> String.pad_leading(2, "0")

  @doc ~S"""
  Print in Lezer's `@tokens` notation.

  Character sets are `$[…]`, negated sets `![…]`, single characters string literals,
  and `.` becomes `![\n]` (Lezer's `_` would include the newline).

      iex> LangTptp.Regex.to_lezer({:seq, [{:class, false, [{?a, ?z}]}, {:star, {:class, true, [{?*, ?*}]}}]})
      ~S|$[a-z] ![*]*|
  """
  @spec to_lezer(t()) :: binary()
  def to_lezer(node), do: lezer(node, :top)

  defp lezer({:seq, nodes}, ctx) do
    body = Enum.map_join(nodes, " ", &lezer(&1, :seq))
    if ctx == :star, do: "(#{body})", else: body
  end

  defp lezer({:alt, nodes}, ctx) do
    body = Enum.map_join(nodes, " | ", &lezer(&1, :alt))
    if ctx == :top, do: body, else: "(#{body})"
  end

  defp lezer({:star, node}, _ctx), do: lezer(node, :star) <> "*"
  defp lezer(:any, _ctx), do: "![\\n]"
  defp lezer({:char, c}, _ctx), do: lezer_string(c)
  defp lezer({:class, false, [{c, c}]}, _ctx), do: lezer_string(c)

  defp lezer({:class, negated, ranges}, _ctx) do
    if(negated, do: "![", else: "$[") <> Enum.map_join(ranges, &lezer_range/1) <> "]"
  end

  defp lezer({:ref, name}, _ctx), do: raise(ArgumentError, "unresolved reference <#{name}>")

  defp lezer_range({c, c}), do: lezer_set_char(c)
  defp lezer_range({from, to}), do: lezer_set_char(from) <> "-" <> lezer_set_char(to)

  defp lezer_string(?"), do: ~S|'"'|
  defp lezer_string(c), do: ~s|"#{lezer_escape(c, ~c"\\\"")}"|

  defp lezer_set_char(c), do: lezer_escape(c, ~c"\\]-[^")

  defp lezer_escape(?\n, _meta), do: "\\n"
  defp lezer_escape(?\t, _meta), do: "\\t"
  defp lezer_escape(?\r, _meta), do: "\\r"

  defp lezer_escape(c, _meta) when c < 0x20 or c == 0x7F,
    do: "\\u{" <> Integer.to_string(c, 16) <> "}"

  defp lezer_escape(c, meta), do: if(c in meta, do: <<?\\, c::utf8>>, else: <<c::utf8>>)
end
