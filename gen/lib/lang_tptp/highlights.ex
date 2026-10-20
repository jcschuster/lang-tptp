defmodule LangTptp.Highlights do
  @moduledoc """
  Loads the highlight table (`categories.exs`) and renders it for each target, so the
  three targets get their highlighting from one place.

  `load!/1` validates the table against the IR: every literal spelling of the
  grammar must have a category, and every node named must be a visible node of the
  generated grammars. A BNF release that adds an operator therefore fails generation
  until the operator is given a category.
  """

  alias LangTptp.IR

  @categories_path Path.expand("../../categories.exs", __DIR__)
  @external_resource @categories_path

  @type category :: atom()
  @type selector :: {binary() | nil, binary()}

  @type t :: %{
          targets: %{category() => %{tree_sitter: binary(), lezer: binary(), monarch: binary()}},
          nodes: [{selector(), category()}],
          literals: %{binary() => category()}
        }

  @doc "Path of the hand-written table."
  @spec path() :: Path.t()
  def path, do: @categories_path

  @doc "Load and validate the table against the IR."
  @spec load!(IR.t(), Path.t()) :: t()
  def load!(%IR{} = ir, path \\ @categories_path) do
    {raw, _binding} = Code.eval_file(path)

    nodes =
      Enum.map(raw.nodes, fn {selector, category} -> {parse_selector(selector), category} end)

    literals =
      for {category, spellings} <- raw.literals, spelling <- spellings, reduce: %{} do
        acc ->
          if Map.has_key?(acc, spelling) do
            raise ArgumentError,
                  "#{inspect(spelling)} has two categories in #{Path.basename(path)}"
          end

          Map.put(acc, spelling, category)
      end

    table = %{targets: raw.targets, nodes: nodes, literals: literals}
    validate!(table, ir, path)
    table
  end

  defp parse_selector(selector) do
    case String.split(selector, ">", trim: true) |> Enum.map(&String.trim/1) do
      [child] -> {nil, child}
      [parent, child] -> {parent, child}
      _ -> raise ArgumentError, "selector #{inspect(selector)} may have at most one parent"
    end
  end

  defp validate!(table, ir, path) do
    file = Path.basename(path)

    missing = Enum.reject(ir.literals, &Map.has_key?(table.literals, &1))

    if missing != [] do
      raise ArgumentError, "#{file} gives no category to the literals #{Enum.join(missing, " ")}"
    end

    unused = Map.keys(table.literals) -- ir.literals

    if unused != [] do
      raise ArgumentError,
            "#{file} lists literals the grammar does not use: #{Enum.join(Enum.sort(unused), " ")}"
    end

    for {{parent, child}, category} <- table.nodes,
        name <- Enum.reject([parent, child], &is_nil/1) do
      unless visible?(ir, name) do
        raise ArgumentError, "#{file} names <#{name}>, which is not a visible node of the grammar"
      end

      unless Map.has_key?(table.targets, category) do
        raise ArgumentError,
              "#{file} uses the category #{inspect(category)} without naming it in targets"
      end
    end

    for {_spelling, category} <- table.literals, not Map.has_key?(table.targets, category) do
      raise ArgumentError,
            "#{file} uses the category #{inspect(category)} without naming it in targets"
    end

    :ok
  end

  @doc "Whether a BNF name is a node that appears in the generated trees."
  @spec visible?(IR.t(), binary()) :: boolean()
  def visible?(ir, name) do
    name == "comment" or name in ir.token_order or
      (IR.rule?(ir, name) and not MapSet.member?(ir.transparent, name))
  end

  @doc "The category of a literal spelling."
  @spec literal_category(t(), binary()) :: category()
  def literal_category(table, spelling), do: Map.fetch!(table.literals, spelling)

  @doc "The name of a category for one target."
  @spec target(t(), category(), :tree_sitter | :lezer | :monarch) :: binary()
  def target(table, category, which),
    do: table.targets |> Map.fetch!(category) |> Map.fetch!(which)

  ## tree-sitter

  @doc """
  Render `queries/highlights.scm`.

  Editors disagree on which of two patterns capturing the same node wins, so the
  patterns never overlap: when the table has `parent > child` entries, the plain
  `child` entry is expanded into one pattern per other parent the child can have
  in the tree (looking through hidden rules).
  """
  @spec render_tree_sitter(t(), IR.t()) :: binary()
  def render_tree_sitter(table, %IR{} = ir) do
    contexts =
      for {{parent, child}, _category} <- table.nodes, parent != nil, reduce: %{} do
        acc -> Map.update(acc, child, [parent], &[parent | &1])
      end

    nodes =
      Enum.map_join(table.nodes, "\n", fn
        {{nil, child}, category} ->
          capture = "@" <> target(table, category, :tree_sitter)

          case Map.fetch(contexts, child) do
            :error ->
              "(#{child}) #{capture}"

            {:ok, excluded} ->
              (visible_parents(ir, child) -- excluded)
              |> Enum.map_join("\n", &"(#{&1} (#{child}) #{capture})")
          end

        {{parent, child}, category} ->
          "(#{parent} (#{child}) @#{target(table, category, :tree_sitter)})"
      end)

    literals =
      table.literals
      |> Enum.group_by(fn {_s, c} -> c end, fn {s, _c} -> s end)
      |> Enum.sort()
      |> Enum.map_join("\n\n", fn {category, spellings} ->
        items = spellings |> Enum.sort() |> Enum.map_join("\n", &("  " <> JSON.encode!(&1)))
        "[\n#{items}\n] @#{target(table, category, :tree_sitter)}"
      end)

    """
    ; Generated by `mix lang_tptp.gen` from gen/categories.exs and SyntaxBNF-v#{ir.version}. Do not edit.

    #{nodes}

    #{literals}
    """
  end

  @doc """
  The visible nodes that can be the direct parent of `name` in a tree: the rules
  that use it, with hidden (transparent) rules replaced by their own parents.
  """
  @spec visible_parents(IR.t(), binary()) :: [binary()]
  def visible_parents(%IR{} = ir, name), do: ir |> parents(name, MapSet.new()) |> Enum.sort()

  defp parents(ir, name, seen) do
    users =
      for {rule, alts} <- ir.rules,
          Enum.any?(alts, fn alt ->
            Enum.any?(alt, &(name in IR.nt_names(&1) or &1 == {:token, name}))
          end),
          uniq: true,
          do: rule

    Enum.flat_map(users, fn user ->
      cond do
        MapSet.member?(seen, user) -> []
        MapSet.member?(ir.transparent, user) -> parents(ir, user, MapSet.put(seen, user))
        true -> [user]
      end
    end)
    |> Enum.uniq()
  end

  ## Lezer

  @doc """
  Render `src/highlight.ts`: a `styleTags` call for the Lezer grammar.

  `node_name` maps a BNF name to the Lezer node name.
  """
  @spec render_lezer(t(), IR.t(), (binary() -> binary())) :: binary()
  def render_lezer(table, %IR{} = ir, node_name) do
    # A style on a nonterminal covers only text its children do not, unless the
    # selector ends in `/...`; inner nodes' own styles still take precedence.
    whole = fn name ->
      if IR.rule?(ir, name), do: node_name.(name) <> "/...", else: node_name.(name)
    end

    nodes =
      Enum.map(table.nodes, fn
        {{nil, child}, category} -> {whole.(child), category}
        {{parent, child}, category} -> {node_name.(parent) <> "/" <> whole.(child), category}
      end)

    literals =
      table.literals
      |> Enum.group_by(fn {_s, c} -> c end, fn {s, _c} -> s end)
      |> Enum.sort()
      |> Enum.map(fn {category, spellings} ->
        {spellings |> Enum.sort() |> Enum.map_join(" ", &lezer_selector_name/1), category}
      end)

    entries =
      Enum.map_join(nodes ++ literals, ",\n", fn {selector, category} ->
        "  #{JSON.encode!(selector)}: #{lezer_tag(target(table, category, :lezer))}"
      end)

    """
    // Generated by `mix lang_tptp.gen` from gen/categories.exs and SyntaxBNF-v#{ir.version}. Do not edit.

    import type {NodePropSource} from "@lezer/common"
    import {styleTags, tags as t} from "@lezer/highlight"

    export const tptpHighlighting: NodePropSource = styleTags({
    #{entries},
    })
    """
  end

  # styleTags selectors are space-separated names, with `/` for parent paths; names
  # with other characters are written in double quotes.
  defp lezer_selector_name(name) do
    if Regex.match?(~r/^[A-Za-z_$][A-Za-z0-9_]*$/, name), do: name, else: JSON.encode!(name)
  end

  defp lezer_tag(tag) do
    Regex.replace(~r/[A-Za-z]+/, tag, fn word -> "t." <> word end)
  end
end
