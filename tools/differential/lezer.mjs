// Prints every file (one path per line in argv[2]) that the Lezer parser rejects.
// Needs the built package: `pnpm --filter codemirror-lang-tptp run build`.
//
// In strict mode the parser throws a SyntaxError where it would otherwise insert an
// error node and recover, so a file is rejected exactly when its tree would contain
// an error node, without walking the tree.
import {readFileSync} from "node:fs"
import {tptpLanguage} from "../../packages/codemirror-lang-tptp/dist/index.js"

const parser = tptpLanguage.parser.configure({strict: true})
const paths = readFileSync(process.argv[2], "utf8").split("\n").filter(Boolean)

for (const path of paths) {
  try {
    parser.parse(readFileSync(path, "utf8"))
  } catch (error) {
    if (!(error instanceof SyntaxError)) throw error
    console.log(path)
  }
}
