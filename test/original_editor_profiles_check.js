// node test/original_editor_profiles_check.js from the Flutter project root.
// Runs real profile/tokenizer code against a deterministic Monaco bridge fixture.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const themes=new Map(),classes=new Map(),styles=new Map(),messages=[],commands=new Map();
let initialized,activeModel,options={},syntax,disposedSyntax=0;
const nodes={editor:{style:{}},loading:{remove(){}},'zenith-editor-hint':{hidden:true},'zenith-editor-help':{addEventListener(type,fn){this[type]=fn;}}};
const editor={
 updateOptions(next){Object.assign(options,next);},getModel:()=>activeModel,setModel(model){activeModel=model;},
 getPosition:()=>({lineNumber:1,column:1}),saveViewState:()=>({scrollTop:42}),restoreViewState(value){this.restored=value;},
 onDidChangeCursorPosition(){},onDidBlurEditorWidget(){},addCommand(key,fn){commands.set(key,fn);},trigger(){},
 deltaDecorations:(_,items)=>items,
};
const kind={Keyword:1,Function:2,Module:3,Snippet:4,TypeParameter:5,Class:6,Variable:7,Property:8,Method:9,Event:10,Enum:11};
const monaco={
 MarkerSeverity:{Error:8},Range:class{},KeyMod:{CtrlCmd:2048,Shift:1024,Alt:512},
 KeyCode:{KeyF:1,KeyS:2,KeyO:3,KeyN:4,Enter:5,KeyK:6,KeyP:7,KeyW:8,KeyL:9,F9:10,KeyT:11},Uri:{parse:value=>value},
 languages:{CompletionItemKind:kind,CompletionItemInsertTextRule:{InsertAsSnippet:4},CompletionItemTag:{Deprecated:1},
  register(){},setLanguageConfiguration(){},setMonarchTokensProvider(language,definition){syntax=definition;return {dispose(){disposedSyntax++;}};},
  registerCompletionItemProvider(){},registerSignatureHelpProvider(){},registerHoverProvider(){},
 },
 editor:{defineTheme(name,value){themes.set(name,value);},setTheme(){},create:()=>editor,setModelMarkers(){},
  createModel(value){const listeners=[];return {disposed:false,getValue:()=>value,getLineCount:()=>value.split('\n').length,
   onDidChangeContent(fn){listeners.push(fn);},dispose(){this.disposed=true;},getFullModelRange:()=>({}),pushStackElement(){},
   pushEditOperations(_,edits){value=edits[0].text;for(const fn of listeners)fn();}};},
 },
};
const context={monaco,console,setTimeout,clearTimeout,URL,WeakMap,location:{href:'http://127.0.0.1:9988/editor/index.html'},
 document:{fonts:{load:async()=>[]},documentElement:{classList:{toggle(name,value){classes.set(name,value);}},style:{setProperty(name,value){styles.set(name,value);}}},getElementById:id=>nodes[id]||null},
 fetch:async()=>({ok:true,json:async()=>({classes:{},datatypes:{},libraries:{},enums:{}})}),addEventListener(){},
 dispatchEvent(event){messages.push(event.detail);},CustomEvent:class{constructor(type,value){this.detail=value.detail;}}};
