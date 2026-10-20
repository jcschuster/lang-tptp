import {tptpLanguage} from "../dist/index.js"
import {highlightTree, tagHighlighter, tags as t} from "@lezer/highlight"
import assert from "assert"
import * as fs from "fs"
import * as path from "path"
import {fileURLToPath} from "url"

const fixtures = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "fixtures")

describe("fixtures", () => {
  for (const file of fs.readdirSync(fixtures).sort()) {
    it(`${file} parses without error nodes`, () => {
      const text = fs.readFileSync(path.join(fixtures, file), "utf8")
      const errors = []
      tptpLanguage.parser.parse(text).iterate({
        enter: node => { if (node.type.isError) errors.push(JSON.stringify(text.slice(node.from, node.from + 30))) },
      })
      assert.deepStrictEqual(errors, [])
    })
  }
})

describe("highlighting", () => {
  // One class per tag the highlight table uses, so modified tags stay distinct.
  const highlighter = tagHighlighter([
    {tag: t.keyword, class: "keyword"},
    {tag: t.modifier, class: "role"},
    {tag: t.labelName, class: "label"},
    {tag: t.variableName, class: "variable"},
    {tag: t.function(t.variableName), class: "function"},
    {tag: t.constant(t.variableName), class: "constant"},
    {tag: t.standard(t.variableName), class: "builtin"},
    {tag: t.standard(t.typeName), class: "builtin-type"},
    {tag: t.special(t.variableName), class: "system"},
    {tag: t.string, class: "string"},
    {tag: t.special(t.string), class: "path"},
    {tag: t.number, class: "number"},
    {tag: t.logicOperator, class: "operator"},
    {tag: t.comment, class: "comment"},
  ])

  // Map each highlighted piece of text to its class.
  function classes(text) {
    const result = {}
    highlightTree(tptpLanguage.parser.parse(text), highlighter, (from, to, cls) => {
      result[text.slice(from, to)] = cls
    })
    return result
  }

  it("separates keyword, name, role, variable, function, builtin, number, constant", () => {
    assert.deepStrictEqual(
      pick(classes("fof(ax1, axiom, ! [X] : p(X, $sum(1, c)))."), ["fof", "ax1", "axiom", "!", "X", "p", "$sum", "1", "c"]),
      {fof: "keyword", ax1: "label", axiom: "role", "!": "operator", X: "variable", p: "function",
       $sum: "builtin", 1: "number", c: "constant"},
    )
  })

  it("highlights types, system words, comments, strings and paths", () => {
    const c = classes("% note\ninclude('a.ax').\ntff(t, type, f: $int > $o).\nfof(d, axiom, $$sk(\"obj\")).")
    assert.deepStrictEqual(pick(c, ["% note", "'a.ax'", "$int", "$$sk", '"obj"']), {
      "% note": "comment", "'a.ax'": "path", $int: "builtin-type", $$sk: "system", '"obj"': "string",
    })
  })
})

function pick(object, keys) {
  return Object.fromEntries(keys.map(key => [key, object[key]]))
}
