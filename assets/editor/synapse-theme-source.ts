import type * as monaco from "monaco-editor";

/**
 * VS Dark syntax token colours (hex without #) — stable copy used for all
 * shell-matched editor themes. Only editor *backgrounds* are swapped per preset.
 */
const VS_DARK_RULES: monaco.editor.ITokenThemeRule[] = [
  { token: "", foreground: "D4D4D4", background: "1e1e1e" },
  { token: "comment", foreground: "6A9955", fontStyle: "italic" },
  { token: "keyword", foreground: "569CD6" },
  { token: "keyword.control", foreground: "C586C0" },
  { token: "string", foreground: "CE9178" },
  { token: "string.escape", foreground: "D7BA7D" },
  { token: "number", foreground: "B5CEA8" },
  { token: "regexp", foreground: "D16969" },
  { token: "operator", foreground: "D4D4D4" },
  { token: "namespace", foreground: "4EC9B0" },
  { token: "type", foreground: "4EC9B0" },
  { token: "struct", foreground: "4EC9B0" },
  { token: "class", foreground: "4EC9B0" },
  { token: "interface", foreground: "4EC9B0" },
  { token: "enum", foreground: "4EC9B0" },
  { token: "type.parameter", foreground: "4EC9B0" },
  { token: "function", foreground: "DCDCAA" },
  { token: "method", foreground: "DCDCAA" },
  { token: "variable", foreground: "9CDCFE" },
  { token: "variable.predefined", foreground: "4FC1FF" },
  { token: "constant", foreground: "4FC1FF" },
  { token: "tag", foreground: "569CD6" },
  { token: "attribute.name", foreground: "9CDCFE" },
  { token: "attribute.value", foreground: "CE9178" },
];

function stripHash(hex: string): string {
  return hex.replace("#", "").toLowerCase();
}

function hexToRgb(hex: string): [number, number, number] {
  const h = stripHash(hex);
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

function rgbToHex(r: number, g: number, b: number): string {
  const c = (n: number) => Math.min(255, Math.max(0, Math.round(n)));
  return `#${[c(r), c(g), c(b)].map((x) => x.toString(16).padStart(2, "0")).join("")}`;
}

/** Slightly lighter than bg for the active line highlight. */
export function shellThemeLineHighlightBg(backgroundHex: string): string {
  const [r, g, b] = hexToRgb(backgroundHex);
  return rgbToHex(r + 18, g + 18, b + 18);
}

/** Dark, low-contrast selection tints matched to the editor canvas (not VS blue). */
export function shellThemeSubtleSelectionColors(backgroundHex: string): Record<string, string> {
  const [r, g, b] = hexToRgb(backgroundHex);
  const selection = rgbToHex(r + 22, g + 22, b + 22);
  const inactive = rgbToHex(r + 14, g + 14, b + 14);
  const occurrence = rgbToHex(r + 30, g + 30, b + 30);
  const strip = (h: string) => h.replace("#", "");
  return {
    "editor.selectionBackground": selection,
    "editor.inactiveSelectionBackground": inactive,
    "editor.selectionHighlightBackground": `#${strip(occurrence)}55`,
    "editor.hoverHighlightBackground": "#ffffff14",
    "editor.wordHighlightBackground": "#57575780",
    "editor.wordHighlightStrongBackground": "#6a6a6a80",
  };
}

/**
 * Build a Monaco theme that is VS Dark for syntax/foreground but uses `backgroundHex`
 * for every editor surface (not the HTML wrapper behind the widget).
 */
export function buildVsDarkShellMonacoTheme(backgroundHex: string): monaco.editor.IStandaloneThemeData {
  const bg = stripHash(backgroundHex);
  const hex = `#${bg}`;
  const lineHi = shellThemeLineHighlightBg(hex);
  const rules = VS_DARK_RULES.map((rule, i) =>
    i === 0 ? { ...rule, background: bg } : { ...rule },
  );

  return {
    base: "vs-dark",
    inherit: false,
    rules,
    colors: {
      "editor.background": hex,
      "editor.foreground": "#D4D4D4",
      "editor.lineHighlightBackground": lineHi,
      "editor.selectionBackground": "#264F78",
      "editor.inactiveSelectionBackground": "#3A3D41",
      "editor.selectionHighlightBackground": "#ADD6FF26",
      "editor.findMatchBackground": "#515C6A",
      "editor.findMatchHighlightBackground": "#EA5C0055",
      "editor.hoverHighlightBackground": "#264F7833",
      "editor.wordHighlightBackground": "#575757B8",
      "editor.wordHighlightStrongBackground": "#004972B8",
      "editorCursor.foreground": "#AEAFAD",
      "editorWhitespace.foreground": "#404040",
      "editorLineNumber.foreground": "#858585",
      "editorLineNumber.activeForeground": "#C6C6C6",
      "editorIndentGuide.background": "#404040",
      "editorIndentGuide.activeBackground": "#707070",
      "editorGutter.background": hex,
      "editorPane.background": hex,
      "minimap.background": hex,
      "scrollbar.shadow": "#00000000",
      "scrollbarSlider.background": "#79797966",
      "scrollbarSlider.hoverBackground": "#646464B3",
      "scrollbarSlider.activeBackground": "#BFBFBF66",
    },
  };
}
