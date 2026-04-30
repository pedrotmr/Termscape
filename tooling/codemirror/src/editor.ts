import { autocompletion, closeBrackets, closeBracketsKeymap, completionKeymap } from "@codemirror/autocomplete";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
  insertTab,
  isolateHistory,
} from "@codemirror/commands";
import { cpp } from "@codemirror/lang-cpp";
import { css } from "@codemirror/lang-css";
import { go } from "@codemirror/lang-go";
import { html } from "@codemirror/lang-html";
import { java } from "@codemirror/lang-java";
import { javascript } from "@codemirror/lang-javascript";
import { json } from "@codemirror/lang-json";
import { markdown } from "@codemirror/lang-markdown";
import { php } from "@codemirror/lang-php";
import { python } from "@codemirror/lang-python";
import { rust } from "@codemirror/lang-rust";
import { sql } from "@codemirror/lang-sql";
import { wast } from "@codemirror/lang-wast";
import { xml } from "@codemirror/lang-xml";
import {
  bracketMatching,
  foldGutter,
  foldKeymap,
  forceParsing,
  HighlightStyle,
  indentOnInput,
  indentUnit,
  Language,
  StreamLanguage,
  syntaxHighlighting,
} from "@codemirror/language";
import { dockerFile } from "@codemirror/legacy-modes/mode/dockerfile";
import { properties } from "@codemirror/legacy-modes/mode/properties";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { swift } from "@codemirror/legacy-modes/mode/swift";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import { yaml } from "@codemirror/legacy-modes/mode/yaml";
import {
  highlightSelectionMatches,
  search,
  searchKeymap,
} from "@codemirror/search";
import { Compartment, EditorSelection, EditorState, Extension, RangeSetBuilder } from "@codemirror/state";
import {
  crosshairCursor,
  Decoration,
  DecorationSet,
  drawSelection,
  dropCursor,
  EditorView,
  highlightActiveLine,
  highlightActiveLineGutter,
  highlightSpecialChars,
  keymap,
  lineNumbers,
  rectangularSelection,
  ViewPlugin,
  ViewUpdate,
} from "@codemirror/view";
import { tags } from "@lezer/highlight";

type SwiftMessage = {
  type: string;
  documentId?: string;
  text?: string;
  revision?: number;
  reason?: string;
};

type DocumentPayload = {
  id: string;
  path: string;
  text: string;
  editable?: boolean;
};

type ThemePayload = {
  background: string;
  foreground: string;
  muted: string;
  accent: string;
  border: string;
  chrome: string;
  hover: string;
  selection: string;
  activeLine: string;
  bracket: string;
  isDark: boolean;
};

declare global {
  interface Window {
    termscapeEditor: {
      setDocument(payload: DocumentPayload): void;
      setTheme(payload: ThemePayload): void;
      setEditable(editable: boolean): void;
      setLanguage(path: string): void;
      focusEditor(): void;
      flushText(reason?: string): string;
      getText(): string;
    };
    webkit?: {
      messageHandlers?: {
        termscapeEditor?: {
          postMessage(message: SwiftMessage): void;
        };
      };
    };
  }
}

const languageCompartment = new Compartment();
const editableCompartment = new Compartment();

let view: EditorView;
let currentDocumentId: string | null = null;
let revision = 0;
let suppressChangeNotification = false;
let pendingChangeTimer: number | null = null;

function post(message: SwiftMessage) {
  window.webkit?.messageHandlers?.termscapeEditor?.postMessage(message);
}

function flushText(reason = "explicit"): string {
  if (pendingChangeTimer !== null) {
    window.clearTimeout(pendingChangeTimer);
    pendingChangeTimer = null;
  }
  const text = view.state.doc.toString();
  if (currentDocumentId !== null) {
    post({ type: "documentChanged", documentId: currentDocumentId, text, revision, reason });
  }
  return text;
}

function scheduleChangeNotification() {
  if (pendingChangeTimer !== null) {
    window.clearTimeout(pendingChangeTimer);
  }
  pendingChangeTimer = window.setTimeout(() => {
    pendingChangeTimer = null;
    flushText("debounced");
  }, 180);
}

