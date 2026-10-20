defmodule LangTptp.RegexTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias LangTptp.Regex, as: Re

  doctest LangTptp.Regex

  @bnf Tptp.Bnf.vendored_path!()
  @oracle Tptp.Bnf.Oracle.patterns(@bnf)
  @asts (for rule <- Tptp.Bnf.read!(@bnf), rule.separator in ["::-", ":::"], into: %{} do
           {rule.lhs, Re.parse(rule.raw)}
         end)

  # Characters that matter to some token rule, plus a few that matter to none.
  @alphabet ~c"aqzAQZ019_$'\"\\` .+-/eE*%\n|<>#[]^~\t"

  defp anchored(pattern), do: Regex.compile!("\\A(?:" <> pattern <> ")\\z")

  defp printable, do: Enum.to_list(0x20..0x7E) ++ [?\n]

  # Strings the AST matches, drawn from its structure.
  defp sample({:seq, nodes}),
    do: nodes |> Enum.map(&sample/1) |> StreamData.fixed_list() |> StreamData.map(&Enum.join/1)

  defp sample({:alt, nodes}), do: StreamData.one_of(Enum.map(nodes, &sample/1))

  defp sample({:star, node}),
    do: node |> sample() |> StreamData.list_of(max_length: 3) |> StreamData.map(&Enum.join/1)

  defp sample({:char, c}), do: StreamData.constant(<<c>>)
  defp sample(:any), do: chars(Enum.reject(printable(), &(&1 == ?\n)))

  defp sample({:class, negated, ranges}) do
    inside? = fn c -> Enum.any?(ranges, fn {from, to} -> c in from..to end) end
    chars(Enum.filter(printable(), &(inside?.(&1) != negated)))
  end

  defp chars(list), do: list |> StreamData.member_of() |> StreamData.map(&<<&1>>)

  describe "to_js/1 agrees with Tptp.Bnf.Oracle" do
    for name <- Map.keys(@oracle) |> Enum.sort() do
      @name name
      property "<#{name}>" do
        ast = Re.resolve(Map.fetch!(@asts, @name), @asts)
        js = anchored(Re.to_js(ast))
        oracle = anchored(Map.fetch!(@oracle, @name))

        check all(
                text <-
                  StreamData.one_of([sample(ast), StreamData.string(@alphabet, max_length: 8)]),
                max_runs: 200
              ) do
          assert Regex.match?(js, text) == Regex.match?(oracle, text),
                 "#{inspect(text)}: printed #{Regex.match?(js, text)}, oracle #{Regex.match?(oracle, text)}"
        end
      end
    end
  end

  test "every token rule parses and resolves" do
    for {name, ast} <- @asts do
      assert Re.resolve(ast, @asts), name
    end
  end

  test "octal escapes become code points" do
    assert Re.parse("[\\40-\\41]") == {:class, false, [{?\s, ?!}]}
  end

  test "to_js escapes slashes and prints dot without newline" do
    assert Re.to_js({:seq, [{:class, false, [{?/, ?/}]}, :any]}) == "\\/[^\\n]"
  end

  test "to_lezer prints sets, negated sets and strings" do
    assert Re.to_lezer(
             {:alt, [{:class, false, [{?a, ?z}]}, {:class, true, [{?*, ?*}]}, {:char, ?"}]}
           ) ==
             ~S{$[a-z] | ![*] | '"'}
  end

  test "an unknown construct raises" do
    assert_raise ArgumentError, fn -> Re.parse("a{2}") end
  end
end
