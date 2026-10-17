// node test/luau_analysis_cache_check.cjs
// Exercises the real provider with Monaco's model-version contract. Cached
// analysis must never leave stale types after edits, undo, or tab switches.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const language=require('../assets/editor/luau-language.js');
const api=JSON.parse(fs.readFileSync(path.join(__dirname,'../assets/editor/roblox-api.json')));
const providers={},noop=()=>{};
const monaco={languages:{
  CompletionItemKind:{Keyword:1,TypeParameter:2,Module:3,Class:4,Variable:5,Property:6,Function:7,Method:8,Event:9,Enum:10,EnumMember:11,Snippet:12,Text:13},
  CompletionItemInsertTextRule:{InsertAsSnippet:4},CompletionItemTag:{Deprecated:1},
  register:noop,setLanguageConfiguration:noop,setMonarchTokensProvider:()=>({dispose:noop}),
  registerCompletionItemProvider:(_,value)=>providers.completion=value,
  registerHoverProvider:(_,value)=>providers.hover=value,
  registerSignatureHelpProvider:(_,value)=>providers.signature=value,
}};
const catalog=language.register(monaco,api);
function model(initial){
  let text=initial,version=1;
  return {
    reads:0,getValue(){this.reads++;return text;},getVersionId:()=>version,
    getLineContent:line=>text.split('\n')[line-1],
    getWordUntilPosition(position){const prefix=this.getLineContent(position.lineNumber).slice(0,position.column-1),word=/[A-Za-z_]\w*$/.exec(prefix)?.[0]||'';return {word,startColumn:position.column-word.length,endColumn:position.column};},
    getWordAtPosition(position){const line=this.getLineContent(position.lineNumber);for(const match of line.matchAll(/[A-Za-z_]\w*/g))if(match.index<position.column&&match.index+match[0].length>=position.column-1)return {word:match[0],startColumn:match.index+1,endColumn:match.index+match[0].length+1};return null;},
    getValueInRange(range){return text.split('\n').slice(0,range.endLineNumber).map((line,index)=>index===range.endLineNumber-1?line.slice(0,range.endColumn-1):line).join('\n');},
    replace(value){text=value;version++;},
  };
}
const position={lineNumber:2,column:15};
const first=model('local thing = Instance.new("Part")\nthing.Position');
const complete=m=>providers.completion.provideCompletionItems(m,position).suggestions;
let suggestions=complete(first),hover=providers.hover.provideHover(first,position);
assert(suggestions.some(row=>row.label==='Position'));
assert(hover.contents.some(row=>row.value.includes('Position: Vector3')));
for(let i=0;i<20;i++){assert.deepEqual(complete(first),suggestions);assert.deepEqual(providers.hover.provideHover(first,position),hover);}
assert.equal(first.reads,1,'unchanged completion and hover reuse one document snapshot');
first.replace('local thing = game:GetService("Players")\nthing.Position');
assert(complete(first).some(row=>row.label==='LocalPlayer'));
assert(!complete(first).some(row=>row.label==='Position'),'an edit invalidates inferred types');
assert.equal(providers.hover.provideHover(first,position),null);
assert.equal(first.reads,2);
first.replace('local thing = Instance.new("Part")\nthing.Position');
assert.deepEqual(complete(first),suggestions,'undo content under a new version restores completion');
assert.deepEqual(providers.hover.provideHover(first,position),hover);
const second=model('local thing = Vector3.new()\nthing.Position');
assert(complete(second).some(row=>row.label==='Magnitude'));
assert.deepEqual(complete(first),suggestions,'models with the same version retain independent analyses');
assert.equal(first.reads,3);assert.equal(second.reads,1);
// The efficient duplicate check preserves global precedence and local order.
const locals='local print = 1\nlocal variable = 1\nlocal function greeting(name: string)\nend\nlocal variable = 2';
const rows=catalog.complete(locals,'');
assert.equal(rows.filter(row=>row.name==='print').length,1);
assert.equal(rows.find(row=>row.name==='print').kind,'function');
assert.equal(rows.filter(row=>row.name==='variable').length,1);
assert(rows.findIndex(row=>row.name==='variable')<rows.findIndex(row=>row.name==='greeting'));
// Signature scanning retains string, multiline-comment, and bracket behavior.
for(const [source,expression,argument]of [
 ['print("comma, in a string", ','print',1],
 ['math.clamp(1, {2,3}, ','math.clamp',2],
 ['print(--[=[ (, ]=]\n','print',0],
 ['print([[comma, in a string]], ','print',1],
])assert.deepEqual(language.callContext(source),{expression,argument});
console.log('Luau analysis cache passed: fresh edits/undo/tab types, shared snapshots, identical ordering and signatures.');
