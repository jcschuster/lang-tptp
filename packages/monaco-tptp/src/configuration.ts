import type {languages} from "monaco-editor"

/// Editor behaviour for TPTP: comments, brackets, auto-closing and what counts as a
/// word (so `$sum` and `$$skolem` are selected whole).
export const configuration: languages.LanguageConfiguration = {
  comments: {
    lineComment: "%",
    blockComment: ["/*", "*/"],
  },
  brackets: [
    ["(", ")"],
    ["[", "]"],
    ["{", "}"],
  ],
  autoClosingPairs: [
    {open: "(", close: ")"},
    {open: "[", close: "]"},
    {open: "{", close: "}"},
    {open: "'", close: "'", notIn: ["string", "comment"]},
    {open: '"', close: '"', notIn: ["string", "comment"]},
    {open: "/*", close: " */", notIn: ["string"]},
  ],
  surroundingPairs: [
    {open: "(", close: ")"},
    {open: "[", close: "]"},
    {open: "{", close: "}"},
    {open: "'", close: "'"},
    {open: '"', close: '"'},
  ],
  wordPattern: /\$\$?[A-Za-z0-9_]*|[A-Za-z][A-Za-z0-9_]*|[+-]?[0-9][0-9./Ee+-]*/,
}
