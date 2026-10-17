// Run from the project root with the repository's isolated Playwright runtime.
// This serves only the bundled editor; it never opens or captures the desktop.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {chromium} = require(process.env.ORION_PLAYWRIGHT_PATH || path.resolve(__dirname, '../../../work/monaco/test-runtime/node_modules/playwright'));
const base = path.resolve(__dirname, '../assets/editor');
const types = {'.html':'text/html','.js':'text/javascript','.json':'application/json','.css':'text/css','.ttf':'font/ttf'};
const source = 'local part = Instance.new("Part")\npart.';
const configurations = [
  ['dark', {shell:'orion',background:'#141A23',surface:'#1C2635',foreground:'#E7EDF7',accent:'#A8C7FA',muted:'#8C9CB4'}],
  ['light', {shell:'orion',brightness:'light',background:'#F4F6FB',surface:'#FFFFFF',foreground:'#1A2535',accent:'#175FCB',muted:'#68758A'}],
  ['custom', {shell:'orion',background:'#261B30',surface:'#352540',foreground:'#F1E9F9',accent:'#E0B8FF',muted:'#B5A1C3',backgroundGradient:{colors:['#201828','#382242'],angle:135}}],
  ['glassy', {shell:'orion',glassEnabled:true,compositorGlass:true,surface:'#1C2635',foreground:'#EEF3FA',accent:'#B7C9DF',muted:'#A1B2C8'}],
  ['glassy-custom', {shell:'orion',glassEnabled:true,compositorGlass:true,surface:'#352540',foreground:'#F1E9F9',accent:'#E0B8FF',muted:'#B5A1C3'}],
  ['glassy-light', {shell:'orion',brightness:'light',glassEnabled:true,compositorGlass:true,surface:'#EBF1F7',foreground:'#192635',accent:'#315B85',muted:'#536B82'}],
  ['glassy-custom-light', {shell:'orion',brightness:'light',glassEnabled:true,compositorGlass:true,surface:'#F7F0E4',foreground:'#382B20',accent:'#97602B',muted:'#796652'}],
];

