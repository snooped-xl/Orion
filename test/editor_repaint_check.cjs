// node test/editor_repaint_check.cjs
// Exercise actual bridge visibility/font recovery without a browser or GPU.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const events={},fontEvents={},messages=[],frames=[],fontRequests=[],layouts=[],renders=[],timeouts=[];
let initialized,activeModel=null,remeasures=0;
const noop=()=>{},node={style:{},clientWidth:0,clientHeight:0};
const editor={
  updateOptions:noop,getModel:()=>activeModel,setModel:model=>activeModel=model,getPosition:()=>null,
  onDidChangeCursorPosition:noop,onDidBlurEditorWidget:noop,addCommand:noop,
  saveViewState:()=>({}),restoreViewState:noop,deltaDecorations:(_,value)=>value,
  layout:dimensions=>layouts.push(dimensions),render:force=>renders.push(force),
};
const monaco={KeyMod:{CtrlCmd:2048,Shift:1024,Alt:512},KeyCode:{},Uri:{parse:value=>value},
  editor:{create:()=>editor,defineTheme:noop,setTheme:noop,setModelMarkers:noop,remeasureFonts:()=>remeasures++,
    createModel(value){return {getValue:()=>value,onDidChangeContent:noop,dispose:noop};}},
};
const document={hidden:false,
  fonts:{load(font){fontRequests.push(font);return font.includes('OrionXMono')?Promise.reject(new Error('Unavailable font')):new Promise(()=>{});},addEventListener:(name,fn)=>fontEvents[name]=fn},
  documentElement:{classList:{toggle:noop},style:{setProperty:noop}},
  getElementById:id=>id==='editor'?node:id==='loading'?{remove:noop}:id==='zenith-editor-hint'?{hidden:true}:null,
  addEventListener:(name,fn)=>events[name]=fn,
};
const context={monaco,document,console,URL,location:{href:'http://127.0.0.1:9999/editor/index.html'},
  OrionLuau:{register:noop},fetch:async()=>({ok:true,json:async()=>({})}),
  addEventListener:(name,fn)=>events[name]=fn,requestAnimationFrame:fn=>frames.push(fn),
  dispatchEvent:event=>messages.push(event.detail),CustomEvent:class{constructor(_,value){this.detail=value.detail;}},
  setTimeout(fn,ms){timeouts.push({fn,ms});return timeouts.length;},clearTimeout:noop,
};
context.window=context;context.require=(_,fn)=>initialized=fn();context.require.config=noop;vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname,'../assets/editor/editor.js'),'utf8'),context,{filename:'editor.js'});
const paint=()=>{const queued=frames.splice(0);queued.forEach(fn=>fn());};
(async()=>{
  for(let i=0;i<10 && !timeouts.length;i++)await Promise.resolve();
  assert.equal(timeouts.length,1);assert.equal(timeouts[0].ms,1000,'font loading cannot stall editor readiness');
  timeouts[0].fn();
  await initialized;
  assert(fontRequests.includes('14px "JetBrains Mono"'),'load the measured default font');
  assert(messages.some(message=>message.type==='ready'),'a failed font must not abort editor startup');
  paint();assert.equal(layouts.length,0,'never cache an empty viewport');
  node.clientWidth=840;node.clientHeight=480;
  events.pageshow();events.focus();events.visibilitychange();
  assert.equal(frames.length,1,'visibility notifications coalesce into one frame');
  paint();assert.equal(layouts.length,1);assert.equal(layouts[0].width,840);assert.equal(layouts[0].height,480);
  assert.deepEqual(renders,[true],'same-size native remaps force glyph repaint');
  document.hidden=true;context.orionReceive({type:'layout'});paint();
  assert.equal(layouts.length,1,'hidden documents defer their repaint');
  document.hidden=false;events.visibilitychange();paint();assert.equal(layouts.length,2);
  fontEvents.loadingdone();fontEvents.loadingdone();
  assert.equal(remeasures,0);assert.equal(frames.length,1);paint();assert.equal(remeasures,1);assert.equal(layouts.length,3);
  context.orionReceive({type:'layout'});context.orionLayout();paint();assert.equal(layouts.length,4);
  context.orionReceive({type:'sync',documents:[{id:'one',content:'print(42)'}],activeId:'one',options:{shell:'orion'}});
  for(let i=0;i<50;i++)context.orionReceive({type:'flush',requestId:i});
  assert.equal(frames.length,0,'ordinary model synchronization/flush does not force layout or glyph repaint');
  console.log('Editor recovery passed: bounded font fallback, nonzero viewport, coalesced native remap/font repaint and idle edit path.');
})().catch(error=>{console.error(error);process.exitCode=1;});
