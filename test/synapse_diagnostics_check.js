// Run with `node test/synapse_diagnostics_check.js` from the project root.
// Scanner fixture remains import compatible; the editor no longer exposes or
// enables Error Logging, even when old preferences request it.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const markers = new Map();
let activeModel, initialized, editorOptions;
const editor = {
  updateOptions(options) {editorOptions=options;}, getModel: () => activeModel, setModel: model => activeModel = model,
  getPosition: () => ({lineNumber:1,column:1}), saveViewState: () => ({}), restoreViewState() {},
  onDidChangeCursorPosition() {}, onDidBlurEditorWidget() {}, addCommand() {},
  deltaDecorations: (_, value) => value,
};
const monaco = {
  MarkerSeverity:{Error:8}, Range:class { constructor(...values) {this.values=values;} },
  KeyMod:{CtrlCmd:2048,Shift:1024,Alt:512}, KeyCode:{KeyF:1,KeyS:2,KeyO:3,KeyN:4,Enter:5,KeyK:6},
  Uri:{parse:value=>value},
  editor:{defineTheme() {},setTheme() {},create:()=>editor,
    setModelMarkers:(model,owner,value)=>markers.set(model,value),
    createModel:content=>({getValue:()=>content,onDidChangeContent() {},dispose() {},
      getFullModelRange:()=>({}),pushStackElement() {},
      pushEditOperations:(_,edits)=>content=edits[0].text}),
  },
};
const context = {monaco,console,setTimeout,clearTimeout,URL,location:{href:'http://127.0.0.1:9999/editor/index.html'},
  document:{fonts:{load:async()=>[]},documentElement:{classList:{toggle(){}},style:{setProperty(){}}},
    getElementById:id=>id==='editor'?{style:{}}:id==='loading'?{remove(){}}:null},
  fetch:async()=>({ok:true,json:async()=>({})}), OrionLuau:{register(){}},
  addEventListener(){},dispatchEvent(){},CustomEvent:class{},
};
context.window=context;
context.require=(_modules, callback)=>initialized=callback();
context.require.config=()=>{};
vm.createContext(context);
for (const file of ['synapse-diagnostics.js','synapse-theme.js','synapse-skins.js','editor.js']) {
  vm.runInContext(fs.readFileSync(`assets/editor/${file}`,'utf8'),context,{filename:file});
}
(async()=>{
  await initialized;
  const diagnose=context.OrionSynapseDiagnostics.getLuaDiagnostics;
  for (const source of [
    'local value = 42\nprint(value)',
    'local text = "function : type // += end"\nprint(text)',
    '-- if type Thing = // +=\nlocal value = 1',
    '--[[\n@native\nthis is not code += :\n]]\nprint("ok")',
    'local text = [[\ntype Foo = invalid @native\n]]\nprint(text)',
    'local function sum(value: number): number\n return value + 1\nend',
    'type Item = {name: string}\nlocal item = {name = "ok"}\nitem.name ..= "!"',
    'for index = 1, 3 do\n continue\nend',
  ]) assert.equal(diagnose(source).length,0,source);
  const failures=diagnose('local broken = )\nprint("next")');
  assert.equal(failures.length,1); assert.equal(failures[0].severity,8);
  assert.equal(failures[0].source,'Synapse');
  const sync=enabled=>context.orionReceive({type:'sync',documents:[
    {id:'a',name:'a.luau',content:'local broken = )\nprint("next")'},
  ],activeId:'a',options:{shell:'synapseV3',diagnosticEnabled:enabled}});
  sync(true); assert.equal(markers.get(activeModel).length,0);
  assert.equal(editorOptions.overviewRulerBorder,false);
  assert.equal(editorOptions.hideCursorInOverviewRuler,true);
  const source=activeModel.getValue();
  sync(false); assert.equal(markers.get(activeModel).length,0);
  assert.equal(editor._synapseErrorDecorations.length,0);
  assert.equal(activeModel.getValue(),source);
  sync(true); assert.equal(markers.get(activeModel).length,0);
  for(const shell of ['synapseV3','synapseBlue','synapseX','synapseOriginal']) {
    context.orionReceive({type:'sync',documents:[{id:'a',name:'a.luau',content:source}],activeId:'a',options:{shell,diagnosticEnabled:true}});
    assert.equal(markers.get(activeModel).length,0,shell+' ignores retired Error Logging preference');
  }
  context.orionReceive({type:'sync',documents:[{id:'a',name:'a.luau',content:source}],activeId:'a',options:{}});
  assert.equal(markers.get(activeModel).length,0);
  assert.equal(editorOptions.overviewRulerBorder,true);
  assert.equal(editorOptions.hideCursorInOverviewRuler,false);
  assert.equal(activeModel.getValue(),source);
  console.log('Synapse Error Logging removal passed: all four interfaces ignore retired flags, clear markers and preserve source.');
})().catch(error=>{console.error(error);process.exitCode=1;});