function languageForPath(path: string): Extension {
  const filename = path.split(/[\\/]/).pop()?.toLowerCase() ?? "";
  const ext = filename.includes(".") ? filename.split(".").pop() ?? "" : "";

  if (filename === "dockerfile" || filename.endsWith(".dockerfile")) {
    return StreamLanguage.define(dockerFile);
  }
  if (filename === "makefile") return StreamLanguage.define(shell);
  if (filename === "package.json" || filename === "tsconfig.json" || filename.endsWith(".json")) return json();
  if (filename.endsWith(".html") || filename.endsWith(".htm")) return html();
  if (filename.endsWith(".css")) return css();
  if (filename.endsWith(".scss") || filename.endsWith(".sass") || filename.endsWith(".less")) return css();
  if (filename.endsWith(".md") || filename.endsWith(".markdown")) return markdown({
    codeLanguages: markdownCodeLanguage,
  });
  if (filename.endsWith(".toml")) return StreamLanguage.define(toml);
  if (filename.endsWith(".yaml") || filename.endsWith(".yml")) return StreamLanguage.define(yaml);
  if (filename.endsWith(".xml") || filename.endsWith(".plist") || filename.endsWith(".xib") || filename.endsWith(".storyboard")) return xml();
  if (filename.endsWith(".properties") || filename.endsWith(".env")) return StreamLanguage.define(properties);

  switch (ext) {
    case "js":
    case "mjs":
    case "cjs":
      return javascript({ jsx: false, typescript: false });
    case "jsx":
      return javascript({ jsx: true, typescript: false });
    case "ts":
    case "mts":
    case "cts":
      return javascript({ jsx: false, typescript: true });
    case "tsx":
      return javascript({ jsx: true, typescript: true });
    case "py":
    case "pyw":
      return python();
    case "swift":
      return StreamLanguage.define(swift);
    case "rs":
      return rust();
    case "go":
      return go();
    case "java":
      return java();
    case "c":
    case "h":
    case "cc":
    case "cpp":
    case "cxx":
    case "hpp":
    case "hh":
    case "m":
    case "mm":
      return cpp();
    case "php":
      return php();
    case "sql":
      return sql();
    case "wat":
    case "wast":
      return wast();
    case "sh":
    case "bash":
    case "zsh":
    case "fish":
      return StreamLanguage.define(shell);
    default:
      return [];
  }
}

function markdownCodeLanguage(info: string): Language | null {
  const name = info.trim().toLowerCase().split(/\s+/)[0] ?? "";
  switch (name) {
    case "js":
    case "javascript":
    case "mjs":
    case "cjs":
      return javascript({ jsx: false, typescript: false }).language;
    case "jsx":
      return javascript({ jsx: true, typescript: false }).language;
    case "ts":
    case "typescript":
    case "mts":
    case "cts":
      return javascript({ jsx: false, typescript: true }).language;
    case "tsx":
      return javascript({ jsx: true, typescript: true }).language;
    case "json":
      return json().language;
    case "html":
    case "htm":
      return html().language;
    case "css":
    case "scss":
    case "sass":
    case "less":
      return css().language;
    case "py":
    case "python":
      return python().language;
    case "swift":
      return StreamLanguage.define(swift);
    case "rs":
    case "rust":
      return rust().language;
    case "go":
    case "golang":
      return go().language;
    case "java":
      return java().language;
    case "c":
    case "cpp":
    case "c++":
    case "cc":
    case "cxx":
    case "h":
    case "hpp":
      return cpp().language;
    case "php":
      return php().language;
    case "sql":
      return sql().language;
    case "xml":
      return xml().language;
    case "sh":
    case "shell":
    case "bash":
    case "zsh":
    case "fish":
      return StreamLanguage.define(shell);
    case "yaml":
    case "yml":
      return StreamLanguage.define(yaml);
    case "toml":
      return StreamLanguage.define(toml);
    default:
      return null;
  }
}

function setTheme(payload: ThemePayload) {
  const style = document.documentElement.style;
  style.setProperty("--termscape-bg", payload.background);
  style.setProperty("--termscape-fg", payload.foreground);
  style.setProperty("--termscape-muted", payload.muted);
  style.setProperty("--termscape-accent", payload.accent);
  style.setProperty("--termscape-border", payload.border);
  style.setProperty("--termscape-chrome", payload.chrome);
  style.setProperty("--termscape-hover", payload.hover);
  style.setProperty("--termscape-selection", payload.selection);
  style.setProperty("--termscape-active-line", payload.activeLine);
  style.setProperty("--termscape-bracket", payload.bracket);
  const syntax = payload.isDark ? darkSyntaxPalette : lightSyntaxPalette;
  for (const [key, value] of Object.entries(syntax)) {
    style.setProperty(key, value);
  }
  document.body.dataset.theme = payload.isDark ? "dark" : "light";
}

