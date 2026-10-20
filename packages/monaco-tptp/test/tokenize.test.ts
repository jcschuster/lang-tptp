import {readdirSync, readFileSync} from "node:fs"
import {join} from "node:path"
import {beforeAll, describe, expect, it} from "vitest"
import * as monaco from "monaco-editor/editor/editor.api.js"
import {languageId, register} from "../src/index.js"

const fixtures = join(import.meta.dirname, "..", "..", "..", "fixtures")

type Token = {text: string; type: string}

function tokenize(source: string): Token[][] {
  const lines = source.split("\n")
  return monaco.editor.tokenize(source, languageId).map((tokens, row) =>
    tokens.map((token, i) => ({
      text: lines[row].slice(token.offset, tokens[i + 1]?.offset ?? lines[row].length),
      type: token.type,
    })),
  )
}

beforeAll(() => register(monaco))

describe("fixtures", () => {
  for (const file of readdirSync(fixtures).sort()) {
    it(`${file} has no invalid tokens`, () => {
      const lines = tokenize(readFileSync(join(fixtures, file), "utf8"))
      const invalid = lines.flatMap((tokens, row) =>
        tokens.filter((t) => t.type.startsWith("invalid")).map((t) => `${row + 1}: ${JSON.stringify(t.text)}`),
      )
      expect(invalid).toEqual([])
    })

    it(`${file} token stream`, () => {
      const lines = tokenize(readFileSync(join(fixtures, file), "utf8"))
      const stream = lines
        .map((tokens) => tokens.filter((t) => t.type != "white.tptp").map((t) => `${t.type} ${t.text}`).join("\n"))
        .join("\n")
      expect(stream).toMatchSnapshot()
    })
  }
})

describe("classes", () => {
  const types = (source: string) =>
    Object.fromEntries(tokenize(source)[0].filter((t) => t.type != "white.tptp").map((t) => [t.text, t.type]))

  it("separates statement keyword, name and role", () => {
    const tokens = tokenize("fof(fof, axiom, fof).")[0].filter((t) => t.type != "white.tptp")
    expect(tokens.map((t) => t.type)).toEqual([
      "keyword.tptp",
      "delimiter.bracket.tptp",
      "tag.tptp",
      "delimiter.tptp",
      "type.tptp",
      "delimiter.tptp",
      "identifier.tptp",
      "delimiter.bracket.tptp",
      "delimiter.tptp",
    ])
  })

  it("classifies words inside formulas", () => {
    expect(types("tff(a, axiom, ! [X: $int] : $less(X, $$sk(1.5, -3/4))).")).toMatchObject({
      "!": "operator.tptp",
      X: "variable.tptp",
      $int: "predefined.tptp",
      $less: "predefined.tptp",
      $$sk: "annotation.tptp",
      "1.5": "number.tptp",
      "-3/4": "number.tptp",
    })
  })

  it("treats a block comment spanning lines as comment", () => {
    const lines = tokenize("/* one\ntwo */ fof(a, axiom, p).")
    expect(lines[0].every((t) => t.type == "comment.tptp")).toBe(true)
    expect(lines[1][0]).toEqual({text: "two */", type: "comment.tptp"})
  })
})
