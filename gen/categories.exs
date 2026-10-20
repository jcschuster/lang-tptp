# The highlight table: one mapping from BNF symbols to categories, from which
# `LangTptp.Highlights` renders `highlights.scm` (tree-sitter), `highlight.ts`
# (Lezer styleTags) and the token classes of `monarch.ts`.
#
# `targets` names each category per target:
#
#   * tree_sitter — a capture name. Uses the names Neovim and Zed share
#     (`keyword`, `function.builtin`, `punctuation.bracket`, …); `keyword.modifier`
#     is Neovim's name, which Zed falls back from to `keyword`.
#   * lezer — a tag from `@lezer/highlight`, written without the `t.` prefix.
#   * monarch — a Monaco token class.
#
# `nodes` maps a visible nonterminal or token to a category. `"parent > child"`
# applies only to a child directly under that parent, and is listed before the
# plain rule for the child so that it wins (tree-sitter uses the first matching
# pattern; Lezer prefers the deeper selector).
#
# `literals` maps every literal spelling the grammar uses to a category. Generation
# fails if the BNF gains a spelling that is not listed here, or if a name listed
# here is not a visible node of the generated grammars.

%{
  targets: %{
    keyword: %{tree_sitter: "keyword", lezer: "keyword", monarch: "keyword"},
    role: %{tree_sitter: "keyword.modifier", lezer: "modifier", monarch: "type"},
    label: %{tree_sitter: "label", lezer: "labelName", monarch: "tag"},
    variable: %{tree_sitter: "variable", lezer: "variableName", monarch: "variable"},
    function: %{tree_sitter: "function", lezer: "function(variableName)", monarch: "identifier"},
    constant: %{tree_sitter: "constant", lezer: "constant(variableName)", monarch: "identifier"},
    type: %{tree_sitter: "type", lezer: "typeName", monarch: "type.identifier"},
    builtin: %{tree_sitter: "function.builtin", lezer: "standard(variableName)", monarch: "predefined"},
    builtin_type: %{tree_sitter: "type.builtin", lezer: "standard(typeName)", monarch: "predefined"},
    system: %{tree_sitter: "function.macro", lezer: "special(variableName)", monarch: "annotation"},
    string: %{tree_sitter: "string", lezer: "string", monarch: "string"},
    path: %{tree_sitter: "string.special.path", lezer: "special(string)", monarch: "string"},
    number: %{tree_sitter: "number", lezer: "number", monarch: "number"},
    operator: %{tree_sitter: "operator", lezer: "logicOperator", monarch: "operator"},
    bracket: %{tree_sitter: "punctuation.bracket", lezer: "bracket", monarch: "delimiter.bracket"},
    delimiter: %{tree_sitter: "punctuation.delimiter", lezer: "separator", monarch: "delimiter"},
    comment: %{tree_sitter: "comment", lezer: "comment", monarch: "comment"}
  },
  nodes: [
    {"formula_role", :role},
    {"intro_type", :role},
    {"name", :label},
    {"variable", :variable},
    {"constant > functor", :constant},
    {"type_constant > type_functor", :type},
    {"type_functor", :type},
    {"functor", :function},
    {"inference_rule", :function},
    {"defined_constant > defined_functor", :builtin},
    {"defined_functor", :builtin},
    {"defined_type", :builtin_type},
    {"system_constant > system_functor", :system},
    {"system_functor", :system},
    {"system_type", :system},
    {"file_name", :path},
    {"distinct_object", :string},
    {"integer", :number},
    {"rational", :number},
    {"real", :number},
    {"comment", :comment}
  ],
  literals: %{
    keyword: ~w(thf tff tcf fof cnf tpi include inference introduced file
                $thf $tff $fof $cnf $fot $let),
    operator: ~w"! ? ^ @ ~ & | = != == => <= <=> <~> ~| ~& --> := > * + << # !! ?? @+ @- @= @@+ @@- !> ?* <.> [.] {.} (.)",
    bracket: ~w|( ) [ ] { }|,
    delimiter: ~w(, . : -)
  }
}