const darkSyntaxPalette: Record<string, string> = {
  "--syntax-keyword": "#c891ff",
  "--syntax-operator-keyword": "#d9a3ff",
  "--syntax-name": "#e7ded3",
  "--syntax-function": "#8fbaff",
  "--syntax-definition": "#9fc8ff",
  "--syntax-type": "#8fd6b3",
  "--syntax-string": "#d6b06f",
  "--syntax-special-string": "#e0c07a",
  "--syntax-number": "#f0a66a",
  "--syntax-bool": "#f0a66a",
  "--syntax-comment": "#877d70",
  "--syntax-property": "#bcc7d1",
  "--syntax-punctuation": "#a9a097",
  "--syntax-meta": "#a78f78",
  "--syntax-invalid": "#ff6f6f",
};

const lightSyntaxPalette: Record<string, string> = {
  "--syntax-keyword": "#7c3aed",
  "--syntax-operator-keyword": "#8b4fd9",
  "--syntax-name": "#26221d",
  "--syntax-function": "#0b62b7",
  "--syntax-definition": "#075aa5",
  "--syntax-type": "#28704f",
  "--syntax-string": "#8a5b00",
  "--syntax-special-string": "#9a6500",
  "--syntax-number": "#a34f00",
  "--syntax-bool": "#a34f00",
  "--syntax-comment": "#776f64",
  "--syntax-property": "#34556c",
  "--syntax-punctuation": "#5f5850",
  "--syntax-meta": "#7c6753",
  "--syntax-invalid": "#ba1a1a",
};

const termscapeHighlightStyle = HighlightStyle.define([
  { tag: tags.heading1, color: "var(--syntax-keyword)", fontWeight: "700" },
  { tag: tags.heading2, color: "var(--syntax-keyword)", fontWeight: "650" },
  { tag: [tags.heading3, tags.heading4, tags.heading5, tags.heading6], color: "var(--syntax-keyword)", fontWeight: "600" },
  { tag: tags.heading, color: "var(--syntax-keyword)", fontWeight: "600" },
  { tag: tags.strong, color: "var(--syntax-definition)", fontWeight: "700" },
  { tag: tags.emphasis, color: "var(--syntax-meta)", fontStyle: "italic" },
  { tag: tags.link, color: "var(--syntax-function)", textDecoration: "underline" },
  { tag: tags.url, color: "var(--syntax-special-string)" },
  { tag: tags.monospace, color: "var(--syntax-string)" },
  { tag: tags.quote, color: "var(--syntax-comment)", fontStyle: "italic" },
  { tag: tags.list, color: "var(--syntax-number)" },
  { tag: tags.contentSeparator, color: "var(--syntax-punctuation)" },
  { tag: tags.keyword, color: "var(--syntax-keyword)", fontWeight: "500" },
  { tag: [tags.operatorKeyword, tags.modifier], color: "var(--syntax-operator-keyword)" },
  { tag: [tags.name, tags.variableName], color: "var(--syntax-name)" },
  { tag: [tags.function(tags.variableName), tags.function(tags.propertyName)], color: "var(--syntax-function)" },
  { tag: [tags.definition(tags.name), tags.className], color: "var(--syntax-definition)" },
  { tag: [tags.typeName, tags.standard(tags.typeName)], color: "var(--syntax-type)" },
  { tag: [tags.string, tags.character], color: "var(--syntax-string)" },
  { tag: [tags.special(tags.string), tags.regexp], color: "var(--syntax-special-string)" },
  { tag: tags.number, color: "var(--syntax-number)" },
  { tag: [tags.bool, tags.null], color: "var(--syntax-bool)" },
  { tag: [tags.lineComment, tags.blockComment], color: "var(--syntax-comment)", fontStyle: "italic" },
  { tag: [tags.propertyName, tags.attributeName], color: "var(--syntax-property)" },
  { tag: [tags.punctuation, tags.brace, tags.squareBracket, tags.paren], color: "var(--syntax-punctuation)" },
  { tag: [tags.meta, tags.processingInstruction], color: "var(--syntax-meta)" },
  { tag: tags.invalid, color: "var(--syntax-invalid)" },
]);

