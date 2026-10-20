defmodule LangTptp.IRTest do
  use ExUnit.Case, async: true

  alias LangTptp.IR

  setup_all do
    {:ok, ir: IR.build()}
  end

  test "carries the BNF version", %{ir: ir} do
    assert ir.version == Tptp.bnf_version()
  end

  test "every nonterminal reference resolves to a rule", %{ir: ir} do
    for {_name, alts} <- ir.rules, alt <- alts, sym <- alt, ref <- IR.nt_names(sym) do
      assert IR.rule?(ir, ref), "<#{ref}> is referenced but has no rule"
    end
  end

  test "only known symbol shapes remain", %{ir: ir} do
    for {_name, alts} <- ir.rules, alt <- alts, sym <- alt do
      assert match?({tag, _} when tag in [:nt, :token, :lit, :repeat], sym), inspect(sym)
    end
  end

  test "every value token has a resolved regex", %{ir: ir} do
    for name <- ir.token_order ++ ["comment"] do
      assert ir.tokens |> Map.fetch!(name) |> LangTptp.Regex.to_js() |> is_binary()
    end
  end

  test "token references split by the BNF are merged back", %{ir: ir} do
    assert ir.merged == ["<.>", "~|"]
    assert "~|" in ir.literals and "<.>" in ir.literals
    refute "~" in Enum.filter(ir.literals, &(&1 == "~|"))
  end

  test "literals split against Tptp.Token's spellings", %{ir: ir} do
    spellings = MapSet.new(Tptp.Token.spellings(), &elem(&1, 1))
    assert Enum.all?(ir.literals, &MapSet.member?(spellings, &1))
  end

  test "<nothing> alternatives become empty and their rules nullable", %{ir: ir} do
    assert [] in IR.alternatives(ir, "annotations")
    assert MapSet.member?(ir.nullable, "annotations")
    assert MapSet.member?(ir.nullable, "TPTP_file")
    refute MapSet.member?(ir.nullable, "fof_annotated")
  end

  test "keywords are the statement, source and $-keywords", %{ir: ir} do
    expected =
      (Tptp.Token.statement_keywords() ++
         Tptp.Token.source_keywords() ++ Tptp.Token.dollar_keywords())
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort()

    assert ir.keywords == expected
  end

  test "significant names stay visible", %{ir: ir} do
    for name <- ~w(variable functor formula_role name defined_functor) do
      assert IR.rule?(ir, name)
      refute MapSet.member?(ir.transparent, name)
    end
  end

  test "the root is not pruned and nothing reachable is", %{ir: ir} do
    assert IR.rule?(ir, "TPTP_file")
    assert ir.pruned == []
  end
end
