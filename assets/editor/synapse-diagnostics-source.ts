import * as luaparse from "luaparse";
const monaco = { get MarkerSeverity() { return window.monaco.MarkerSeverity; }, get Range() { return window.monaco.Range; } };

/* ─────────────────────────────────────────────────────────────────────────────
 * synapseDiagnostics.ts – Multi‑pass Lua/Luau syntax error detection
 *
 * luaparse only understands standard Lua 5.1 syntax.  Roblox scripts use
 * Luau, which adds type annotations, compound assignments, `continue`,
 * `type` declarations, and if‑expressions.  We pre‑process the source to
 * neutralise these Luau extensions before feeding it to the parser.
 *
 * Detection strategy (two complementary passes):
 *
 *   1. **Full‑parse with line‑blanking recovery** – Parse the entire file.
 *      When an error is caught, blank the offending line and re‑parse.
 *
 *   2. **Per‑statement isolation** – Split the source into statement chunks
 *      and parse each independently to catch errors hidden by context.
 *
 * The union (deduplicated by line number) is returned as Monaco markers.
 * ────────────────────────────────────────────────────────────────────────── */

const MAX_ERRORS = 25;

/**
 * Identifies spans of code that should be ignored by the Luau stripper
 * (comments and strings) to avoid corrupting ASCII art or nested content.
 */
function getIgnoreSpans(code: string) {
  const spans: { start: number; end: number }[] = [];
  let i = 0;
  while (i < code.length) {
    // 1) Comments
    if (code[i] === "-" && code[i + 1] === "-") {
      const start = i;
      i += 2;
      if (code[i] === "[" && code[i + 1] === "[") {
        i += 2;
        while (i < code.length && !(code[i] === "]" && code[i + 1] === "]")) i++;
        i += 2;
      } else {
        while (i < code.length && code[i] !== "\n") i++;
      }
      spans.push({ start, end: Math.min(i, code.length) });
      continue;
    }
    // 2) Strings (single/double/backtick)
    if (code[i] === '"' || code[i] === "'" || code[i] === "`") {
      const start = i;
      const q = code[i];
      i++;
      while (i < code.length && code[i] !== q) {
        if (code[i] === "\\" && i + 1 < code.length) i++;
        i++;
      }
      i++;
      spans.push({ start, end: Math.min(i, code.length) });
      continue;
    }
    // 3) Long strings
    if (code[i] === "[" && code[i + 1] === "[") {
      const start = i;
      i += 2;
      while (i < code.length && !(code[i] === "]" && code[i + 1] === "]")) i++;
      i += 2;
      spans.push({ start, end: Math.min(i, code.length) });
      continue;
    }
    i++;
  }
  return spans;
}

function isInsideSpan(pos: number, spans: { start: number; end: number }[]) {
  for (const s of spans) {
    if (pos >= s.start && pos < s.end) return true;
  }
  return false;
}

/**
 * Transform Luau‑specific syntax into valid Lua 5.1 while respecting
 * comments and strings.
 */
function stripLuauSyntax(code: string): string {
  const spans = getIgnoreSpans(code);
  const lines = code.split("\n");
  const result: string[] = [];
  let currentOffset = 0;

  for (const line of lines) {
    let l = line;
    const lineStart = currentOffset;

    // 1) Replace backtick string interpolation with regular strings so luaparse doesn't choke
    // We do this line-by-line first, but ideally we'd handle multi-line.
    l = l.replace(/`([^`\\]|\\.)*`/g, (match) => {
      return '"' + " ".repeat(match.length - 2) + '"';
    });

    // Only apply complex strippers if the line doesn't start inside a multi-line span (comment/string)
    if (!isInsideSpan(lineStart, spans)) {
      // 2) `type Foo = ...` and `export type Foo = ...` declarations → blank the line
      if (/^\s*(?:export\s+)?type\s+\w/.test(l)) {
        result.push(" ".repeat(l.length));
        currentOffset += line.length + 1;
        continue;
      }

      // 3) Standalone `continue` → replace with `break`
      if (/^\s*continue\s*(--.*)?$/.test(l)) {
        l = l.replace(/\bcontinue\b/, "break  ");
      }

      // 4) Compound assignments and Floor division: +=, -=, *=, /=, %=, ^=, ..=, //, //=
      // Also handles replacing `//` with `/` to avoid breaking luaparse.
      l = l.replace(
        /(\b\w+(?:\.\w+|\[\w+\])*)\s*([\+\-\*\/\%\^\.]+|\/\/)?=/,
        (match, ident, op) => {
          if (op && op !== "=") {
            return ident + " =";
          }
          return match;
        }
      );
      // Floor division (without assignment) `//` -> `/ `
      l = l.replace(/\/\//g, "/ ");

      // 5) Remove type annotations: `: Type` and `->` (skinny arrow)
      // This regex distinguishes method calls from type annotations.
      // Method calls are `obj:Method(`, `obj:Method"`, `obj:Method{`
      l = l.replace(/:\s*([A-Za-z_][A-Za-z0-9_]*)\s*([("'{[])|:\s*([A-Za-z_][A-Za-z0-9_?|{}\[\]\.<>,\s]*)/g, (match, methodIdent, methodParen, typeIdent, offset) => {
        if (methodIdent && methodParen) {
          // It's a method call, keep it
          return match;
        }
        // It's a type annotation, strip it
        const charBefore = l[offset - 1];
        if (charBefore && /\w/.test(charBefore)) {
          if (isInsideSpan(lineStart + offset, spans)) return match;
          return " ".repeat(match.length);
        }
        return match;
      });
      // Strip skinny arrows `->` often used in function type signatures
      l = l.replace(/->/g, "  ");

      // 6) Return type annotations:  `): ReturnType`  →  `)`
      l = l.replace(/\)\s*:\s*[A-Za-z_]\w*[?]?\s*$/, ")");

      // 7) Attributes (e.g. `@native`, `@[...]`) 
      // If a line starts with `@` (ignoring whitespace), blank it entirely.
      if (/^\s*@/.test(l)) {
        l = " ".repeat(l.length);
      }

      // 8) If‑expressions:  `local x = if cond then a else b`
      // Simple neutralization: replace `if` with `(` and `else` with `or`? No, just blank the line if it's an assignment.
      if (/=\s*if\s+/.test(l)) {
        l = l.replace(/\bif\b/, "  ").replace(/\bthen\b/, " and ").replace(/\belse\b/, " or  ");
      }

      // 8) Neutralize Luau numeric literals (underscores, binary)
      // 0x123_456 -> 0x123456
      l = l.replace(/\b0x[0-9a-fA-F_]+\b/g, (m) => m.replace(/_/g, ""));
      // 0b101 -> 0
      l = l.replace(/\b0b[01_]+\b/g, "0");
    }

    result.push(l);
    currentOffset += line.length + 1;
  }

  return result.join("\n");
}