const bracketPairs = new Map<string, string>([
  ["(", ")"],
  ["[", "]"],
  ["{", "}"],
]);
const closingBrackets = new Set(Array.from(bracketPairs.values()));

function bracketPairDecorations(state: EditorState): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const viewportFrom = view?.viewport.from ?? 0;
  const viewportTo = view?.viewport.to ?? state.doc.length;
  const prefix = state.doc.sliceString(0, viewportFrom);
  let depth = 0;
  for (const char of prefix) {
    if (bracketPairs.has(char)) {
      depth += 1;
    } else if (closingBrackets.has(char)) {
      depth = Math.max(0, depth - 1);
    }
  }

  const text = state.doc.sliceString(viewportFrom, viewportTo);
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const pos = viewportFrom + index;
    if (bracketPairs.has(char)) {
      const className = `cm-bracket-pair-${(depth % 6) + 1}`;
      builder.add(pos, pos + 1, Decoration.mark({ class: className }));
      depth += 1;
    } else if (closingBrackets.has(char)) {
      const className = `cm-bracket-pair-${(Math.max(0, depth - 1) % 6) + 1}`;
      builder.add(pos, pos + 1, Decoration.mark({ class: className }));
      depth = Math.max(0, depth - 1);
    }
  }
  return builder.finish();
}

const bracketPairColorizer = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(editorView: EditorView) {
      view = editorView;
      this.decorations = bracketPairDecorations(editorView.state);
    }

    update(update: ViewUpdate) {
      view = update.view;
      if (update.docChanged || update.viewportChanged) {
        this.decorations = bracketPairDecorations(update.state);
      }
    }
  },
  {
    decorations: plugin => plugin.decorations,
  }
);

function parseVisibleViewportSoon(editorView: EditorView) {
  requestAnimationFrame(() => {
    forceParsing(editorView, editorView.viewport.to, 80);
  });
}

const eagerSyntaxParser = ViewPlugin.fromClass(
  class {
    constructor(editorView: EditorView) {
      parseVisibleViewportSoon(editorView);
    }

    update(update: ViewUpdate) {
      if (update.docChanged || update.viewportChanged) {
        parseVisibleViewportSoon(update.view);
      }
    }
  }
);

const termscapeTheme = EditorView.theme({
  "&": {
    backgroundColor: "var(--termscape-bg)",
    color: "var(--termscape-fg)",
  },
  ".cm-scroller": {
    backgroundColor: "var(--termscape-bg)",
  },
  ".cm-content": {
    color: "var(--termscape-fg)",
    fontVariantLigatures: "none",
  },
  ".cm-cursor": {
    borderLeftColor: "var(--termscape-accent)",
  },
  ".cm-line": { color: "var(--termscape-fg)" },
  ".cm-gutters": {
    backgroundColor: "var(--termscape-bg)",
    color: "color-mix(in srgb, var(--termscape-muted) 58%, transparent)",
    borderRight: "1px solid color-mix(in srgb, var(--termscape-border) 70%, transparent)",
  },
  ".cm-gutter": {
    backgroundColor: "var(--termscape-bg)",
  },
  ".cm-gutterElement": {
    backgroundColor: "transparent",
    color: "color-mix(in srgb, var(--termscape-muted) 58%, transparent)",
  },
  ".cm-lineNumbers .cm-gutterElement": {
    minWidth: "34px",
    padding: "0 10px 0 6px",
  },
  ".cm-foldGutter .cm-gutterElement": {
    color: "color-mix(in srgb, var(--termscape-muted) 46%, transparent)",
    padding: "0 5px",
  },
  ".cm-activeLine": {
    backgroundColor: "var(--termscape-active-line)",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "var(--termscape-active-line)",
    color: "var(--termscape-fg)",
  },
  ".cm-selectionMatch": {
    backgroundColor: "color-mix(in srgb, var(--termscape-accent) 22%, transparent)",
  },
  ".cm-searchMatch": {
    backgroundColor: "color-mix(in srgb, var(--termscape-accent) 34%, transparent)",
    outline: "1px solid color-mix(in srgb, var(--termscape-accent) 45%, transparent)",
  },
  ".cm-matchingBracket, .cm-nonmatchingBracket": {
    backgroundColor: "var(--termscape-bracket)",
    outline: "none",
  },
});