context.window=context;context.require=(_,callback)=>initialized=callback();context.require.config=()=>{};
vm.createContext(context);
for(const file of ['luau-language.js','synapse-diagnostics.js','synapse-theme.js','synapse-skins.js','editor.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../assets/editor',file),'utf8'),context,{filename:file});
const clone=value=>JSON.parse(JSON.stringify(value));
(async()=>{
 await initialized;const baseSyntax=syntax;
 const docs=[{id:'one',name:'one.luau',content:'local value = 42\nprint(value)'},{id:'two',name:'two.luau',content:'print("two")'}];
 const sync=(shell,extra={})=>context.orionReceive({type:'sync',documents:docs,activeId:'one',options:{shell,...extra}});
 const baselines=new Map();
 for(const shell of ['','synapseV3','synapseBlue','synapseX','synapseOriginal']){sync(shell);baselines.set(shell,clone(options));}
 const model=activeModel;
 const cases=()=>syntax.tokenizer.root.find(row=>row[1]&&typeof row[1]==='object'&&row[1].cases&&row[1].cases['@keywords'])[1].cases;
 sync('originalAwp',{background:'#191818'});
 assert.equal(options.fontSize,13);assert.equal(options.lineHeight,18);assert.equal(options.glyphMargin,true);
 assert.deepEqual(clone(options.padding),{top:0,bottom:2});assert.equal(options.lineNumbersMinChars,1);assert.equal(options.lineDecorationsWidth,0);
 assert.equal(options.quickSuggestions,false);assert.equal(options.suggestOnTriggerCharacters,false);assert.equal(options.tabCompletion,'off');
 assert.equal(themes.get('orion').colors['editor.background'],'#191818');assert.equal(themes.get('orion').colors['editor.lineHighlightBackground'],'#00000000');
 assert.equal(themes.get('orion').rules.find(row=>row.token==='keyword').foreground,'569CD6');
 sync('originalXeno',{background:'#050505'});
 assert.equal(themes.get('orion').colors['editor.background'],'#050505');assert.equal(themes.get('orion').colors['editor.lineHighlightBackground'],'#171717');
 assert.equal(options.lineHeight,18);assert.equal(options.renderLineHighlight,'all');assert.equal(options.fontSize,13);
 sync('originalKrnl',{background:'#282828'});
 assert.equal(options.fontSize,40/3);assert.equal(options.lineHeight,16);assert.equal(options.glyphMargin,false);assert.equal(options.renderLineHighlight,'none');
 assert.equal(options.folding,false);assert.equal(options.minimap.enabled,false);assert.equal(styles.get('--krnl-gutter-width'),'18px');
 assert.equal(cases()['@krnlBuiltins'],'builtin');assert(syntax.krnlBuiltins.includes('print'));assert(syntax.krnlBuiltins.includes('game'));
 assert.equal(themes.get('orion').rules.find(row=>row.token==='builtin').foreground,'59FFAC');
 assert.equal(themes.get('orion').rules.find(row=>row.token==='builtin').fontStyle,'bold');
 assert.equal(themes.get('orion').rules.find(row=>row.token==='keyword').foreground,'FF3C7A');
 sync('originalZenith',{background:'#0d0d0d',showEditorHints:true,formatOnPaste:true});
 assert.equal(options.lineHeight,20);assert.equal(options.fontSize,14);assert.equal(options.fontLigatures,false);assert.equal(options.wordWrap,'on');
 assert.equal(options.lineNumbersMinChars,5);assert.equal(options.lineDecorationsWidth,10);assert.equal(options.glyphMargin,false);
 assert.deepEqual(clone(options.padding),{top:0,bottom:0});assert.equal(options.hover.enabled,false);assert.equal(options.parameterHints.enabled,false);
 assert.equal(options.showFoldingControls,'always');assert.equal(options.suggest.selectionMode,'never');assert.equal(options.formatOnType,true);assert.equal(options.formatOnPaste,true);
 assert.equal(cases()['@keywords'].token,'keyword.$0');assert.equal(themes.get('orion').rules.find(row=>row.token==='keyword.local').foreground,'C678DD');
 assert.equal(nodes['zenith-editor-hint'].hidden,true);
 docs[0].content='';sync('originalZenith',{background:'#0d0d0d',showEditorHints:true});assert.equal(nodes['zenith-editor-hint'].hidden,false);
 sync('originalZenith',{background:'#0d0d0d',showEditorHints:false});assert.equal(nodes['zenith-editor-hint'].hidden,true);
 nodes['zenith-editor-help'].click();assert.equal(messages.at(-1).name,'help');
 commands.get(monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyW)();assert.equal(messages.at(-1).name,'close-tab');
 commands.get(monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyP)();assert.equal(messages.at(-1).name,'palette');
 commands.get(monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyT)();assert.equal(messages.at(-1).name,'new');
 assert.equal(activeModel,model);assert.equal(model.disposed,false);
 docs[0].content='local value = 42\nprint(value)';
 for(const shell of ['','synapseV3','synapseBlue','synapseX','synapseOriginal']){
  sync(shell);assert.deepEqual(clone(options),baselines.get(shell),`complete source-option cleanup into ${shell||'Orion'}`);
  assert.equal(syntax,baseSyntax);assert.equal(classes.get('original-port'),false);assert.equal(nodes['zenith-editor-hint'].hidden,true);
 }
 assert(disposedSyntax>=3);assert.equal(model.getValue(),docs[0].content);
 // Studio foreground/background changes preserve each Synapse's real syntax
 // rules and the Luau tokenizer, including V3's undocked editor profile.
 for (const [shell,keyword,string] of [
   ['synapseV3','569CD6','CE9178'],['synapseBlue','CC99CC','99CC99'],
   ['synapseX','FF6A00','468DD4'],['synapseOriginal','569CD6','CE9178'],
 ]) {
   sync(shell,{background:'#1e1e1e',foreground:'#E0F0FF',studioEditorEnabled:true});
   const theme=themes.get('orion');
   assert.equal(theme.rules.find(rule=>rule.token==='keyword').foreground.toUpperCase(),keyword);
   assert.equal(theme.rules.find(rule=>rule.token==='string').foreground.toUpperCase(),string);
   assert.equal(theme.colors['editor.foreground'],'#E0F0FF');
   assert.equal(syntax,baseSyntax);
   assert(syntax.keywords.includes('continue'));assert(syntax.keywords.includes('export'));
   assert(syntax.tokenizer.longcomment);assert(syntax.tokenizer.interpolated);
 }
 // Glass fallback owns an opaque shared backdrop across the GTK surfaces.
 // Changing this material never replaces a script model or its undo stack,
 // and the option is deliberately ignored by every preserved source UI.
 const glassBackdrop={color:'#17212d',opacity:.22,gradient:{
   colors:['#1a2636b8','#1c2431a6','#222933b3'],stops:[0,.52,1],begin:[-1,-1],end:[1,1],
 },radials:[{colors:['#b9d5ff14','#b9d5ff00'],stops:[0,1],center:[-.5,-.6],radius:.7}]};
 context.orionSetBackdropGeometry({x:264,y:156,width:1000,height:650});
 sync('orion',{glassEnabled:true,glassEditorRadius:20,glassTint:'#edf3ff09',glassMaterialOpacity:.22,windowBackdrop:glassBackdrop});
 assert.equal(classes.get('orion-glass'),true);assert.equal(classes.get('orion-transparent'),true);
 assert.equal(themes.get('orion').colors['editor.background'],'#00000000');
 assert.equal(themes.get('orion').colors['editorGutter.background'],'#00000000');
 assert.equal(styles.get('--window-backdrop-color'),'#17212d');
 assert.equal(styles.get('--window-backdrop-size'),'1000px 650px');
 assert.equal(styles.get('--window-backdrop-position'),'-264px -156px');
 const svg=decodeURIComponent(styles.get('--window-backdrop-image').slice(33,-2));
 assert(svg.includes('width="1000" height="650"'));assert(svg.includes('stop-color="#1a2636"'));
 assert(svg.includes('cx="250" cy="130"'));assert(svg.includes('<g opacity="1">'));
 assert(Math.abs(Number(svg.match(/cy="130" r="([^"]+)"/)[1])-455)<.001);
 assert.equal(context.document.documentElement.style.clipPath,'');
 assert.equal(nodes.editor.style.clipPath,'inset(0 round 20px)');
 assert.equal(nodes.editor.style.opacity,'');assert.equal(styles.get('--glass-tint'),'#edf3ff09');
 assert.equal(styles.get('--glass-material-opacity'),'1');
 assert.equal(activeModel,model);assert.equal(model.disposed,false);
 context.orionSetBackdropGeometry({x:200,y:100,width:800,height:520});
 assert.equal(styles.get('--window-backdrop-position'),'-200px -100px');
 assert.equal(styles.get('--window-backdrop-size'),'800px 520px');
 sync('orion',{glassEnabled:true,studioEditorEnabled:true,studioEditorOpacity:.5,
   studioEditorTransparent:true,glassEditorRadius:16,windowBackdrop:glassBackdrop});
 assert.equal(nodes.editor.style.opacity,'0.5');
 assert.equal(themes.get('orion').colors['editor.background'],'#00000000');
 // Actual compositor Glass uses clean alpha snapshots, with the desktop tint
 // supplied once by Flutter. No synthetic native canvas may obscure it.
 sync('orion',{glassEnabled:true,compositorGlass:true,studioEditorEnabled:true,
   studioEditorTransparent:true,glassEditorRadius:20,windowBackdrop:glassBackdrop});
 assert.equal(classes.get('orion-compositor-glass'),true);
 assert.equal(classes.get('orion-window-backdrop'),false);
 assert.equal(themes.get('orion').colors['editor.background'],'#00000000');
 assert.equal(themes.get('orion').colors['editorGutter.background'],'#00000000');
 assert.equal(context.document.documentElement.style.clipPath,'');
 assert.equal(nodes.editor.style.clipPath,'inset(0 round 20px)');
 assert.equal(activeModel,model);assert.equal(model.disposed,false);
 sync('orion',{glassEnabled:true,windowBackdrop:glassBackdrop});
 assert.equal(classes.get('orion-compositor-glass'),false);
 assert.equal(classes.get('orion-window-backdrop'),true);

 for(const shell of ['orion','synapseV3','synapseBlue','synapseX','synapseOriginal','originalKrnl']) {
   sync(shell,{glassEnabled:shell!=='orion',windowBackdrop:glassBackdrop});
   assert.equal(classes.get('orion-glass'),false,`glass cleanup into ${shell}`);
   assert.equal(classes.get('orion-compositor-glass'),false);
   assert.equal(classes.get('orion-transparent'),false);
   assert.equal(classes.get('orion-window-backdrop'),false);
   assert.equal(context.document.documentElement.style.clipPath,'');
   assert.equal(nodes.editor.style.clipPath,'');
   assert.equal(nodes.editor.style.opacity,'');assert.equal(activeModel,model);
 }
 console.log('Original Monaco profiles passed: exact palettes/font geometry/gating; cached syntax restoration, shared models, Zenith hints and existing-profile cleanup.');
})().catch(error=>{console.error(error);process.exitCode=1;});
