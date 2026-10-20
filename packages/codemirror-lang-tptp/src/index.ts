import {parser} from "./tptp.grammar"
import {
  LRLanguage,
  LanguageSupport,
  indentNodeProp,
  foldNodeProp,
  foldInside,
  continuedIndent,
} from "@codemirror/language"

/// The node names of the six annotated-formula statements and `include`, as the
/// generated grammar names them.
const statements =
  "ThfAnnotated TffAnnotated TcfAnnotated FofAnnotated CnfAnnotated TpiAnnotated Include"

/// The TPTP language, with highlighting (from the generated `highlight.ts`, attached
/// by the grammar), folding of whole statements and indentation of continued lines.
export const tptpLanguage = LRLanguage.define({
  name: "tptp",
  parser: parser.configure({
    props: [
      indentNodeProp.add({
        [statements]: continuedIndent(),
      }),
      foldNodeProp.add({
        [statements]: foldInside,
        Comment: (node, state) =>
          state.doc.sliceString(node.from, node.from + 2) == "/*" ? {from: node.from + 2, to: node.to - 2} : null,
      }),
    ],
  }),
  languageData: {
    commentTokens: {line: "%", block: {open: "/*", close: "*/"}},
    closeBrackets: {brackets: ["(", "[", "{", "'", '"']},
    wordChars: "$",
  },
})

/// TPTP language support for CodeMirror.
export function tptp() {
  return new LanguageSupport(tptpLanguage)
}