(async () => {
  const server = http.createServer((request,response) => {
    const location = path.resolve(base, '.' + decodeURIComponent(request.url.split('?')[0]));
    if (!location.startsWith(base + path.sep)) {response.writeHead(404);return response.end();}
    fs.readFile(location, (error,data) => {
      response.writeHead(error?404:200, {'Content-Type':types[path.extname(location)] || 'application/octet-stream'});
      response.end(error?'missing':data);
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true,
      executablePath:process.env.ORION_CHROMIUM_PATH || path.join(os.homedir(), '.cache/ms-playwright/chromium-1228/chrome-linux64/chrome'),
      args:['--no-sandbox'],
    });
    const page = await browser.newPage({viewport:{width:850,height:500}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {if (message.type() === 'error') errors.push(message.text());});
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
    await page.waitForFunction(() => Boolean(window.orionEditor));
    const open = async (options) => {
      await page.keyboard.press('Escape');
      await page.evaluate(({source,options}) => {
        orionReceive({type:'sync',documents:[{id:'a',name:'a.luau',content:source}],activeId:'a',options:{fontSize:14,...options}});
        orionEditor.setPosition({lineNumber:2,column:6});
        orionEditor.focus();
        orionEditor.trigger('test','editor.action.triggerSuggest',null);
      }, {source,options});
      await page.waitForSelector('.suggest-widget.visible');
      await page.waitForTimeout(200);
    };
    const appearances = new Map();
    for (const [name,options] of configurations) {
      await open(options);
      const appearance = await page.evaluate(() => {
        const popup = document.querySelector('.suggest-widget'), row = popup.querySelector('.monaco-list-row');
        const icon = row.querySelector('.suggest-icon'), details = row.querySelector('.details-label');
        const style = getComputedStyle(popup);
        return {
          main:document.documentElement.classList.contains('orion-main'),radius:style.borderRadius,
          surface:style.backgroundColor,backgroundImage:style.backgroundImage,backdrop:style.backdropFilter,
          height:row.getBoundingClientRect().height,rowHeight:orionEditor.getOptions().get(monaco.editor.EditorOption.suggestLineHeight),
          rowBackground:getComputedStyle(row).backgroundColor,listBackground:getComputedStyle(popup.querySelector('.monaco-list')).backgroundColor,
          rowsBackground:getComputedStyle(popup.querySelector('.monaco-list-rows')).backgroundColor,
          iconFont:getComputedStyle(icon).fontFamily,iconGlyph:getComputedStyle(icon,'::before').content,
          iconBackground:getComputedStyle(icon).backgroundColor,
          codiconLoaded:document.fonts.check('16px codicon'),iconKind:icon.className,
          details:getComputedStyle(details).display,detailsWidth:details.getBoundingClientRect().width,
          focused:getComputedStyle(row,'::before').backgroundColor,pillRadius:getComputedStyle(row,'::before').borderRadius,
          canvas:getComputedStyle(document.documentElement).backgroundColor,shadow:style.boxShadow,
          text:getComputedStyle(row.querySelector('.monaco-icon-label')).color,
          muted:getComputedStyle(details).color,
        };
      });
      assert(appearance.main, name);
      assert.equal(appearance.radius, name.startsWith('glassy')?'20px':'18px', name);
      assert.equal(appearance.height, 30, name);
      assert.equal(appearance.rowHeight, 30, name);
      assert.equal(appearance.rowBackground, 'rgba(0, 0, 0, 0)', name);
      assert.equal(appearance.listBackground, 'rgba(0, 0, 0, 0)', name);
      assert.equal(appearance.rowsBackground, 'rgba(0, 0, 0, 0)', name);
      assert.equal(appearance.iconFont, 'codicon', name);
      assert.equal(appearance.iconBackground, 'rgba(0, 0, 0, 0)', `${name}: unboxed icons`);
      assert(appearance.codiconLoaded && appearance.iconGlyph !== 'none' && appearance.iconGlyph !== '""', name);
      assert(appearance.iconKind.includes('codicon-symbol-method'), `method kind is preserved: ${appearance.iconKind}`);
      assert.notEqual(appearance.details, 'none', name);
      assert(appearance.detailsWidth > 0 && appearance.detailsWidth < 250, name);
      assert.notEqual(appearance.focused, 'rgba(0, 0, 0, 0)', name);
      assert.equal(appearance.pillRadius, '11px', name);
      assert.equal(appearance.backdrop, 'none', name);
      assert.equal(appearance.backgroundImage, 'none', `${name}: one simple sheet`);
      assert(!appearance.shadow.includes('inset'), `${name}: no decorative inset rims`);
      if (name.startsWith('glassy')) {
        assert(appearance.surface.startsWith('rgba('), name);
        const channels=appearance.surface.match(/[\d.]+/g).map(Number);
        assert(channels[3] >= .7 && channels[3] <= .85, `${name}: meaningful transparency`);
        assert.deepEqual(channels.slice(0,3), [1,3,5].map(offset=>parseInt(options.surface.slice(offset,offset+2),16)), `${name}: actual theme surface RGB`);
        assert(appearance.focused.startsWith('rgba('), `${name}: translucent themed selection`);
        const selection=appearance.focused.match(/[\d.]+/g).map(Number);
        assert.deepEqual(selection.slice(0,3), [1,3,5].map(offset=>parseInt(options.accent.slice(offset,offset+2),16)), `${name}: actual theme accent`);
        assert(selection[3] < .2, `${name}: selection preserves glass alpha`);
        assert.equal(appearance.canvas, 'rgba(0, 0, 0, 0)', name);
      } else assert(appearance.surface.startsWith('rgb('), name);
      appearances.set(name,appearance);
      if (process.env.ORION_AUTOCOMPLETE_SCREENSHOTS) {
        fs.mkdirSync(process.env.ORION_AUTOCOMPLETE_SCREENSHOTS, {recursive:true});
        await page.screenshot({path:path.join(process.env.ORION_AUTOCOMPLETE_SCREENSHOTS, `${name}.png`)});
      }

      const first = await page.locator('.suggest-widget [role="listbox"]').getAttribute('aria-activedescendant');
      await page.keyboard.press('ArrowDown');
      const second = await page.locator('.suggest-widget [role="listbox"]').getAttribute('aria-activedescendant');
      assert.notEqual(second, first, `${name}: native arrow navigation`);
      await page.keyboard.press('PageDown');
      const position = await page.locator('.suggest-widget .monaco-list-row.focused').getAttribute('aria-posinset');
      assert(Number(position) > 2, `${name}: native virtual-list paging`);
    }
    assert.notEqual(appearances.get('glassy').surface, appearances.get('glassy-custom').surface, 'custom Glass changes the popup surface');
    assert.notEqual(appearances.get('glassy').focused, appearances.get('glassy-custom').focused, 'custom Glass changes the selection');
    assert.notEqual(appearances.get('glassy').text, appearances.get('glassy-custom').text, 'custom Glass uses the selected foreground');
    assert.notEqual(appearances.get('glassy-light').surface, appearances.get('glassy-custom-light').surface, 'light custom Glass follows its palette');

    await open({});
    assert.equal(await page.locator('.suggest-widget').evaluate(node => getComputedStyle(node).borderRadius), '18px');
    await page.emulateMedia({reducedMotion:'reduce'});
    await open({shell:'orion'});
    assert.equal(await page.locator('.suggest-widget').evaluate(node => getComputedStyle(node).animationName), 'none');
    await page.emulateMedia({reducedMotion:'no-preference'});
    await open({shell:'orion',reducedMotion:true});
    assert.equal(await page.locator('.suggest-widget').evaluate(node => getComputedStyle(node).animationName), 'none');
    assert.equal(await page.locator('.suggest-widget .monaco-list-row').first().evaluate(node => getComputedStyle(node,'::before').transitionDuration), '0s');
    await page.keyboard.type('Pos');
    await page.waitForTimeout(150);
    assert((await page.locator('.suggest-widget').innerText()).includes('Position'));
    assert((await page.locator('.suggest-widget .monaco-highlighted-label .highlight').allTextContents()).join('').includes('Pos'));
    await page.keyboard.press('Enter');
    assert((await page.evaluate(() => orionEditor.getValue())).endsWith('part.Position'));
    await page.evaluate(() => orionReceive({type:'action',name:'undo'}));
    assert((await page.evaluate(() => orionEditor.getValue())).endsWith('part.Pos'));
    await page.evaluate(() => orionReceive({type:'action',name:'redo'}));
    assert((await page.evaluate(() => orionEditor.getValue())).endsWith('part.Position'));

    await page.keyboard.press('Escape');
    const configure = async flags => page.evaluate(flags => {
      const content=orionEditor.getValue();
      window.settingsModel ||= orionEditor.getModel();
      orionReceive({type:'sync',documents:[{id:'a',name:'a.luau',content,nativeEcho:true}],activeId:'a',
        options:{shell:'orion',...flags}});
      const config=orionEditor.getOptions(), option=monaco.editor.EditorOption;
      return {minimap:config.get(option.minimap).enabled,brackets:config.get(option.bracketPairColorization).enabled,
        whitespace:config.get(option.renderWhitespace),automatic:config.get(option.quickSuggestions),
        triggers:config.get(option.suggestOnTriggerCharacters),sameModel:settingsModel===orionEditor.getModel(),content:orionEditor.getValue()};
    }, flags);
    const enabled=await configure({minimap:true,bracketPairColorization:true,renderWhitespace:true,autocomplete:true});
    assert.equal(enabled.minimap,true);assert.equal(enabled.brackets,true);assert.equal(enabled.whitespace,'all');
    assert.equal(enabled.triggers,true);assert.equal(enabled.sameModel,true);
    const disabled=await configure({minimap:false,bracketPairColorization:false,renderWhitespace:false,autocomplete:false});
    assert.equal(disabled.minimap,false);assert.equal(disabled.brackets,false);assert.equal(disabled.whitespace,'none');
    assert.equal(disabled.triggers,false);assert.equal(disabled.automatic.other,'off');assert.equal(disabled.sameModel,true);
    assert.equal(disabled.content,enabled.content);
    await page.evaluate(() => {orionEditor.setPosition({lineNumber:2,column:6});orionEditor.focus();});
    await page.keyboard.type('P');
    await page.waitForTimeout(200);
    assert.equal(await page.locator('.suggest-widget.visible').count(),0, 'automatic suggestions stay closed while disabled');
    await page.keyboard.press('Control+Space');
    await page.waitForSelector('.suggest-widget.visible');
    assert((await page.locator('.suggest-widget').innerText()).includes('Position'), 'manual completion remains available when automatic suggestions are disabled');

    for (const shell of ['originalAwp','originalXeno','originalKrnl','originalZenith','synapseV3','synapseBlue','synapseX','synapseOriginal']) {
      await open({shell,bracketPairColorization:true,renderWhitespace:true});
      assert.equal(await page.evaluate(() => document.documentElement.classList.contains('orion-main')), false, shell);
      assert.equal(await page.evaluate(() => orionEditor.getOptions().get(monaco.editor.EditorOption.suggestLineHeight)), shell === 'originalZenith'?20:18, shell);
      assert.equal(await page.evaluate(() => orionEditor.getOptions().get(monaco.editor.EditorOption.renderWhitespace)), 'none', `${shell}: main whitespace preference is isolated`);
      assert.equal(await page.evaluate(() => orionEditor.getOptions().get(monaco.editor.EditorOption.bracketPairColorization).enabled), shell==='originalZenith', `${shell}: source bracket preference remains intact`);
      assert.equal(await page.locator('.suggest-widget').evaluate(node => getComputedStyle(node).animationName), 'none', shell);
    }
    assert.deepEqual(errors, []);
    console.log('Orion autocomplete passed: simple theme-colored normal/custom Glass alpha sheets, unboxed glyphs, virtual rows, native keyboard/filter/accept/undo, real editor settings/manual completion, reduced motion and source-profile isolation.');
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => {console.error(error);process.exitCode = 1;});
