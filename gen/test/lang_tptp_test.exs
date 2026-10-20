defmodule LangTptpTest do
  use ExUnit.Case, async: true

  doctest LangTptp

  alias LangTptp.IR

  setup_all do
    {:ok, ir: IR.build()}
  end

  test "the committed generated files are up to date" do
    root = LangTptp.root()

    for {path, content} <- LangTptp.outputs(root) do
      assert File.read!(Path.join(root, path)) == content,
             "#{path} is stale; run `mix lang_tptp.gen`"
    end
  end

  test "tree-sitter departures are in the grammar", %{ir: ir} do
    grammar = LangTptp.TreeSitter.render(ir)

    for word <- ~w(inference introduced file) do
      assert grammar =~ ~s|alias("#{word}", $.lower_word)|
    end

    assert length(LangTptp.TreeSitter.departures()) == 1
  end

  test "Lezer departures are in the grammar", %{ir: ir} do
    grammar = LangTptp.Lezer.render(ir)

    for word <- ir.keywords do
      assert grammar =~ ~r/@(extend|specialize)\[@name=("?)#{Regex.escape(word)}\2\]/
    end

    assert grammar =~
             ~s|FofAndFormula { fof_unit_formula "&" fof_unit_formula ("&" fof_unit_formula)* }|

    assert grammar =~ ~s|NameList { Name ("," Name)* }|
  end

  test "transparent rules are hidden in both grammars", %{ir: ir} do
    assert LangTptp.TreeSitter.name(ir, "fof_formula") == "_fof_formula"
    assert LangTptp.Lezer.name(ir, "fof_formula") == "fof_formula"
    assert LangTptp.TreeSitter.name(ir, "fof_annotated") == "fof_annotated"
    assert LangTptp.Lezer.name(ir, "fof_annotated") == "FofAnnotated"
    assert LangTptp.Lezer.name(ir, "TPTP_file") == "TPTPFile"
  end

  test "the BNF version stamp is replaced in place" do
    json = ~s({\n  "license": "MIT",\n  "tptp": {\n    "bnf": "1.0"\n  }\n}\n)
    assert LangTptp.stamp_bnf_version(json, "1.2.3.4") =~ ~s("bnf": "1.2.3.4")

    assert LangTptp.stamp_bnf_version(~s({\n  "license": "MIT"\n}\n), "2") =~
             ~s("license": "MIT",\n  "tptp")
  end
end
