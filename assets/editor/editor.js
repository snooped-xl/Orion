(function () {
  'use strict';
  let editor = null, activeId = null, muted = false, lastOptions = '', lastTheme = '';
  const documents = new Map(), pending = [];
  let diagnosticsEnabled = false, diagnosticsTimer = null, diagnosticsModel = null;
  const clearedDiagnostics = new WeakSet();
  let currentShell = '', showEditorHints = true, lastKrnlGutter = 0;
  let currentCompositorGlass = false, interactionQueued = false;
  let sharedWindowBackdrop = null, backdropGeometry = null, backdropImage = null;
  let lastCursor = null;
  let studioImages = null;
  let layoutQueued = false, repaintRequested = false, fontMeasurementRequested = false;
  function layoutEditor(repaint = false) {
    repaintRequested = repaintRequested || repaint;
    if (!editor || typeof editor.layout !== 'function' || layoutQueued) return;
    layoutQueued = true;
    requestAnimationFrame(() => {
      layoutQueued = false;
      const node = document.getElementById('editor');
      // A native WebView can be unmapped without changing its DOM size. Do
      // not teach Monaco a zero viewport while hidden; repaint when remapped.
      if (!node || node.clientWidth <= 0 || node.clientHeight <= 0 || document.hidden) return;
      if (fontMeasurementRequested) {monaco.editor.remeasureFonts();fontMeasurementRequested = false;}
      editor.layout({width:node.clientWidth,height:node.clientHeight});
      if (repaintRequested && typeof editor.render === 'function') editor.render(true);
      repaintRequested = false;
      frameInteraction();
    });
  }
  window.orionLayout = () => layoutEditor(true);
  addEventListener('pageshow', () => layoutEditor(true));
  if (document.addEventListener) document.addEventListener('visibilitychange', () => {
    if (!document.hidden) layoutEditor(true);
  });
  const hexColor = color => typeof color === 'string' && /^#[0-9a-f]{6}$/i.test(color);
  // Fallback glass paints an opaque window-coordinate substrate. Real
  // compositor glass instead exports clean alpha snapshots to Flutter. Keep
  // alpha formats local to these backdrops; source palettes stay opaque.
  const backdropColor = color => typeof color === 'string' && /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(color);
  function completionPalette({light,glass,surface,foreground,accent,muted}) {
    const rgb=color=>[1,3,5].map(offset=>parseInt(color.slice(offset,offset+2),16));
    const blend=(base,tint,amount)=>'#'+rgb(base).map((value,index)=>Math.round(value+(rgb(tint)[index]-value)*amount).toString(16).padStart(2,'0')).join('');
    const luminance=color=>rgb(color).map(value=>{value/=255;return value<=.04045?value/12.92:((value+.055)/1.055)**2.4;})
      .reduce((sum,value,index)=>sum+value*[.2126,.7152,.0722][index],0);
    const contrast=(a,b)=>{const first=luminance(a),second=luminance(b);return (Math.max(first,second)+.05)/(Math.min(first,second)+.05);};
    const safe=(color,fallback)=>hexColor(color)?color:fallback;
    const base=safe(surface,light?'#FFFFFF':'#1C2635');
    const ink=safe(foreground,light?'#1A2535':'#E7EDF7'),tint=safe(accent,light?'#175FCB':'#A8C7FA');
    const panel=base,opacity=light?.82:.74;
    const alpha=(color,value)=>`${color}${Math.round(value*255).toString(16).padStart(2,'0')}`;
    // Glass inherits the selected theme and keeps real alpha in the Flutter
    // mirror. Protect labels against both bright and dark desktop backdrops.
    const surfaces=glass?[panel,blend('#FFFFFF',panel,opacity),blend('#000000',panel,opacity)]:[panel];
    const minimumContrast=color=>Math.min(...surfaces.map(surface=>contrast(color,surface)));
    const strongest=minimumContrast('#FFFFFF')>minimumContrast('#000000')?'#FFFFFF':'#000000';
    const readable=(color,minimum=4.5)=>{
      color=safe(color,strongest);
      for(let step=0;step<10 && minimumContrast(color)<minimum;step++)color=blend(color,strongest,.18);
      return minimumContrast(color)>=minimum?color:strongest;
    };
    const text=readable(ink);
    return {
      surface:glass?alpha(panel,opacity):panel,
      foreground:text,muted:readable(muted),highlight:readable(tint),
      selected:glass?alpha(tint,light?.12:.16):blend(panel,tint,light?.13:.18),
      hover:glass?alpha(tint,.065):blend(panel,tint,.065),
      rim:glass?alpha(blend(text,tint,.4),light?.25:.28):blend(panel,text,light?.16:.15),
      shadow:light?'#14223818':'#03081130',
    };
  }
  function applyWindowBackdrop() {
    const root=document.documentElement,backdrop=sharedWindowBackdrop,geometry=backdropGeometry;
    root.classList.toggle('orion-window-backdrop',Boolean(backdrop));
    if(!backdrop)return;
    root.style.setProperty('--window-backdrop-color',backdrop.color);
    let image='none';
    const cached=backdropImage && backdropImage.backdrop===backdrop && geometry &&
      backdropImage.width===geometry.width && backdropImage.height===geometry.height;
    if(cached)image=backdropImage.image;
    else if(geometry && backdrop.gradient) {
      const {width,height}=geometry,gradient=backdrop.gradient;
      const point=alignment=>[(alignment[0]+1)*width/2,(alignment[1]+1)*height/2];
      const [x1,y1]=point(gradient.begin),[x2,y2]=point(gradient.end);
      const stops=spec=>spec.colors.map((color,index)=>`<stop offset="${spec.stops[index]}" stop-color="${color}"/>`).join('');
      const lights=(backdrop.radials||[]).map((light,index)=>{
        const [cx,cy]=point(light.center),radius=light.radius*Math.min(width,height);
        return `<radialGradient id="light${index}" gradientUnits="userSpaceOnUse" cx="${cx}" cy="${cy}" r="${radius}">${stops(light)}</radialGradient>`;
      }).join('');
      const lightRects=(backdrop.radials||[]).map((_,index)=>`<rect width="100%" height="100%" fill="url(#light${index})"/>`).join('');
      // This is the shell's one backdrop in window coordinates, shared across
      // GTK surfaces. It never restarts at the editor's top-left corner.
      const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><defs><linearGradient id="window" gradientUnits="userSpaceOnUse" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops(gradient)}</linearGradient>${lights}</defs><g opacity="${backdrop.opacity}"><rect width="100%" height="100%" fill="url(#window)"/>${lightRects}</g></svg>`;
      image=`url("data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}")`;
      backdropImage={backdrop,width,height,image};
    }
    root.style.setProperty('--window-backdrop-image',image);
    if(geometry) {
      root.style.setProperty('--window-backdrop-size',`${geometry.width}px ${geometry.height}px`);
      root.style.setProperty('--window-backdrop-position',`${-geometry.x}px ${-geometry.y}px`);
    }
  }
  window.orionSetBackdropGeometry=function(geometry) {
    if(!geometry || !['x','y','width','height'].every(key=>Number.isFinite(geometry[key]) && Math.abs(geometry[key])<=100000) || geometry.width<=0 || geometry.height<=0)return;
    if(backdropGeometry && ['x','y','width','height'].every(key=>backdropGeometry[key]===geometry[key]))return;
    backdropGeometry={x:geometry.x,y:geometry.y,width:geometry.width,height:geometry.height};
    applyWindowBackdrop();
    applyStudioImages();
  };
  // WebKit is a separate native surface above Flutter. Reproduce image layers
  // in window coordinates so the same backdrop continues through Monaco.
  function applyStudioImages() {
    for(const [key,id] of [['background','studio-background'],['overlay','studio-overlay']]) {
      const spec=studioImages && studioImages[key];
      let layer=document.getElementById(id);
      if(!spec) {if(layer)layer.remove();continue;}
      if(!layer) {
        layer=document.createElement('div');layer.id=id;layer.setAttribute('aria-hidden','true');
        const image=document.createElement('img');image.alt='';image.draggable=false;layer.append(image);
        document.body.append(layer);
      }
      const image=layer.firstChild,region=spec.region;
      const geometry=spec.local?null:region && backdropGeometry?{
        x:backdropGeometry.x-region.x,y:backdropGeometry.y-region.y,width:region.width,height:region.height,
      }:backdropGeometry;
      if(image.getAttribute('src')!==spec.data)image.src=spec.data;
      layer.style.opacity=String(spec.layerOpacity??1);
      layer.style.backgroundColor=spec.fill||'';
      image.style.opacity=String(spec.opacity);
      image.style.left=geometry?`${-geometry.x}px`:'0';image.style.top=geometry?`${-geometry.y}px`:'0';
      image.style.width=geometry?`${geometry.width}px`:'100%';image.style.height=geometry?`${geometry.height}px`:'100%';
      image.style.objectFit=['contain','cover','fill','none','scale-down'].includes(spec.fit)?spec.fit:'contain';
      // Flutter's fitWidth/fitHeight keep the original aspect ratio, anchored
      // centrally. CSS contain covers the remaining standard fit modes.
      if(spec.fit==='fitWidth'||spec.fit==='fitHeight') {
        image.style.objectFit='fill';
        const resize=()=>{
          if(!image.naturalWidth||!image.naturalHeight)return;
          const w=geometry?geometry.width:innerWidth,h=geometry?geometry.height:innerHeight;
          const ratio=spec.fit==='fitWidth'?w/image.naturalWidth:h/image.naturalHeight;
          image.style.width=`${image.naturalWidth*ratio}px`;image.style.height=`${image.naturalHeight*ratio}px`;
          image.style.left=`${(w-image.naturalWidth*ratio)/2-(geometry?geometry.x:0)}px`;
          image.style.top=`${(h-image.naturalHeight*ratio)/2-(geometry?geometry.y:0)}px`;
        };
        image.onload=resize;resize();
      } else image.onload=null;
    }
  }
  function studioImage(data,opacity,fit,local) {
    if(typeof data!=='string'||data.length>12*1024*1024||!/^data:image\/(png|jpeg|webp);base64,[a-z0-9+/=]+$/i.test(data))return null;
    return {data,opacity:Number.isFinite(opacity)?Math.max(0,Math.min(1,opacity)):1,fit:fit==='scaleDown'?'scale-down':fit,local};
  }
  addEventListener('resize',applyStudioImages);
  function windowBackdrop(options,enabled,opaque=false) {
    const backdrop=options.windowBackdrop;
    if(!enabled || !backdrop || !backdropColor(backdrop.color))return null;
    const result={color:opaque?backdrop.color.slice(0,7):backdrop.color,gradient:null,radials:[],opacity:opaque?1:Number.isFinite(backdrop.opacity)?Math.max(0,Math.min(1,backdrop.opacity)):1},gradient=backdrop.gradient;
    const alignment=value=>Array.isArray(value) && value.length===2 && value.every(number=>Number.isFinite(number) && Math.abs(number)<=10);
    const colorStops=spec=>{
      if(!spec || !Array.isArray(spec.colors) || spec.colors.length<2 || spec.colors.length>4 || !spec.colors.every(backdropColor))return null;
      const stops=Array.isArray(spec.stops) && spec.stops.length===spec.colors.length && spec.stops.every((stop,index)=>Number.isFinite(stop) && stop>=0 && stop<=1 && (index===0 || stop>=spec.stops[index-1]))?spec.stops:spec.colors.map((_,index)=>index/(spec.colors.length-1));
      return {colors:spec.colors,stops};
    };
    const linear=colorStops(gradient);
    if(linear && alignment(gradient.begin) && alignment(gradient.end)) {
      result.gradient={...linear,colors:opaque?linear.colors.map(color=>color.slice(0,7)):linear.colors,begin:gradient.begin,end:gradient.end};
      if(Array.isArray(backdrop.radials))for(const light of backdrop.radials.slice(0,4)) {
        const colors=colorStops(light);
        if(colors && alignment(light.center) && Number.isFinite(light.radius) && light.radius>0 && light.radius<=5)
          result.radials.push({...colors,center:light.center,radius:light.radius});
      }
    }
    return result;
  }
  function updateOriginalHint() {
    const hint = document.getElementById('zenith-editor-hint');
    if (!hint) return;
    if(currentShell !== 'originalZenith' || !showEditorHints) {hint.hidden=true;return;}
    const model = editor && editor.getModel(), value = model ? model.getValue().trim() : '';
    hint.hidden = value !== '' && value !== '-- Loading... --';
  }
  function krnlGutter() {
    const model = editor && editor.getModel();
    const lines = model ? (typeof model.getLineCount === 'function' ? model.getLineCount() : model.getValue().split('\n').length) : 1;
    const digits = String(Math.max(1, lines)).length;
    // Source RichTextBox number margin: Consolas8pt(digits+1), plus5px, min15px.
    const width = Math.max(15, Math.ceil((digits + 1) * (32 / 3) * .6 + 5));
    return {width, decorations: Math.max(0, width - Math.ceil(digits * (40 / 3) * .6))};
  }
  function refreshOriginalGutter() {
    if (!editor || currentShell !== 'originalKrnl') return;
    const gutter = krnlGutter();
    if (gutter.width === lastKrnlGutter) return;
    lastKrnlGutter = gutter.width;
    document.documentElement.style.setProperty('--krnl-gutter-width', gutter.width + 'px');
    editor.updateOptions({lineDecorationsWidth:gutter.decorations});
  }
  function originalTheme(shell, background) {
    if (shell === 'originalKrnl') return {base:'vs-dark',inherit:false,rules:[
      {token:'',foreground:'FFFFFF'}, {token:'comment',foreground:'4F5162'},
      {token:'keyword',foreground:'FF3C7A'}, {token:'builtin',foreground:'59FFAC',fontStyle:'bold'},
      {token:'number',foreground:'A570FF'}, {token:'string',foreground:'FFC073'},
      {token:'string.escape',foreground:'FFC073'}, {token:'operator',foreground:'FFFFFF'},
      {token:'delimiter',foreground:'FFFFFF'},
    ],colors:{'editor.background':'#282828','editor.foreground':'#FFFFFF','editorGutter.background':'#282828',
      'editorLineNumber.foreground':'#BEBEBE','editorLineNumber.activeForeground':'#BEBEBE',
      'editor.selectionBackground':'#0078D7','editor.inactiveSelectionBackground':'#0078D7',
      'editor.selectionForeground':'#FFFFFF','editor.lineHighlightBackground':'#00000000',
      'editor.lineHighlightBorder':'#00000000','editorCursor.foreground':'#FFFFFF',
      'scrollbar.shadow':'#00000000'}};
    if (shell === 'originalZenith') return {base:'vs-dark',inherit:true,rules:[
      {token:'',foreground:'D4D4D4'}, {token:'variable.language.self',foreground:'A9A0A0'},
      {token:'variable.parameter',foreground:'A9A0A0'}, {token:'variable',foreground:'A9A0A0'},
      {token:'variable.property',foreground:'9CDCFE'}, {token:'keyword',foreground:'4CC2F7'},
      {token:'keyword.local',foreground:'C678DD',fontStyle:'bold'}, {token:'keyword.operator',foreground:'4CC2F7'},
      {token:'operator',foreground:'D4D4D4'}, {token:'function',foreground:'DCDCAA'},
      {token:'entity.name.function',foreground:'DCDCAA'}, {token:'global',foreground:'39A2FF',fontStyle:'bold'},
      {token:'comment',foreground:'ABB2BF',fontStyle:'bold'}, {token:'delimiter',foreground:'9A9A9A'},
      {token:'delimiter.bracket',foreground:'808080'}, {token:'string',foreground:'63F499'},
      {token:'string.escape',foreground:'63F499'}, {token:'number',foreground:'E5C07B'},
      {token:'constant',foreground:'39A2FF'}, {token:'support.function',foreground:'39A2FF'},
      {token:'support.type',foreground:'39A2FF'},
    ],colors:{'editor.background':background,'editor.foreground':'#D4D4D4',
      'editor.selectionBackground':'#3A3D41','editor.inactiveSelectionBackground':'#3A3D4188',
      'editor.lineHighlightBackground':'#14141411','editor.lineHighlightBorder':'#00000000',
      'editorLineNumber.foreground':'#FFFFFF','editorLineNumber.activeForeground':'#FFFFFF',
      'editorCursor.foreground':'#D4D4D4','editorGutter.background':background,'editorPane.background':background,
      'minimap.background':background,'editorWidget.background':'#111111','editorWidget.border':'#3A3B3C',
      'editorSuggestWidget.background':'#111111','editorSuggestWidget.border':'#3A3B3C',
      'editorSuggestWidget.foreground':'#FFFFFF','editorSuggestWidget.selectedBackground':'#3A3D41',
      'editorSuggestWidget.highlightForeground':'#39A2FF','editorHoverWidget.background':'#111111',
      'editorHoverWidget.border':'#3A3B3C','scrollbar.shadow':'#00000000','scrollbarSlider.background':'#3A3A3A',
      'scrollbarSlider.hoverBackground':'#4A4A4A','scrollbarSlider.activeBackground':'#5A5A5A',
      'editorBracketHighlight.foreground1':'#808080','editorBracketHighlight.foreground2':'#808080',
      'editorBracketHighlight.foreground3':'#808080','editorBracketPairGuide.background1':'#80808040',
      'editorBracketPairGuide.activeBackground1':'#808080'}};
    return {base:'vs-dark',inherit:false,rules:[
      {token:'',foreground:'D4D4D4'}, {token:'comment',foreground:'6A9955',fontStyle:'italic'},
      {token:'keyword',foreground:'569CD6'}, {token:'keyword.control',foreground:'C586C0'},
      {token:'string',foreground:'CE9178'}, {token:'string.escape',foreground:'D7BA7D'},
      {token:'number',foreground:'B5CEA8'}, {token:'regexp',foreground:'D16969'},
      {token:'operator',foreground:'D4D4D4'}, {token:'namespace',foreground:'4EC9B0'},
      {token:'type',foreground:'4EC9B0'}, {token:'struct',foreground:'4EC9B0'}, {token:'class',foreground:'4EC9B0'},
      {token:'interface',foreground:'4EC9B0'}, {token:'enum',foreground:'4EC9B0'}, {token:'type.parameter',foreground:'4EC9B0'},
      {token:'function',foreground:'DCDCAA'}, {token:'method',foreground:'DCDCAA'}, {token:'variable',foreground:'9CDCFE'},
      {token:'variable.predefined',foreground:'4FC1FF'}, {token:'constant',foreground:'4FC1FF'},
      {token:'tag',foreground:'569CD6'}, {token:'attribute.name',foreground:'9CDCFE'}, {token:'attribute.value',foreground:'CE9178'},
    ],colors:{'editor.background':background,'editor.foreground':'#D4D4D4',
      'editor.lineHighlightBackground':shell==='originalAwp'?'#00000000':'#171717',
      'editor.lineHighlightBorder':'#00000000','editor.selectionBackground':'#264F78',
      'editor.inactiveSelectionBackground':'#3A3D41','editor.selectionHighlightBackground':'#ADD6FF26',
      'editor.findMatchBackground':'#515C6A','editor.findMatchHighlightBackground':'#EA5C0055',
      'editor.hoverHighlightBackground':'#264F7833','editor.wordHighlightBackground':'#575757B8',
      'editor.wordHighlightStrongBackground':'#004972B8','editorCursor.foreground':'#AEAFAD',
      'editorWhitespace.foreground':'#404040','editorLineNumber.foreground':'#858585',
      'editorLineNumber.activeForeground':'#C6C6C6','editorIndentGuide.background1':'#404040',
      'editorIndentGuide.activeBackground1':'#707070','editorGutter.background':background,
      'editorPane.background':background,'minimap.background':background,'scrollbar.shadow':'#00000000',
      'scrollbarSlider.background':'#79797966','scrollbarSlider.hoverBackground':'#646464B3',
      'scrollbarSlider.activeBackground':'#BFBFBF66'}};
  }
  function refreshDiagnostics() {
    if (!editor) return;
    const model = editor.getModel();
    if (!model) return;
    if (!diagnosticsEnabled) {
      // Error logging is retired. Clear each model once rather than waking a
      // timer and rebuilding every open tab's marker/decorations after typing.
      if(!clearedDiagnostics.has(model)) {
        monaco.editor.setModelMarkers(model,'Synapse',[]);clearedDiagnostics.add(model);
      }
      if(diagnosticsModel!==model && window.OrionSynapseDiagnostics)
        OrionSynapseDiagnostics.updateEditorDecorations(editor,[]);
      diagnosticsModel=model;
      return;
    }
    if (!window.OrionSynapseDiagnostics) return;
    const markers=OrionSynapseDiagnostics.getLuaDiagnostics(model.getValue());
    monaco.editor.setModelMarkers(model,'Synapse',markers);
    OrionSynapseDiagnostics.updateEditorDecorations(editor,markers);
    clearedDiagnostics.delete(model);diagnosticsModel=model;
  }
  function scheduleDiagnostics() {
    if(!diagnosticsEnabled)return;
    clearTimeout(diagnosticsTimer);
    diagnosticsTimer = setTimeout(refreshDiagnostics, 150);
  }
  function post(message) {
    try {
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.orion;
      if (handler) handler.postMessage(JSON.stringify(message));
      else if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(JSON.stringify(message));
      else window.dispatchEvent(new CustomEvent('orion-message', { detail: message }));
    } catch (error) { console.error('Orion editor bridge:', error); }
  }
  function postCursor(position) {
    if(!position)return;
    const {lineNumber:line,column}=position;
    if(lastCursor && lastCursor.id===activeId && lastCursor.line===line && lastCursor.column===column)return;
    lastCursor={id:activeId,line,column};post({type:'cursor',line,column});
  }
  function frameInteraction() {
    if(!currentCompositorGlass || interactionQueued)return;
    interactionQueued=true;
    // Native input does not pass through Flutter's pointer listeners. Batch
    // these hints; the mirror service owns the bounded snapshot cadence.
    setTimeout(()=>{interactionQueued=false;if(currentCompositorGlass)post({type:'interaction'});},40);
  }
  function report(error) {
    const message=error && error.message ? error.message : String(error);
    const loading=document.getElementById('loading');loading.textContent='Editor could not load';
    post({type:'error',message});console.error(error);
  }
  window.addEventListener('error', event => post({type:'error',message:event.message}));
  window.addEventListener('unhandledrejection', event => post({type:'error',message:String(event.reason)}));
  window.MonacoEnvironment = {getWorkerUrl(_moduleId, _label) {
    return new URL('./vs/assets/editor.worker-_vAIFJDs.js', window.location.href).href;
  }};
  require.config({paths:{vs:new URL('./vs',window.location.href).href}});
  require.onError=report;
  function updateOptions(options) {
    const value=JSON.stringify(options || {});if(value===lastOptions)return;lastOptions=value;
    options=options||{};
    const palette=options.palette || {},shell=options.shell || '',v3=shell==='synapseV3',x=shell==='synapseX',og=shell==='synapseOriginal',blue=shell==='synapseBlue',synapse=v3||x||og||blue,light=options.brightness==='light';
    const awp=shell==='originalAwp',xeno=shell==='originalXeno',krnl=shell==='originalKrnl',zenith=shell==='originalZenith',original=awp||xeno||krnl||zenith;
    currentShell=shell;showEditorHints=options.showEditorHints!==false;
    document.documentElement.classList.toggle('original-port',original);
    document.documentElement.classList.toggle('original-krnl',krnl);
    document.documentElement.classList.toggle('original-zenith',zenith);
    if (OrionLuau.setSyntaxProfile) OrionLuau.setSyntaxProfile(monaco,shell);
    const editorThemeId=options.editorThemeId || (x?'net-theme-dark':og?'og-2017-custom':blue?'tomorrow-night-eighties':'');
    document.documentElement.classList.toggle('synapse-v3', synapse);
    diagnosticsEnabled = false;
    const orion=shell==='orion',mainOrion=orion || shell==='',studio=(synapse||orion) && options.studioEditorEnabled===true;
    document.documentElement.classList.toggle('orion-main',mainOrion);
    document.documentElement.classList.toggle('orion-reduced-motion',options.reducedMotion===true);
    const glass=orion && options.glassEnabled===true;
    const compositorGlass=glass && options.compositorGlass===true;
    if(compositorGlass!==currentCompositorGlass) {
      currentCompositorGlass=compositorGlass;
      if(compositorGlass)post({type:'focus',focused:Boolean(editor && editor.hasWidgetFocus && editor.hasWidgetFocus())});
    }
    document.documentElement.classList.toggle('orion-compositor-glass',compositorGlass);
    document.documentElement.classList.toggle('orion-glass',glass);
    document.documentElement.style.setProperty('--glass-tint',glass && backdropColor(options.glassTint)?options.glassTint:'#00000000');
    // Window-level opacity supplies desktop translucency. The software WebKit
    // canvas itself must repaint opaquely, without framebuffer backdrop reads.
    document.documentElement.style.setProperty('--glass-material-opacity','1');
    document.documentElement.classList.toggle('orion-studio',studio && orion);
    document.documentElement.style.setProperty('--studio-backdrop',studio && hexColor(options.studioWindowBackground)?options.studioWindowBackground:'#202020');
    studioImages=studio && !compositorGlass?{
      background:(()=>{
        const image=studioImage(options.studioBackgroundImage,options.studioBackgroundOpacity,options.studioBackgroundFit,options.studioBackgroundLocal===true);
        if(image && orion) {
          image.layerOpacity=Number.isFinite(options.studioBackgroundLayerOpacity)?Math.max(0,Math.min(1,options.studioBackgroundLayerOpacity)):1;
          image.fill=typeof options.studioBackgroundFill==='string' && /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(options.studioBackgroundFill)?options.studioBackgroundFill:null;
          const region=options.studioBackgroundRegion;
          image.region=region && ['x','y','width','height'].every(key=>Number.isFinite(region[key]) && Math.abs(region[key])<=100000) && region.width>0 && region.height>0?region:null;
        }
        return image;
      })(),
      overlay:studioImage(options.studioOverlayImage,options.studioOverlayOpacity,options.studioOverlayFit,false),
    }:null;
    applyStudioImages();
    document.documentElement.classList.toggle('synapse-studio',studio);
    const editorNode=document.getElementById('editor');
    editorNode.style.opacity=studio && Number.isFinite(options.studioEditorOpacity)?String(Math.max(0,Math.min(1,options.studioEditorOpacity))):'';
    editorNode.style.pointerEvents=studio && options.studioEditorOpacity===0?'none':'';
    const radius=glass && Number.isFinite(options.glassEditorRadius)?Math.max(0,Math.min(256,options.glassEditorRadius)):studio && Number.isFinite(options.studioEditorRadius)?Math.max(0,Math.min(256,options.studioEditorRadius)):0;
    // Keep Glass's native canvas opaque even outside the curved foreground.
    // Cutting holes in the WebKit root exposes a software GTK matte at the
    // corners. Its window-aligned base instead continues through those pixels;
    // only code/widgets and the rounded optical rim need the pane's mask.
    document.documentElement.style.clipPath=!glass && radius?`inset(0 round ${radius}px)`:'';
    editorNode.style.clipPath=glass && radius?`inset(0 round ${radius}px)`:'';
    document.documentElement.style.setProperty('--glass-radius',`${radius}px`);
    const background=options.background || palette.background || (light?'#F4F6FB':'#141A23');
    const foreground=options.foreground || palette.foreground || (light?'#1A2535':'#E7EDF7');
    const accent=options.accent || palette.accent || (light?'#175FCB':'#A8C7FA');
    const mutedColor=options.muted || palette.muted || (light?'#68758A':'#8C9CB4'),border=options.border || palette.border || (light?'#D8DEEA':'#303D50');
    const surface=options.surface || (light?'#FFFFFF':'#1C2635');
    const materialAccent=!synapse && !original && /^#[0-9a-f]{6}$/i.test(accent);
    const accentLayer=alpha=>`${accent}${Math.round(alpha*255).toString(16).padStart(2,'0')}`;
    const mutedLayer=alpha=>`${/^#[0-9a-f]{6}$/i.test(mutedColor)?mutedColor:(light?'#68758A':'#8C9CB4')}${Math.round(alpha*255).toString(16).padStart(2,'0')}`;
    const accentLuminance=materialAccent?[1,3,5].map(offset=>parseInt(accent.slice(offset,offset+2),16)/255)
      .map(channel=>channel<=.04045?channel/12.92:((channel+.055)/1.055)**2.4)
      .reduce((sum,channel,index)=>sum+channel*[.2126,.7152,.0722][index],0):.5;
    const onAccent=accentLuminance>.179?'#000000':'#FFFFFF';
    const selection=materialAccent?accentLayer(light?.25:.3):(light?'#D5E3FF':'#2D4668');
    const completion=completionPalette({light,glass,surface,foreground,accent,muted:mutedColor});
    if(mainOrion)for(const [role,value]of Object.entries(completion))
      document.documentElement.style.setProperty(`--orion-suggest-${role}`,value);
    // Classic Orion shares the Flutter shell's single backdrop. It must not
    // paint another gradient inside Monaco, or restart that gradient at the
    // editor's bounds. Preserved interface ports ignore this shell option.
    const transparentBackground=glass || (studio?options.studioEditorTransparent===true:!synapse && !original && options.transparentBackground===true);
    sharedWindowBackdrop=compositorGlass?null:windowBackdrop(options,orion && studio || transparentBackground && !studio,glass) ||
      (glass?{color:hexColor(background)?background:'#1c2431',gradient:null,radials:[],opacity:1}:null);
    applyWindowBackdrop();
    const backdrop=options.backgroundGradient;
    let gradient=null;
    if(!synapse && !original && !transparentBackground && backdrop && Array.isArray(backdrop.colors) &&
       backdrop.colors.length>=2 && backdrop.colors.length<=4 &&
       backdrop.colors.every(color=>typeof color==='string' && /^#[0-9a-f]{6}$/i.test(color))) {
      const stops=Array.isArray(backdrop.stops) && backdrop.stops.length===backdrop.colors.length &&
        backdrop.stops.every((stop,index)=>Number.isFinite(stop) && stop>=0 && stop<=1 &&
          (index===0 || stop>=backdrop.stops[index-1])) ? backdrop.stops : null;
      const angle=Number.isFinite(backdrop.angle)?((backdrop.angle%360)+360)%360:135;
      gradient=`linear-gradient(${angle}deg,${backdrop.colors.map((color,index)=>
        `${color} ${100*(stops?stops[index]:index/(backdrop.colors.length-1))}%`).join(',')})`;
    }
    const editorBackground=gradient || transparentBackground?'#00000000':background;
    const themeKey=JSON.stringify({background,foreground,accent,mutedColor,border,surface,gradient,transparentBackground,light,synapse,shell,editorThemeId,studio,glass,compositorGlass});
    if(themeKey!==lastTheme) {
      lastTheme=themeKey;
      const defineTheme=theme=>{
        if(studio)theme={...theme,colors:{...theme.colors,
          'editor.background':editorBackground,'editor.foreground':foreground,
          'editorGutter.background':editorBackground,'editorPane.background':editorBackground,
          'minimap.background':editorBackground,'editorStickyScroll.background':editorBackground,
          'editorLineNumber.foreground':mutedColor,'editorLineNumber.activeForeground':foreground,
          'editorCursor.foreground':accent,'editor.selectionBackground':selection,
          'editor.lineHighlightBackground':transparentBackground?'#00000000':'#ffffff08',
          'editorWidget.background':surface,'editorWidget.border':border,
          'editorSuggestWidget.background':surface,'editorSuggestWidget.foreground':foreground,
          'editorSuggestWidget.border':border,'editorSuggestWidget.highlightForeground':accent,
          'editorSuggestWidget.selectedBackground':selection,'editorHoverWidget.background':surface,
          'editorHoverWidget.foreground':foreground,'editorHoverWidget.border':border,
        }};
        monaco.editor.defineTheme('orion',theme);
      };
      if(original) defineTheme(originalTheme(shell,background));
      else if(v3) defineTheme(OrionSynapseTheme.buildVsDarkShellMonacoTheme(background));
      else if(synapse) {
        let id=editorThemeId;
        if(x && background.toLowerCase()!=='#1e1e1e')id='shell-custom';
        const theme=OrionSynapseSkins.resolve(id,background);
        if(theme)defineTheme(theme);
        else defineTheme({base:['vs','hc-light'].includes(id)?'vs':'vs-dark',inherit:true,rules:[],colors:{}});
      }
      else monaco.editor.defineTheme('orion',{base:light?'vs':'vs-dark',inherit:true,rules:[
        {token:'',foreground:foreground.replace('#','')},{token:'comment',foreground:light?'668166':'758F85',fontStyle:'italic'},
        {token:'keyword',foreground:light?'6550A1':'C5ABFF'},{token:'type',foreground:light?'156D81':'82C8D9'},
        {token:'string',foreground:light?'3D7846':'B8D69B'},{token:'string.interpolation',foreground:light?'175FCB':'A8C7FA'},
        {token:'number',foreground:light?'96652A':'EBC58E'},{token:'operator',foreground:accent.replace('#','')},
      ],colors:{
        'editor.background':editorBackground,'editor.foreground':foreground,'editorLineNumber.foreground':mutedColor,
        'editorLineNumber.activeForeground':accent,'editorCursor.foreground':accent,'editor.selectionBackground':selection,
        'editor.inactiveSelectionBackground':materialAccent?accentLayer(.18):(light?'#E3EAF6':'#25344A'),'editor.lineHighlightBackground':transparentBackground?'#00000000':materialAccent?accentLayer(.08):(light?'#EBEFF6':'#1A2330'),
        // Monaco inherits blue occurrence/search chrome from vs-dark unless
        // these roles follow Orion's selected theme as well as its cursor.
        'editor.selectionHighlightBackground':materialAccent?accentLayer(.15):selection,
        'editor.wordHighlightBackground':materialAccent?accentLayer(.12):selection,
        'editor.wordHighlightStrongBackground':materialAccent?accentLayer(.22):selection,
        'editor.wordHighlightTextBackground':materialAccent?accentLayer(.12):selection,
        'editor.hoverHighlightBackground':materialAccent?accentLayer(.1):selection,
        'editor.lineHighlightBorder':'#00000000','editorIndentGuide.background1':border,'editorIndentGuide.activeBackground1':accent,
        'editorWidget.background':surface,'editorWidget.border':border,'editorSuggestWidget.background':mainOrion?completion.surface:surface,
        'editorSuggestWidget.border':mainOrion?completion.rim:border,'editorSuggestWidget.foreground':mainOrion?completion.foreground:foreground,
        'editorSuggestWidget.selectedBackground':mainOrion?completion.selected:selection,
        'editorSuggestWidget.highlightForeground':mainOrion?completion.highlight:accent,
        'editorSuggestWidget.focusHighlightForeground':mainOrion?completion.highlight:accent,
        'editorSuggestWidget.selectedForeground':mainOrion?completion.foreground:foreground,
        'editorSuggestWidget.selectedIconForeground':mainOrion?completion.highlight:foreground,
        'editorHoverWidget.background':surface,'editorHoverWidget.border':border,'editorWidget.resizeBorder':accent,
        'editorHoverWidget.foreground':foreground,'editor.findMatchBackground':materialAccent?accentLayer(.4):(light?'#A6C8FF':'#396194'),
        'editor.findMatchHighlightBackground':materialAccent?accentLayer(.16):(light?'#CEE0FF':'#2C4668'),'editorBracketMatch.background':selection,
        'editorBracketMatch.border':accent,'focusBorder':accent,'input.background':background,'input.foreground':foreground,
        'input.border':border,'inputOption.activeBackground':selection,'inputOption.activeBorder':accent,
        'inputOption.activeForeground':foreground,'list.activeSelectionBackground':selection,
        'list.activeSelectionForeground':foreground,'list.focusForeground':foreground,
        'list.focusBackground':selection,'list.focusOutline':accent,'list.highlightForeground':accent,
        'list.dropBackground':materialAccent?accentLayer(.18):selection,
        'list.hoverBackground':materialAccent?accentLayer(.12):(light?'#E9EFF8':'#29384E'),
        'quickInputList.focusBackground':selection,'quickInputList.focusForeground':foreground,
        'scrollbarSlider.background':materialAccent?mutedLayer(.2):(light?'#71829B44':'#7691B644'),
        'scrollbarSlider.hoverBackground':materialAccent?mutedLayer(.35):(light?'#71829B77':'#7691B677'),
        'scrollbarSlider.activeBackground':materialAccent?mutedLayer(.45):(light?'#71829B99':'#7691B699'),
        'editorOverviewRuler.wordHighlightForeground':materialAccent?accentLayer(.3):selection,
        'editorOverviewRuler.wordHighlightStrongForeground':materialAccent?accentLayer(.4):selection,
        'editorOverviewRuler.selectionHighlightForeground':materialAccent?accentLayer(.3):selection,
        'minimap.selectionHighlight':selection,'minimap.findMatchHighlight':materialAccent?accentLayer(.4):selection,
        'progressBar.background':accent,'pickerGroup.foreground':accent,'textLink.foreground':accent,
        'textLink.activeForeground':accent,'editorLink.activeForeground':accent,
        'button.background':accent,'button.foreground':onAccent,'button.hoverBackground':materialAccent?accentLayer(.85):accent,
        'button.secondaryBackground':surface,'button.secondaryForeground':foreground,
        'button.secondaryHoverBackground':materialAccent?accentLayer(.12):selection,'sash.hoverBorder':accent,
        'menu.background':surface,'menu.foreground':foreground,
        'menu.border':border,'menu.selectionBackground':selection,'editorOverviewRuler.border':'#00000000',
        'editorGutter.background':editorBackground,'editorPane.background':editorBackground,
        'minimap.background':editorBackground,'editorStickyScroll.background':editorBackground,
      }});
      monaco.editor.setTheme(synapse && !studio && ['vs','vs-dark','hc-black','hc-light'].includes(editorThemeId) ? editorThemeId : 'orion');
      document.documentElement.classList.toggle('orion-gradient',Boolean(gradient));
      document.documentElement.classList.toggle('orion-transparent',transparentBackground);
      document.documentElement.style.setProperty('--editor-gradient',gradient || 'none');
      document.documentElement.style.setProperty('--background',transparentBackground?'transparent':background);
      document.documentElement.style.setProperty('--foreground',foreground);
      document.documentElement.style.setProperty('--studio-muted',mutedColor);
      document.documentElement.style.setProperty('--studio-surface',surface);
      document.documentElement.style.setProperty('--studio-border',border);
      document.documentElement.style.colorScheme=light?'light':'dark';
    }
    const reduceMotion=options.reducedMotion===true;
    const baseReset = {
      folding:true,foldingHighlight:true,showFoldingControls:'mouseover',dragAndDrop:true,links:false,
      renderValidationDecorations:'editable',codeLens:true,inlayHints:{enabled:'on'},
      'semanticHighlighting.enabled':true,stopRenderingLineAfter:10000,emptySelectionClipboard:true,
      fixedOverflowWidgets:false,renderControlCharacters:false,colorDecorators:true,formatOnType:false,formatOnPaste:false,
      tabCompletion:'on',inlineSuggest:{enabled:false},quickSuggestionsDelay:100,
      parameterHints:{enabled:true,cycle:true},hover:{enabled:true,delay:400},
      occurrencesHighlight:'singleFile',selectionHighlight:true,
      unicodeHighlight:{ambiguousCharacters:false,nonBasicASCII:false,invisibleCharacters:true},
      bracketPairColorization:{enabled:true,independentColorPoolPerBracketType:false},
      guides:{indentation:true,bracketPairs:'active',bracketPairsHorizontal:false,highlightActiveBracketPair:true},
      suggest:{showKeywords:true,showFunctions:true,showMethods:true,showFields:true,showVariables:true,
        showClasses:true,showEnums:true,showModules:true,showSnippets:true,showWords:true,showIcons:true,
        snippetsPreventQuickSuggestions:true,filterGraceful:true,selectionMode:'always',preview:false,showStatusBar:false},
    };
    const sourceOptions = original ? {
      'semanticHighlighting.enabled':false,renderValidationDecorations:'off',codeLens:false,inlayHints:{enabled:'off'},
      fontSize:krnl?40/3:zenith?14:13,fontLigatures:false,lineHeight:krnl?16:zenith?20:18,
      fontFamily:krnl?"'OrionXMono', Consolas, 'Courier New', monospace":zenith?"'JetBrains Mono', 'Fira Code', Consolas, Monaco, monospace":'"Droid Sans Mono", "monospace", monospace',
      padding:zenith?{top:0,bottom:0}:{top:0,bottom:2},
      glyphMargin:awp||xeno,lineNumbersMinChars:zenith?5:1,lineDecorationsWidth:zenith?10:krnl?krnlGutter().decorations:0,
      minimap:{enabled:false},wordWrap:zenith?'on':'off',lineNumbers:'on',renderWhitespace:'none',
      suggestFontSize:zenith?14:13,suggestLineHeight:zenith?20:18,
      wordBasedSuggestions:zenith?'currentDocument':'off',quickSuggestions:zenith?{other:true,comments:false,strings:false}:false,
      suggestOnTriggerCharacters:zenith,quickSuggestionsDelay:50,tabCompletion:zenith?'on':'off',
      bracketPairColorization:{enabled:zenith,independentColorPoolPerBracketType:false},
      guides:{indentation:!krnl,bracketPairs:zenith,bracketPairsHorizontal:zenith?'active':false,highlightActiveBracketPair:zenith},
      renderLineHighlight:krnl?'none':zenith?'line':'all',overviewRulerBorder:false,hideCursorInOverviewRuler:true,
      smoothScrolling:false,cursorSmoothCaretAnimation:'off',cursorBlinking:reduceMotion?'solid':'blink',
      scrollbar:{useShadows:false,verticalScrollbarSize:zenith?10:14,horizontalScrollbarSize:10,
        vertical:'auto',horizontal:'auto',verticalHasArrows:false,horizontalHasArrows:false},
      fixedOverflowWidgets:true,colorDecorators:false,stopRenderingLineAfter:zenith?1000:5000,emptySelectionClipboard:false,
      links:!krnl,folding:!krnl,showFoldingControls:zenith?'always':'mouseover',
      occurrencesHighlight:zenith?'singleFile':'off',selectionHighlight:zenith,
      unicodeHighlight:{ambiguousCharacters:false,invisibleCharacters:false,nonBasicASCII:false},
      parameterHints:{enabled:!zenith&&!krnl,cycle:true},hover:{enabled:!zenith&&!krnl,delay:300},
      formatOnType:zenith,formatOnPaste:zenith&&options.formatOnPaste===true,
      ...(zenith?{suggest:{snippetsPreventQuickSuggestions:false,showIcons:true,filterGraceful:false,
        selectionMode:'never',showKeywords:true,showFunctions:true,showMethods:true,showFields:true,showVariables:true,
        showClasses:true,showEnums:true,preview:false,showStatusBar:false}}:{}),
    } : {};
    editor.updateOptions({
      ...baseReset,
      fontFamily:x?"'OrionXMono', Consolas, 'Courier New', monospace":synapse?'"Droid Sans Mono", "monospace", monospace':"'JetBrains Mono', monospace",
      fontLigatures:false,
      fontSize:Math.min(24,Math.max(10,Number(options.fontSize)||14)),
      lineHeight:v3?16:x?0:synapse?18:23,padding:synapse?{top:0,bottom:2}:{top:16,bottom:16},
      glyphMargin:synapse,lineNumbersMinChars:v3?2:synapse?1:3,lineDecorationsWidth:v3?10:synapse?0:8,
      // Monaco owns row geometry and keyboard scrolling; CSS supplies only
      // the inset state layer, so virtualized rows stay aligned with input.
      suggestFontSize:synapse?13:mainOrion?Math.min(16,Math.max(13,Number(options.fontSize)||14)):0,
      suggestLineHeight:synapse?18:mainOrion?30:0,
      wordBasedSuggestions:synapse?'off':'currentDocument',
      renderWhitespace:mainOrion?(options.renderWhitespace===true?'all':'none'):synapse?'none':'selection',
      bracketPairColorization:{enabled:mainOrion?options.bracketPairColorization!==false:!synapse},
      wordWrap:options.wordWrap===true||options.wordWrap==='on'?'on':'off',
      lineNumbers:options.lineNumbers===false||options.lineNumbers==='off'?'off':'on',
      minimap:{enabled:options.minimap===true,scale:Math.max(1,Math.min(3,Number(options.minimapScale)||1))},
      renderLineHighlight:synapse?(v3||og?'line':'all'):'line',
      overviewRulerBorder:!synapse,hideCursorInOverviewRuler:synapse,
      scrollbar:{useShadows:false,verticalScrollbarSize:synapse?14:9,horizontalScrollbarSize:synapse?10:9},
      smoothScrolling:!synapse&&!reduceMotion,cursorSmoothCaretAnimation:synapse||reduceMotion?'off':'on',
      cursorBlinking:reduceMotion?'solid':'smooth',
      quickSuggestions:options.autocomplete===false?false:{other:true,comments:false,strings:false},
      suggestOnTriggerCharacters:options.autocomplete!==false,
      ...sourceOptions,
      ...(studio && typeof options.studioFontFamily==='string' && options.studioFontFamily.length<=64?{fontFamily:options.studioFontFamily}:{}),
    });
    if (krnl) {lastKrnlGutter=krnlGutter().width;document.documentElement.style.setProperty('--krnl-gutter-width',lastKrnlGutter+'px');}
    updateOriginalHint();
  }
  function changeModelContent(model, content) {
    if(model.getValue()===content)return;
    model.pushStackElement();
    model.pushEditOperations([], [{range:model.getFullModelRange(),text:content}], () => null);
    model.pushStackElement();
  }
  function sync(command) {
    const requested=Array.isArray(command.documents)?command.documents:[];
    const ids=new Set(requested.map(doc=>String(doc.id)));
    muted=true;
    try {
      for(const document of requested) {
        const id=String(document.id),content=String(document.content || '');
        let existing=documents.get(id);
        if(!existing) {
          const uri=monaco.Uri.parse('orion://workspace/'+encodeURIComponent(id)+'/'+encodeURIComponent(document.name||'script.luau'));
          const model=monaco.editor.createModel(content,'luau',uri);
          existing={model,name:document.name,viewState:null};documents.set(id,existing);
          model.onDidChangeContent(() => {if(!muted)post({type:'change',id,content:model.getValue()});scheduleDiagnostics();updateOriginalHint();refreshOriginalGutter();});
        } else {existing.name=document.name;if(!document.nativeEcho)changeModelContent(existing.model,content);}
      }
      const nextId=command.activeId==null?null:String(command.activeId);
      if(activeId!==nextId || editor.getModel()==null) {
        const old=documents.get(activeId);if(old)old.viewState=editor.saveViewState();
        activeId=nextId;const next=documents.get(nextId);
        editor.setModel(next?next.model:null);
        if(next && next.viewState)editor.restoreViewState(next.viewState);
      }
      for(const [id,document] of documents)if(!ids.has(id)){document.model.dispose();documents.delete(id);}
      updateOptions(command.options);
      refreshDiagnostics();updateOriginalHint();refreshOriginalGutter();
    } finally {muted=false;}
    postCursor(editor.getPosition());
  }
  async function action(command) {
    const name=command.name;
    if(name==='focus'){editor.focus();return;}
    if(name==='clear') {
      const model=editor.getModel();if(model)changeModelContent(model,'');editor.focus();return;
    }
    if(name==='paste') {
      try {
        const text=typeof command.text==='string'?command.text:await navigator.clipboard.readText();
        editor.pushUndoStop();editor.executeEdits('orion-paste',[{range:editor.getSelection(),text,forceMoveMarkers:true}]);editor.pushUndoStop();editor.focus();
      } catch(error) {post({type:'error',message:'Paste requires clipboard access. Use Ctrl+V inside the editor.'});}
      return;
    }
    const ids={undo:'undo',redo:'redo',selectAll:'editor.action.selectAll',find:'actions.find',replace:'editor.action.startFindReplaceAction',format:'editor.action.reindentlines',suggest:'editor.action.triggerSuggest',commands:'editor.action.quickCommand'};
    if(ids[name]) {editor.focus();editor.trigger('orion',ids[name],null);}
  }
  function receive(command) {
    try {
      if(typeof command==='string')command=JSON.parse(command);
      if(!command||typeof command!=='object')return;
      if(!editor){pending.push(command);return;}
      switch(command.type || command.command) {
        case 'sync':sync(command);break;
        case 'layout':layoutEditor(true);break;
        case 'action':void action(command);break;
        case 'flush': {const model=editor.getModel();post({type:'flush',requestId:command.requestId,id:activeId,content:model?model.getValue():''});break;}
      }
    } catch(error) {report(error);}
  }
  window.orionReceive=receive;
  require(['vs/editor/editor.main'], async function () {
    try {
      const response=await fetch('./roblox-api.json');if(!response.ok)throw new Error('Luau API catalog is unavailable');
      window.orionLuau=OrionLuau.register(monaco,await response.json());
      // Monaco caches character widths at creation. Load its actual default
      // font as well as preserved profiles before measuring, and keep working
      // with the fallback font if a bundled font cannot be decoded.
      if (document.fonts) {
        let fontTimeout;
        try {
          await Promise.race([
            Promise.allSettled([
              document.fonts.load('14px "JetBrains Mono"'),
              document.fonts.load('14px OrionXMono'),
              document.fonts.load('bold 14px OrionXMono'),
            ]),
            new Promise(resolve => {fontTimeout = setTimeout(resolve,1000);}),
          ]);
        } finally {clearTimeout(fontTimeout);}
      }
      editor=monaco.editor.create(document.getElementById('editor'),{
        model:null,theme:'vs-dark',language:'luau',
        fontFamily:"'JetBrains Mono', monospace",fontSize:14,fontLigatures:false,lineHeight:23,
        minimap:{enabled:false},lineNumbers:'on',lineNumbersMinChars:3,lineDecorationsWidth:8,
        padding:{top:16,bottom:16},tabSize:4,insertSpaces:true,detectIndentation:true,
        scrollBeyondLastLine:false,scrollbar:{useShadows:false,verticalScrollbarSize:9,horizontalScrollbarSize:9},
        quickSuggestions:{other:true,comments:false,strings:false},quickSuggestionsDelay:100,
        suggestOnTriggerCharacters:true,tabCompletion:'on',snippetSuggestions:'top',
        wordBasedSuggestions:'currentDocument',parameterHints:{enabled:true,cycle:true},
        hover:{enabled:true,delay:400},autoClosingBrackets:'languageDefined',autoClosingQuotes:'languageDefined',
        autoIndent:'full',formatOnPaste:false,folding:true,foldingHighlight:true,showFoldingControls:'mouseover',
        bracketPairColorization:{enabled:true},guides:{indentation:true,bracketPairs:'active'},
        links:false,contextmenu:true,renderWhitespace:'selection',renderLineHighlight:'line',
        occurrencesHighlight:'singleFile',selectionHighlight:true,stickyScroll:{enabled:false},
        unicodeHighlight:{ambiguousCharacters:false,nonBasicASCII:false,invisibleCharacters:true},
        accessibilitySupport:'auto',ariaLabel:'Orion Luau script editor',
      });
      window.orionEditor=editor;
      if (document.fonts && document.fonts.addEventListener) document.fonts.addEventListener('loadingdone', () => {
        fontMeasurementRequested = true;
        layoutEditor(true);
      });
      const hintHelp=document.getElementById('zenith-editor-help');
      if(hintHelp&&hintHelp.addEventListener)hintHelp.addEventListener('click',()=>post({type:'shortcut',name:'help'}));
      editor.onDidChangeCursorPosition(event=>postCursor(event.position));
      editor.onDidBlurEditorWidget(()=>{const model=editor.getModel();if(model)post({type:'change',id:activeId,content:model.getValue()});if(currentCompositorGlass)post({type:'focus',focused:false});});
      if(editor.onDidFocusEditorWidget)editor.onDidFocusEditorWidget(()=>{if(currentCompositorGlass)post({type:'focus',focused:true});});
      for(const event of ['onDidScrollChange','onDidChangeCursorSelection','onMouseDown','onKeyDown'])
        if(editor[event])editor[event](frameInteraction);
      const key=monaco.KeyMod.CtrlCmd,code=monaco.KeyCode;
      editor.addCommand(monaco.KeyMod.Shift|monaco.KeyMod.Alt|code.KeyF,()=>editor.trigger('orion','editor.action.reindentlines',null));
      for(const [binding,name] of [[key|code.KeyS,'save'],[key|monaco.KeyMod.Shift|code.KeyS,'saveAs'],[key|code.KeyO,'open'],[key|code.KeyN,'new'],[key|code.Enter,'execute'],[key|code.KeyK,'palette'],[key|monaco.KeyMod.Shift|code.KeyL,'console'],[key|monaco.KeyMod.Alt|code.KeyT,'theme-studio'],[key|monaco.KeyMod.Alt|monaco.KeyMod.Shift|code.KeyT,'theme-studio'],[code.F9,'console']]) {
        editor.addCommand(binding,()=>{const model=editor.getModel();if(model)post({type:'change',id:activeId,content:model.getValue()});post({type:'shortcut',name});});
      }
      editor.addCommand(key|code.KeyP,()=>{if(currentShell==='originalZenith')post({type:'shortcut',name:'palette'});else editor.trigger('orion','editor.action.quickCommand',null);});
      editor.addCommand(key|code.KeyW,()=>{if(currentShell==='originalZenith')post({type:'shortcut',name:'close-tab'});});
      editor.addCommand(key|code.KeyT,()=>{if(currentShell==='originalZenith')post({type:'shortcut',name:'new'});});
      updateOptions({});
      document.getElementById('loading').remove();
      for(const command of pending.splice(0))receive(command);
      layoutEditor(true);
      post({type:'ready'});
    } catch(error) {report(error);}
  });
})();