function setEditable(editable: boolean) {
  view.dispatch({
    effects: editableCompartment.reconfigure([
      EditorView.editable.of(editable),
      EditorState.readOnly.of(!editable),
    ]),
  });
}

function setDocument(payload: DocumentPayload) {
  if (pendingChangeTimer !== null) {
    flushText("preSetDocument");
  }
  const incomingText = payload.text ?? "";
  const sameDocument = currentDocumentId === payload.id;
  const prevText = view.state.doc.toString();
  if (sameDocument && incomingText === prevText) {
    view.dispatch({
      effects: [
        languageCompartment.reconfigure(languageForPath(payload.path)),
        editableCompartment.reconfigure([
          EditorView.editable.of(payload.editable !== false),
          EditorState.readOnly.of(payload.editable === false),
        ]),
      ],
    });
    return;
  }
  const selection =
    sameDocument && incomingText !== prevText
      ? EditorSelection.single(
          Math.min(view.state.selection.main.anchor, incomingText.length),
          Math.min(view.state.selection.main.head, incomingText.length)
        )
      : EditorSelection.cursor(0);
  currentDocumentId = payload.id;
  revision = 0;
  suppressChangeNotification = true;
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: incomingText },
    selection,
    annotations: isolateHistory.of("full"),
    effects: [
      languageCompartment.reconfigure(languageForPath(payload.path)),
      editableCompartment.reconfigure([
        EditorView.editable.of(payload.editable !== false),
        EditorState.readOnly.of(payload.editable === false),
      ]),
    ],
  });
  suppressChangeNotification = false;
  view.focus();
}

function setLanguage(path: string) {
  view.dispatch({ effects: languageCompartment.reconfigure(languageForPath(path)) });
}

function buildExtensions(): Extension[] {
  return [
    highlightSpecialChars(),
    history(),
    drawSelection(),
    dropCursor(),
    EditorState.allowMultipleSelections.of(true),
    indentOnInput(),
    eagerSyntaxParser,
    bracketMatching(),
    bracketPairColorizer,
    closeBrackets(),
    autocompletion(),
    rectangularSelection(),
    crosshairCursor(),
    highlightActiveLine(),
    highlightActiveLineGutter(),
    highlightSelectionMatches(),
    search({ top: true }),
    lineNumbers(),
    foldGutter(),
    EditorView.lineWrapping,
    indentUnit.of("    "),
    syntaxHighlighting(termscapeHighlightStyle, { fallback: true }),
    termscapeTheme,
    languageCompartment.of([]),
    editableCompartment.of([EditorView.editable.of(true), EditorState.readOnly.of(false)]),
    EditorView.updateListener.of((update) => {
      if (!update.docChanged || suppressChangeNotification) return;
      revision += 1;
      scheduleChangeNotification();
    }),
    EditorView.domEventHandlers({
      focus: () => {
        post({ type: "focused" });
        return false;
      },
    }),
    keymap.of([
      {
        key: "Mod-s",
        run: () => {
          const text = flushText("save");
          if (currentDocumentId !== null) {
            post({ type: "saveRequested", documentId: currentDocumentId, text, revision, reason: "keyboard" });
          }
          return true;
        },
        preventDefault: true,
      },
      indentWithTab,
      { key: "Tab", run: insertTab },
      ...closeBracketsKeymap,
      ...searchKeymap,
      ...historyKeymap,
      ...foldKeymap,
      ...completionKeymap,
      ...defaultKeymap,
    ]),
  ];
}

function start() {
  const parent = document.getElementById("editor");
  if (!parent) throw new Error("Missing #editor mount node");
  view = new EditorView({
    state: EditorState.create({ doc: "", extensions: buildExtensions() }),
    parent,
  });

  window.termscapeEditor = {
    setDocument,
    setTheme,
    setEditable,
    setLanguage,
    focusEditor: () => view.focus(),
    flushText,
    getText: () => view.state.doc.toString(),
  };

  post({ type: "ready" });
}

start();
