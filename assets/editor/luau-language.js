/* Orion's Luau catalog completion provider. Engine metadata: Roblox/creator-docs.
 * This provider supplies catalog and local declaration completion, not a typechecker or LSP. */
(function (root) {
  'use strict';
  const keywords = ['and','break','continue','do','else','elseif','end','export','false','for','function','if','in','local','nil','not','or','repeat','return','then','true','type','until','while'];
  const primitiveTypes = ['any','boolean','buffer','never','nil','number','string','thread','unknown','vector'];
  const globals = {
    assert: ['value: T', 'message: string?', 'T'], error: ['message: any', 'level: number?', 'never'],
    print: ['...values: any', '()'], warn: ['...values: any', '()'],
    pairs: ['table: table', 'iterator'], ipairs: ['table: table', 'iterator'],
    pcall: ['function: function', '...arguments: any', '(boolean, ...any)'],
    xpcall: ['function: function', 'handler: function', '...arguments: any', '(boolean, ...any)'],
    require: ['module: ModuleScript | string', 'any'], tonumber: ['value: string', 'base: number?', 'number?'],
    tostring: ['value: any', 'string'], type: ['value: any', 'string'], typeof: ['value: any', 'string'],
    next: ['table: table', 'index: any?', '(any, any)'], select: ['index: number | string', '...values: any', '...any'],
    unpack: ['table: table', 'start: number?', 'finish: number?', '...any'],
    getmetatable: ['value: any', 'table?'], setmetatable: ['table: table', 'metatable: table?', 'table'],
    rawequal: ['a: any', 'b: any', 'boolean'], rawget: ['table: table', 'key: any', 'any'],
    rawset: ['table: table', 'key: any', 'value: any', 'table'], rawlen: ['value: table | string', 'number'],
    gcinfo: ['number'], getfenv: ['target: function | number?', 'table'], setfenv: ['target: function | number', 'environment: table', '()'],
    newproxy: ['metatable: boolean?', 'userdata'], time: ['number'], elapsedTime: ['number'],
    tick: ['number'], wait: ['seconds: number?', 'number'], spawn: ['function: function', '()'], delay: ['seconds: number', 'function: function', '()'],
  };
  const snippets = [
    ['local function','local function ${1:name}(${2})\n\t${0}\nend','Declare a local function'],
    ['function','function ${1:name}(${2})\n\t${0}\nend','Declare a function'],
    ['if','if ${1:condition} then\n\t${0}\nend','Conditional block'],
    ['if else','if ${1:condition} then\n\t${2}\nelse\n\t${0}\nend','Conditional with an alternative'],
    ['for ipairs','for ${1:index}, ${2:value} in ipairs(${3:items}) do\n\t${0}\nend','Iterate an array'],
    ['for pairs','for ${1:key}, ${2:value} in pairs(${3:items}) do\n\t${0}\nend','Iterate a table'],
    ['for','for ${1:i} = ${2:1}, ${3:10} do\n\t${0}\nend','Numeric loop'],
    ['while','while ${1:condition} do\n\t${0}\nend','While loop'],
    ['repeat','repeat\n\t${0}\nuntil ${1:condition}','Repeat loop'],
    ['GetService','local ${1:Players} = game:GetService("${1:Players}")','Get a Roblox service'],
    ['Connect','Connect(function(${1})\n\t${0}\nend)','Connect an event handler'],
    ['task spawn','task.spawn(function()\n\t${0}\nend)','Schedule a function'],
    ['type','type ${1:Name} = {\n\t${2:field}: ${3:string},\n}','Declare a Luau type'],
  ];
  function bareType(type) { return String(type || '').replace(/^(Class|Datatype|Enum)\./, '').replace(/[?]/g, '').split(/[|&]/)[0].trim(); }
  function globalDefinition(name) {
    const args = globals[name];
    return args && {name,kind:'function',parameters:args.slice(0,-1).map(arg => {
      const [parameter,type] = arg.split(': '); return {name:parameter,type:type || 'any',optional:(type || '').endsWith('?')};
    }),returns:[args[args.length-1]],summary:'Luau / Roblox global function.'};
  }
  function createCatalog(api) {
    api = Object.assign({classes:{},datatypes:{},libraries:{},enums:{}},api);
    const inherited = new Map();
    function members(type, visited = new Set()) {
      type = bareType(type);
      if (inherited.has(type)) return inherited.get(type);
      if (visited.has(type)) return [];
      visited.add(type);
      const row = api.classes[type] || api.datatypes[type] || api.libraries[type];
      if (!row) return [];
      const byName = new Map();
      for (const parent of row.inherits || []) for (const member of members(parent,visited)) byName.set(member.name, member);
      for (const member of row.members || []) byName.set(member.name,member);
      const result = Array.from(byName.values()); inherited.set(type,result); return result;
    }
    const services = Object.keys(api.classes).filter(name => api.classes[name].service);
    function declarations(text) {
      const symbols = new Map([['game','DataModel'],['workspace','Workspace'],['script','LuaSourceContainer'],['shared','table'],['_G','table']]);
      for (const match of text.matchAll(/\blocal\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_]\w*\??))?\s*=\s*([^\n;]+)/g)) {
        const name=match[1], value=match[3]; let type=match[2];
        if (!type) {
          let found = /(?:game|Game)\s*:\s*GetService\s*\(\s*["']([^"']+)["']/.exec(value);
          if (found) type=found[1];
          else if ((found=/Instance\s*\.\s*new\s*\(\s*["']([^"']+)["']/.exec(value))) type=found[1];
          else if ((found=/^([A-Za-z_]\w*)\s*\.\s*(?:new|from\w+)\s*\(/.exec(value))) type=found[1];
          else if (/^["'`]/.test(value.trim())) type='string';
          else if (/^\s*(?:true|false)\b/.test(value)) type='boolean';
          else if (/^\s*-?\d/.test(value)) type='number';
          else if (/^\s*\{/.test(value)) type='table';
          else type=resolveType(value.trim(),symbols);
        }
        symbols.set(name,bareType(type || 'any'));
      }
      for (const match of text.matchAll(/\blocal\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)/g)) symbols.set(match[1], match[2]);
      for (const match of text.matchAll(/(?:local\s+)?function\s+([A-Za-z_]\w*)\s*\(([^)]*)\)/g)) symbols.set(match[1],{name:match[1],kind:'function',parameters:match[2].split(',').filter(s=>s.trim()).map(s=>{const [name,type]=s.trim().split(/\s*:\s*/);return {name,type:type||'any'};}),returns:['any'],summary:'Function declared in this document.'});
      return symbols;
    }
    function resolveType(expression,symbols) {
      expression = expression.trim().replace(/^\((.*)\)$/, '$1');
      let service=/^game:GetService\(["']([^"']+)["']\)(.*)$/.exec(expression);
      if (service) expression=service[1]+service[2];
      const parts=expression.split(/[.:]/);
      let type=symbols.get(parts.shift()) || expression.split(/[.:]/)[0];
      if (typeof type !== 'string') return 'function';
      for (let name of parts) {
        if (!name) continue;
        name=name.replace(/\([^)]*\)$/, '');
        if (type==='DataModel' && api.classes[name] && api.classes[name].service) {type=name;continue;}
        const member=members(type).find(m=>m.name===name);
        if (!member) return null;
        type=bareType(member.type || (member.returns || [])[0] || (member.kind==='event' ? 'RBXScriptSignal' : 'any'));
      }
      return type;
    }
    function context(text, before, symbols = declarations(text)) {
      const wordMatch=/[A-Za-z_]\w*$/.exec(before),word=wordMatch?wordMatch[0]:'';
      const memberMatch=/([A-Za-z_]\w*(?:(?:[.:][A-Za-z_]\w*)|(?:\(["'][^"']*["']\)))*)\s*([.:])\s*\w*$/.exec(before);
      return {symbols,word,member:memberMatch&&memberMatch[1],separator:memberMatch&&memberMatch[2]};
    }
    function complete(text,before,symbols) {
      const ctx=context(text,before,symbols);
      const quoted=/(GetService|Instance\.new|FindFirstChildOfClass|FindFirstChildWhichIsA|IsA)\s*\(\s*(["'])([^"']*)$/.exec(before);
      if (quoted) return (quoted[1]==='GetService'?services:Object.keys(api.classes)).filter(name=>name.toLowerCase().startsWith(quoted[3].toLowerCase())).map(name=>({name,kind:'class',insertText:name,replaceLength:quoted[3].length,summary:api.classes[name].summary}));
      if (ctx.member==='Enum') return Object.keys(api.enums).map(name=>({name,kind:'enum',summary:'Roblox enum.'}));
      if (ctx.member && ctx.member.startsWith('Enum.')) return (api.enums[ctx.member.slice(5)]||[]).map(m=>({...m,kind:'enumMember'}));
      if (ctx.member) {
        const type=resolveType(ctx.member,ctx.symbols);
        let rows=(ctx.member==='Instance'?(api.datatypes.Instance?.members || []):members(type)).filter(m=>ctx.separator!==':'||['method','callback'].includes(m.kind)||(type==='string'&&m.kind==='function'));
        if (type==='DataModel' && ctx.separator==='.') rows=rows.concat(services.map(name=>({name,kind:'property',type:name,summary:api.classes[name].summary})));
        return rows.map(m=>({...m,owner:type,parameters:ctx.separator===':'&&type==='string'?(m.parameters||[]).slice(1):m.parameters}));
      }
      const rows=keywords.map(name=>({name,kind:'keyword',summary:'Luau keyword.'}));
      rows.push(...primitiveTypes.map(name=>({name,kind:'type',summary:'Luau type.'})));
      rows.push(...Object.keys(globals).map(globalDefinition));
      for (const name of ['game','workspace','script','shared','_G']) rows.push({name,kind:'variable',type:ctx.symbols.get(name),summary:'Roblox global.'});
      for (const name of Object.keys(api.libraries)) rows.push({name,kind:'module',summary:api.libraries[name].summary});
      for (const name of Object.keys(api.datatypes)) rows.push({name,kind:'class',summary:api.datatypes[name].summary});
      rows.push({name:'Enum',kind:'enum',summary:'Roblox engine enums.'});
      // A Set preserves the existing order and duplicate rules without doing
      // a linear search through every preceding local for every declaration.
      const names=new Set(rows.map(row=>row.name));
      for (const [name,type] of ctx.symbols) if (!names.has(name)) {
        rows.push(typeof type==='object'?type:{name,kind:'variable',type,summary:'Local declaration.'});
        names.add(name);
      }
      rows.push(...snippets.map(([name,insertText,summary])=>({name,insertText,summary,kind:'snippet'})));
      return rows;
    }
    function definition(text,expression,symbols) {
      if (globals[expression]) return globalDefinition(expression);
      symbols=symbols||declarations(text);
      const local=symbols.get(expression);
      if (typeof local==='object') return local;
      const match=/^(.*)([.:])([A-Za-z_]\w*)$/.exec(expression);
      if(!match)return null;
      const type=resolveType(match[1],symbols);
      const member=members(type).find(m=>m.name===match[3]);
      return member && match[2]===':' && type==='string'?{...member,parameters:(member.parameters||[]).slice(1)}:member;
    }
    return {api,members,services,declarations,resolveType,context,complete,definition};
  }
  function signature(definition) {
    const args=(definition.parameters||[]).map(p=>`${p.name}: ${p.type}${p.optional&&!p.type.endsWith('?')?'?':''}`);
    return `${definition.name}(${args.join(', ')})${(definition.returns||[]).length ? ': '+definition.returns.join(', ') : ''}`;
  }
  function snippet(definition) {
    if (definition.insertText) return definition.insertText;
    if (!['function','method'].includes(definition.kind)) return definition.name;
    const parameters=(definition.parameters||[]).filter(p=>!p.optional);
    return definition.name+'('+parameters.map((p,i)=>'${'+(i+1)+':'+p.name.replace(/^\.\.\./,'').replace(/[{}$]/g,'')+'}').join(', ')+')';
  }
  function callContext(source) {
    // Track real delimiters, respecting quotes and comments rather than splitting at every comma.
    const stack=[];let quote=null,escaped=false,lineComment=false,longDelimiter=null;
    for (let i=0;i<source.length;i++) {
      const c=source[i];
      if (lineComment) {if(c==='\n')lineComment=false;continue;}
      if (longDelimiter) {if(source.startsWith(longDelimiter,i)){i+=longDelimiter.length-1;longDelimiter=null;}continue;}
      if (quote) {if(escaped){escaped=false;continue;}if(c==='\\'){escaped=true;continue;}if(c===quote)quote=null;continue;}
      if(source.startsWith('--',i)){const long=/^--\[(=*)\[/.exec(source.slice(i));if(long){longDelimiter=']'+long[1]+']';i+=long[0].length-1;}else lineComment=true;continue;}
      if(c==='[') {
        const long=/^\[(=*)\[/.exec(source.slice(i));if(long){longDelimiter=']'+long[1]+']';i+=long[0].length-1;continue;}
      }
      if(c==='"'||c==="'"||c==='`'){quote=c;continue;}
      if(c==='('||c==='{'||c==='[')stack.push({start:i,kind:c,argument:0});
      else if(c===')'||c==='}'||c===']')stack.pop();
      else if(c===','&&stack.length)stack[stack.length-1].argument++;
    }
    const call=[...stack].reverse().find(item=>item.kind==='(');
    if(!call)return null;
    const match=/([A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*)\s*$/.exec(source.slice(0,call.start));
    return match?{expression:match[1],argument:call.argument}:null;
  }
  const syntaxStates = new WeakMap();
  function setSyntaxProfile(monaco, profile) {
    const state=syntaxStates.get(monaco);if(!state)return;
    const selected=['originalKrnl','originalZenith'].includes(profile)?profile:'';
    if(state.profile===selected)return;
    let definition=state.base;
    if(selected) {
      const rootRules=state.base.tokenizer.root.map(row=>{
        if(row[1]&&typeof row[1]==='object'&&row[1].cases&&row[1].cases['@keywords']) {
          const cases=selected==='originalKrnl'
            ? {'@keywords':'keyword','@krnlBuiltins':'builtin','@typeKeywords':'type','@default':'identifier'}
            : {...row[1].cases,'@keywords':{token:'keyword.$0'}};
          return [row[0],{cases}];
        }
        if(selected==='originalZenith'&&row[1]==='operator')return [row[0],'delimiter'];
        if(selected==='originalKrnl'&&row[1]==='@brackets')return [row[0],'delimiter'];
        return row;
      });
      definition={...state.base,tokenizer:{...state.base.tokenizer,root:rootRules}};
      if(selected==='originalKrnl')definition.krnlBuiltins=['warn','print','loadstring','game','workspace','wait','spawn','pairs','ipairs','require','typeof','tostring','tonumber','pcall','xpcall','getgenv','getgc','identifyexecutor'];
      if(selected==='originalZenith')definition.brackets=[
        {token:'delimiter.bracket',open:'{',close:'}'},
        {token:'delimiter.array',open:'[',close:']'},
        {token:'delimiter.parenthesis',open:'(',close:')'},
      ];
    }
    state.provider?.dispose();
    state.provider=monaco.languages.setMonarchTokensProvider('luau',definition);
    state.profile=selected;
  }
  function register(monaco,api) {
    const catalog=createCatalog(api),language='luau',Kind=monaco.languages.CompletionItemKind;
    monaco.languages.register({id:language,extensions:['.luau','.lua'],aliases:['Luau','luau']});
    monaco.languages.setLanguageConfiguration(language,{
      comments:{lineComment:'--',blockComment:['--[[',']]']},brackets:[['{','}'],['[',']'],['(',')']],
      autoClosingPairs:[{open:'{',close:'}'},{open:'[',close:']'},{open:'(',close:')'},{open:'"',close:'"',notIn:['string','comment']},{open:"'",close:"'",notIn:['string','comment']},{open:'`',close:'`',notIn:['string','comment']}],
      surroundingPairs:[{open:'(',close:')'},{open:'[',close:']'},{open:'{',close:'}'},{open:'"',close:'"'},{open:"'",close:"'"},{open:'`',close:'`'}],
      // Increase only for open block headers or a bracket at the end of a line.
      // Balanced ordinary calls (print(...), math.clamp(...)) do not open a new block.
      indentationRules:{
        increaseIndentPattern:/^\s*(?!--)(?:.*\b(?:then|do)\s*(?:--.*)?|(?:repeat|else)\s*(?:--.*)?|.*\bfunction(?:\s+[A-Za-z_][\w.:]*)?(?:<[^>]+>)?\s*\(.*\)\s*(?::\s*[^-]+)?\s*(?:--.*)?|.*[({\[]\s*(?:--.*)?)$/,
        decreaseIndentPattern:/^\s*(?:end\b|else\b|elseif\b|until\b|[})\]])/,
      },
      folding:{markers:{start:/^\s*--\s*#?region\b/,end:/^\s*--\s*#?endregion\b/}},
      wordPattern:/[A-Za-z_]\w*/,
    });
    const syntaxDefinition={
      defaultToken:'',tokenPostfix:'.luau',keywords,typeKeywords:primitiveTypes,
      tokenizer:{root:[[/--\[(=*)\[/,{token:'comment',next:'@longcomment.$1'}],[/--.*$/,'comment'],[/\[(=*)\[/,{token:'string',next:'@longstring.$1'}],
        [/"/,{token:'string.quote',next:'@double'}],[/'/,{token:'string.quote',next:'@single'}],[/`/,{token:'string.quote',next:'@interpolated'}],
        [/\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?[\d_]+)?)\b/,'number'],
        [/[A-Za-z_]\w*/,{cases:{'@keywords':'keyword','@typeKeywords':'type','@default':'identifier'}}],
        [/[{}()[\]]/,'@brackets'],[/[+\-*\/%^#=<>~?:|&]+/,'operator'],[/[;,.]/,'delimiter'],[/\s+/,'white']],
        longcomment:[[/\](=*)\]/,{cases:{'$1==$S2':{token:'comment',next:'@pop'},'@default':'comment'}}],[/./,'comment']],
        longstring:[[/\](=*)\]/,{cases:{'$1==$S2':{token:'string',next:'@pop'},'@default':'string'}}],[/./,'string']],
        double:[[/[^\\"]+/,'string'],[/\\./,'string.escape'],[/"/,{token:'string.quote',next:'@pop'}]],
        single:[[/[^\\']+/,'string'],[/\\./,'string.escape'],[/'/,{token:'string.quote',next:'@pop'}]],
        interpolated:[[/[^\\`{]+/,'string'],[/\\./,'string.escape'],[/\{[^}]*\}/,'string.interpolation'],[/`/,{token:'string.quote',next:'@pop'}]],
      }
    };
    const syntaxProvider=monaco.languages.setMonarchTokensProvider(language,syntaxDefinition);
    syntaxStates.set(monaco,{base:syntaxDefinition,provider:syntaxProvider,profile:''});
    // Monaco versions are monotonic across edits and undo. Keep one analysis
    // per live model/version so completion and hover share the same snapshot;
    // WeakMap entries disappear with closed tabs rather than retaining scripts.
    const analyses=new WeakMap();
    function analysis(model) {
      const version=typeof model.getVersionId==='function'?model.getVersionId():null;
      let result=analyses.get(model);
      if(version==null || !result || result.version!==version) {
        result={version,text:model.getValue(),symbols:null};analyses.set(model,result);
      }
      return result;
    }
    function symbolsFor(snapshot) {
      return snapshot.symbols||(snapshot.symbols=catalog.declarations(snapshot.text));
    }
    const kindMap={keyword:Kind.Keyword,type:Kind.TypeParameter,module:Kind.Module,class:Kind.Class,variable:Kind.Variable,property:Kind.Property,function:Kind.Function,method:Kind.Method,event:Kind.Event,callback:Kind.Function,enum:Kind.Enum,enumMember:Kind.EnumMember,snippet:Kind.Snippet};
    monaco.languages.registerCompletionItemProvider(language,{triggerCharacters:['.',':','"',"'"],provideCompletionItems(model,position){
      const before=model.getLineContent(position.lineNumber).slice(0,position.column-1),word=model.getWordUntilPosition(position),snapshot=analysis(model);
      return {suggestions:catalog.complete(snapshot.text,before,symbolsFor(snapshot)).map(item=>({
        label:item.name,kind:kindMap[item.kind]??Kind.Text,detail:['function','method'].includes(item.kind)?signature(item):(item.type||item.owner||'Luau'),
        documentation:{value:item.summary||''},insertText:snippet(item),insertTextRules:['function','method','snippet'].includes(item.kind)?monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet:undefined,
        filterText:item.name,sortText:(item.kind==='snippet'?'2_':item.kind==='variable'?'0_':'1_')+item.name,
        tags:item.deprecated?[monaco.languages.CompletionItemTag.Deprecated]:undefined,
        range:{startLineNumber:position.lineNumber,endLineNumber:position.lineNumber,startColumn:item.replaceLength!=null?position.column-item.replaceLength:word.startColumn,endColumn:position.column},
      }))};
    }});
    monaco.languages.registerSignatureHelpProvider(language,{signatureHelpTriggerCharacters:['(',','],signatureHelpRetriggerCharacters:[')'],provideSignatureHelp(model,position){
      const text=model.getValueInRange({startLineNumber:1,startColumn:1,endLineNumber:position.lineNumber,endColumn:position.column}),ctx=callContext(text);
      if(!ctx)return null;
      const def=catalog.definition(text,ctx.expression);if(!def||!def.parameters)return null;
      return {value:{signatures:[{label:signature(def),documentation:{value:def.summary||''},parameters:def.parameters.map(p=>({label:`${p.name}: ${p.type}`,documentation:p.summary||''}))}],activeSignature:0,activeParameter:Math.min(ctx.argument,Math.max(0,def.parameters.length-1))},dispose(){}};
    }});
    monaco.languages.registerHoverProvider(language,{provideHover(model,position){
      const word=model.getWordAtPosition(position);if(!word)return null;
      const line=model.getLineContent(position.lineNumber),prefix=line.slice(0,word.endColumn-1),snapshot=analysis(model),symbols=symbolsFor(snapshot),ctx=catalog.context(snapshot.text,prefix,symbols);
      const expression=ctx.member?ctx.member+ctx.separator+word.word:word.word;
      const def=catalog.definition(snapshot.text,expression,symbols)||catalog.complete(snapshot.text,prefix,symbols).find(row=>row.name===word.word);
      if(!def)return null;
      return {range:{startLineNumber:position.lineNumber,endLineNumber:position.lineNumber,startColumn:word.startColumn,endColumn:word.endColumn},contents:[{value:'```luau\n'+(def.parameters?signature(def):def.name+(def.type?': '+def.type:''))+'\n```'},{value:def.summary||''}]};
    }});
    return catalog;
  }
  root.OrionLuau={createCatalog,register,setSyntaxProfile,signature,snippet,callContext,keywords};
  if(typeof module!=='undefined'&&module.exports)module.exports=root.OrionLuau;
})(typeof window!=='undefined'?window:globalThis);
