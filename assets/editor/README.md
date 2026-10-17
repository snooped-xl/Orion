# Orion's offline Monaco editor

This page embeds Microsoft Monaco Editor **0.57.0** inside the Linux WebKitGTK view. All JavaScript, fonts, language metadata and the editor worker are bundled; the editor does not fetch a CDN at runtime. The desktop host serves these assets on its private loopback HTTP origin, so workers share the same origin.

## Luau support

`luau-language.js` registers Luau syntax, comments, bracket pairs, folding, indentation, snippets, signature help and documentation hover. It supplies completion for Luau globals and libraries, Roblox services, instance constructors, enums, class members, inherited members, simple typed local variables, `GetService` aliases, and member chains. Local function declarations also appear in completion and signature help.

This is a catalog/declaration completion provider. It does not implement the Luau language server, full type inference, typechecking or runtime execution. The `format` command reindents through Monaco's language indentation rules; it does not rewrite Luau syntax.

## Desktop bridge

Desktop → JavaScript: `window.orionReceive(command)` receives a JavaScript object. The desktop serializes commands as JSON; script text remains data.

- `{type:'sync', documents:[{id,name,content,nativeEcho?}], activeId, options}` updates the workspace. Models retain undo history and per-tab cursor/scroll state. `nativeEcho:true` marks an acknowledgement of native-origin text: existing Monaco models keep their current content so a delayed Flutter snapshot cannot overwrite newer keystrokes. New models still initialize from `content`. Intentional external updates (open/import/clear/recovery) omit this flag and update the model through undoable edits. Options accept `fontSize`, `wordWrap`, `lineNumbers`, `minimap`, `reducedMotion`, `autocomplete`, `brightness`, and `background`, `foreground`, `accent`, `muted`, `border` colors. The colors may instead arrive in `options.palette`.
- `{type:'action', name}` supports `undo`, `redo`, `paste`, `selectAll`, `find`, `replace`, `format`, `suggest`, `focus`, `clear`. Paste may include `text` supplied by Flutter's native clipboard.
- `{type:'flush', requestId}` returns the current model text for a save operation.

JavaScript → desktop: `window.webkit.messageHandlers.orion.postMessage(JSON.stringify(message))` emits `ready`, `change` (`id`, `content`), `cursor` (`line`, `column`), `flush` (`requestId`, `id`, `content`), `shortcut` (`name`), or `error` (`message`). Shortcuts forward New, Open, Save, Save As, Execute and the command palette. Normal editing shortcuts remain Monaco's own controls.

## Third-party notices

Monaco Editor is Copyright Microsoft Corporation and distributed under MIT (`MONACO-LICENSE.txt`). Its npm distribution is bundled without modifying the vendor code. Pin and integrity information are recorded in `vendor.json`.

`roblox-api.json` contains a transformed metadata catalog derived from **Roblox Corporation's Creator Documentation**, [Roblox/creator-docs](https://github.com/Roblox/creator-docs), commit `784c5e217446c65958d5d84f5c5f1d127951a8d7`. It contains 625 classes, 49 datatypes, 11 libraries and 513 enums. Names, signatures and documentation summaries were extracted from the English engine-reference YAML, with inaccessible members excluded. The documentation is licensed under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/), whose text is included as `ROBLOX-LICENSE.txt`; code licensing is included as `ROBLOX-LICENSE-CODE.txt`. The derived catalog is attributed to Roblox Corporation and licensed under the same CC BY 4.0 terms. Orion is not endorsed by Roblox Corporation.

JetBrains Mono is licensed under the SIL Open Font License 1.1 (`JetBrainsMono-OFL.txt`).
