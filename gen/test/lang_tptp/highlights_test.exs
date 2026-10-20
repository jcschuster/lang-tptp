defmodule LangTptp.HighlightsTest do
  use ExUnit.Case, async: true

  alias LangTptp.Highlights
  alias LangTptp.IR

  @moduletag :tmp_dir

  setup_all do
    {:ok, ir: IR.build()}
  end

  defp table_with(tmp_dir, edit) do
    path = Path.join(tmp_dir, "categories.exs")
    File.write!(path, edit.(File.read!(Highlights.path())))
    path
  end

  test "the committed table is valid", %{ir: ir} do
    table = Highlights.load!(ir)
    assert Highlights.literal_category(table, "<=>") == :operator
    assert Highlights.target(table, :role, :tree_sitter) == "keyword.modifier"
  end

  test "a literal without a category fails", %{ir: ir, tmp_dir: tmp_dir} do
    path = table_with(tmp_dir, &String.replace(&1, "~w(, . : -)", "~w(, . :)"))

    assert_raise ArgumentError, ~r/no category to the literals -/, fn ->
      Highlights.load!(ir, path)
    end
  end

  test "a node that is not visible fails", %{ir: ir, tmp_dir: tmp_dir} do
    path =
      table_with(tmp_dir, &String.replace(&1, ~s({"name", :label}), ~s({"fof_formula", :label})))

    assert_raise ArgumentError, ~r/<fof_formula>, which is not a visible node/, fn ->
      Highlights.load!(ir, path)
    end
  end

  test "highlights.scm patterns for one node do not overlap", %{ir: ir} do
    scm = Highlights.render_tree_sitter(Highlights.load!(ir), ir)
    assert scm =~ "(constant (functor) @constant)"
    assert scm =~ "(fof_plain_term (functor) @function)"
    refute scm =~ "(constant (functor) @function)"
    refute scm =~ ~r/^\(functor\) @function$/m
  end

  test "visible parents look through hidden rules", %{ir: ir} do
    assert "constant" in Highlights.visible_parents(ir, "functor")
    assert "fof_plain_term" in Highlights.visible_parents(ir, "functor")

    refute Enum.any?(
             Highlights.visible_parents(ir, "functor"),
             &MapSet.member?(ir.transparent, &1)
           )
  end

  test "styleTags quote names that are not words", %{ir: ir} do
    ts = Highlights.render_lezer(Highlights.load!(ir), ir, &LangTptp.Lezer.name(ir, &1))
    assert ts =~ ~s|"Constant/Functor/...": t.constant(t.variableName)|
    assert ts =~ ~s|\\"<=>\\"|
  end
end
