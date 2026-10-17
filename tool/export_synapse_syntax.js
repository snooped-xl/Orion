// node tool/export_synapse_syntax.js [--check]
// Export the real native theme rules used by the Luau Monarch token categories.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const path = require('node:path');
const editor = path.join(__dirname, '../assets/editor');
const context = {};
vm.createContext(context);
for (const file of ['synapse-theme.js', 'synapse-skins.js']) {
  vm.runInContext(fs.readFileSync(path.join(editor, file), 'utf8'), context);
}
const tokens = {comment:'comment',keyword:'keyword',type:'type',string:'string',escape:'string.escape',number:'number',operator:'operator',interpolation:'string.interpolation'};
const dark = {comment:'6A9955',keyword:'569CD6',type:'4EC9B0',string:'CE9178',escape:'D7BA7D',number:'B5CEA8',operator:'D4D4D4',interpolation:'CE9178'};
const light = {comment:'008000',keyword:'0000FF',type:'267F99',string:'A31515',escape:'EE0000',number:'098658',operator:'000000',interpolation:'A31515'};
function flatten(theme) {
  const base = theme.base === 'vs' ? light : dark;
  const foreground = theme.colors?.['editor.foreground'] ||
      theme.rules.find(rule => rule.token === '' && rule.foreground)?.foreground ||
      (theme.base === 'vs' ? '000000' : 'D4D4D4');
  const result = {foreground:foreground.replace('#',''),styles:{}};
  for (const [kind, token] of Object.entries(tokens)) {
    const style = {foreground:base[kind]};
    const rules = theme.rules.filter(rule => rule.token &&
      (token === rule.token || token.startsWith(rule.token + '.')))
      .sort((a,b) => a.token.length - b.token.length);
    for (const rule of rules) {
      if (rule.foreground) style.foreground = rule.foreground;
      if (rule.fontStyle !== undefined) style.fontStyle = rule.fontStyle;
    }
    result.styles[kind] = style;
  }
  return result;
}
const ids = [...context.OrionSynapseSkins.ids,'net-theme-dark','net-theme-light',
  'og-2017-custom','shell-custom','shell-framework','shell-midnight','shell-graphite',
  'shell-ocean','shell-ember','shell-high-contrast','shell-novo'];
const themes = {'synapse-v3':flatten(context.OrionSynapseTheme.buildVsDarkShellMonacoTheme('#1e1e1e'))};
for (const id of ids) {
  const theme = context.OrionSynapseSkins.resolve(id,'#1e1e1e');
  if (theme) themes[id] = flatten(theme);
}
const destination = path.join(editor,'synapse-syntax-themes.json');
if (process.argv.includes('--check')) {
  assert.deepEqual(JSON.parse(fs.readFileSync(destination,'utf8')),themes,
    'Flutter syntax palettes must match the native Monaco theme definitions');
} else fs.writeFileSync(destination,JSON.stringify(themes));
console.log(`${Object.keys(themes).length} Synapse syntax palettes match native Monaco.`);
