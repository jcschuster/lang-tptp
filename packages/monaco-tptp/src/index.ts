import type * as Monaco from "monaco-editor"
import {configuration} from "./configuration.js"
import {tptpMonarch} from "./monarch.js"

export {configuration, tptpMonarch}

/// The Monaco language id.
export const languageId = "tptp"

/// File extensions: problems (`.p`), axiom sets (`.ax`) and solutions (`.s`).
export const extensions = [".p", ".ax", ".s"]

/// Register the TPTP language, its tokenizer and its configuration with Monaco.
/// Safe to call more than once.
export function register(monaco: typeof Monaco): void {
  if (!monaco.languages.getLanguages().some((language) => language.id === languageId)) {
    monaco.languages.register({id: languageId, extensions, aliases: ["TPTP", "tptp"]})
  }
  monaco.languages.setMonarchTokensProvider(languageId, tptpMonarch)
  monaco.languages.setLanguageConfiguration(languageId, configuration)
}