/* ── luaparse helpers ──────────────────────────────────────────────────── */

interface LuaParseError {
  line: number;
  column: number;
  index: number;
  message: string;
}

function isLuaParseError(err: unknown): err is LuaParseError {
  return (
    typeof err === "object" &&
    err !== null &&
    typeof (err as any).line === "number" &&
    typeof (err as any).column === "number"
  );
}

function cleanMessage(msg: string | undefined): string {
  if (!msg) return "Syntax error";
  return msg.replace(/^\[\d+:\d+\]\s*/, "");
}

function tryParse(code: string): LuaParseError | null {
  try {
    luaparse.parse(code, {
      comments: true,
      locations: true,
      ranges: true,
      luaVersion: "5.1",
    });
    return null;
  } catch (err: unknown) {
    if (isLuaParseError(err)) return err;
    return null;
  }
}

/* ── Marker construction ───────────────────────────────────────────────── */

function makeMarker(
  err: LuaParseError,
  lines: string[],
): monaco.editor.IMarkerData {
  const lineIdx = err.line - 1;
  const lineText = lineIdx >= 0 && lineIdx < lines.length ? lines[lineIdx] : "";
  const message = cleanMessage(err.message);

  let startCol = err.column + 1;
  let endCol = startCol + 1;

  if (lineText.length > 0) {
    const rest = lineText.slice(err.column);
    const tokenMatch = rest.match(/^(\S+)/);
    if (tokenMatch) {
      endCol = startCol + tokenMatch[1].length;
    }

    if (startCol > lineText.length) {
      const trimmed = lineText.trimEnd();
      const lastToken = trimmed.match(/(\S+)$/);
      if (lastToken) {
        startCol = trimmed.length - lastToken[1].length + 1;
        endCol = trimmed.length + 1;
      } else {
        startCol = 1;
        endCol = lineText.length + 1;
      }
    }
  }

  return {
    startLineNumber: err.line,
    startColumn: startCol,
    endLineNumber: err.line,
    endColumn: endCol,
    message,
    severity: monaco.MarkerSeverity.Error,
    source: "Synapse",
  };
}

/* ── Public API ────────────────────────────────────────────────────────── */

export function getLuaDiagnostics(code: string): monaco.editor.IMarkerData[] {
  if (!code || code.trim().length === 0) return [];

  const originalLines = code.split("\n");

  // Pre‑process: neutralise Luau syntax so luaparse doesn't false‑positive.
  const processed = stripLuauSyntax(code);

  const markers: monaco.editor.IMarkerData[] = [];
  const err = tryParse(processed);
  if (err) {
    markers.push(makeMarker(err, originalLines));
  }

  return markers;
}



/* ── Editor decoration management ──────────────────────────────────────── */

export function updateEditorDecorations(
  editor: monaco.editor.ICodeEditor,
  markers: monaco.editor.IMarkerData[],
) {
  const model = editor.getModel();
  if (!model) return;

  const decorations: monaco.editor.IModelDeltaDecoration[] = markers.map((m) => ({
    range: new monaco.Range(m.startLineNumber, 1, m.startLineNumber, 1),
    options: {
      isWholeLine: true,
      glyphMarginClassName: "synapse-error-glyph",
      glyphMarginHoverMessage: { value: `**Syntax Error:** ${m.message}` },
    },
  }));

  const oldDecorations = (editor as any)._synapseErrorDecorations || [];
  (editor as any)._synapseErrorDecorations = editor.deltaDecorations(
    oldDecorations,
    decorations,
  );
}
