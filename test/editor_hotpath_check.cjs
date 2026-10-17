// node test/editor_hotpath_check.cjs
// Bridge integration fixture: editing still sends every full content update and
// flushes before shortcuts, without hidden whole-document scans or marker work.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const messages=[],commands=new Map(),events={},markers=[];
let initialized,activeModel,reads=0,timers=0;
const noop=()=>{};
const editor={updateOptions:noop,getModel:()=>activeModel,setModel:model=>activeModel=model,
  getPosition:()=>({lineNumber:1,column:1}),saveViewState:()=>({}),restoreViewState:noop,
  onDidChangeCursorPosition:fn=>events.cursor=fn,onDidBlurEditorWidget:fn=>events.blur=fn,
  addCommand:(key,fn)=>commands.set(key,fn),deltaDecorations:(_,value)=>value,
};
const monaco={MarkerSeverity:{Error:8},Range:class{},KeyMod:{CtrlCmd:2048,Shift:1024,Alt:512},KeyCode:{KeyF:1,KeyS:2,KeyO:3,KeyN:4,Enter:5,KeyK:6,KeyL:9,F9:10,KeyT:11},Uri:{parse:value=>value},
  editor:{defineTheme:noop,setTheme:noop,create:()=>editor,setModelMarkers:(...args)=>markers.push(args),
    createModel(initial){let content=initial;const listeners=[];return {
      getValue(){reads++;return content;},getLineCount:()=>content.split('\n').length,
      onDidChangeContent:fn=>listeners.push(fn),getFullModelRange:()=>({}),pushStackElement:noop,dispose:noop,
      pushEditOperations(_,edits){content=edits[0].text;listeners.forEach(fn=>fn());},
    };},
  },
};
const context={monaco,console,URL,WeakMap,WeakSet,location:{href:'http://127.0.0.1:9999/editor/index.html'},
  document:{fonts:{load:async()=>[]},documentElement:{classList:{toggle:noop},style:{setProperty:noop}},getElementById:id=>id==='editor'?{style:{}}:id==='loading'?{remove:noop}:id==='zenith-editor-hint'?{hidden:true}:null},
  OrionLuau:{register:noop},fetch:async()=>({ok:true,json:async()=>({})}),addEventListener:noop,
  dispatchEvent:event=>messages.push(event.detail),CustomEvent:class{constructor(_,value){this.detail=value.detail;}},
  setTimeout(fn,ms){timers++;return setTimeout(fn,ms);},clearTimeout,
};
context.window=context;context.require=(_,callback)=>initialized=callback();context.require.config=noop;vm.createContext(context);
for(const file of ['synapse-diagnostics.js','synapse-theme.js','synapse-skins.js','editor.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../assets/editor',file),'utf8'),context,{filename:file});
(async()=>{
  await initialized;
  const docs=[{id:'a',name:'a.luau',content:'print("a")'},{id:'b',name:'b.luau',content:'print("b")'}];
  const sync=id=>context.orionReceive({type:'sync',documents:docs.map(doc=>({...doc,nativeEcho:true})),activeId:id,options:{shell:'orion'}});
  sync('a');reads=0;timers=0;const previousMarkers=markers.length;
  for(let i=0;i<50;i++)activeModel.pushEditOperations([],[{text:'print("'+i+'")'}]);
  assert.equal(reads,50,'one mandatory content read per edit, no inactive hint scan');
  assert.equal(timers,0,'retired diagnostics do not wake a typing timer');
  assert.equal(markers.length,previousMarkers,'typing does not rebuild retired markers');
  const changes=messages.filter(message=>message.type==='change');
  assert.equal(changes.length,50);assert.equal(changes.at(-1).content,'print("49")');
  sync('a');sync('a');
  assert.equal(messages.filter(message=>message.type==='cursor').length,1,'identical sync/cursor notifications are suppressed');
  events.cursor({position:{lineNumber:1,column:3}});
  events.cursor({position:{lineNumber:1,column:3}});
  assert.equal(messages.filter(message=>message.type==='cursor').length,2);
  sync('b');
  assert.equal(messages.filter(message=>message.type==='cursor').length,3,'a new active tab reports its own cursor');
  context.orionReceive({type:'flush',requestId:'before-save'});
  assert.equal(messages.at(-1).type,'flush');assert.equal(messages.at(-1).content,'print("b")');
  commands.get(monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyS)();
  assert.equal(messages.at(-2).type,'change');assert.equal(messages.at(-2).content,'print("b")');
  assert.equal(messages.at(-1).type,'shortcut');assert.equal(messages.at(-1).name,'save');
  events.blur();assert.equal(messages.at(-1).type,'change');
  console.log('Editor hot paths passed: complete ordered edit/flush/shortcut delivery, no retired typing work, independent tab cursors.');
})().catch(error=>{console.error(error);process.exitCode=1;});
