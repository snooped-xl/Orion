// Exact active pool dimensions and pass graphs, without requiring a desktop.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,
  '../linux/gnome/orion-glass@orion.local/dist/rendering/blur.js'), 'utf8');
let allocated = 0;
const Cogl = {
  Texture2D: {new_with_size(ctx, width, height) {
    allocated++;
    return {ctx, width, height, get_width: () => width, get_height: () => height};
  }},
  Offscreen: {new_with_texture(texture) { return {texture}; }},
};
const sandbox = {Cogl,
  computeGaussianKernel(sigma, pairs) {return {sigma,pairs};},
  setPipelineFloat(p, key, value) {p.uniforms[key] = value;},
  setPipelineVec2(p, key, x, y) {p.uniforms[key] = [x, y];},
};
vm.createContext(sandbox);
vm.runInContext(source.replace(/^import .*;\n/gm, '').replace('export class BlurRenderer', 'class BlurRenderer') +
  '\nglobalThis.BlurRenderer=BlurRenderer;', sandbox);
const Blur = sandbox.BlurRenderer;
const graph = [];
const pipelines = Object.fromEntries(['downsample','upsample','passthrough','boxDown'].map(name => [name,{name}]));
const copies = new Map();
const passes = {
  pipeline(key) {
    if (!copies.has(key)) copies.set(key,{key, uniforms:{},set_layer_texture(_,texture){this.input=texture;}});
    return copies.get(key);
  },
  add(_, target, pipeline, width, height, uv) {
    graph.push({key:pipeline.key,width,height,input:[pipeline.input.get_width(),pipeline.input.get_height()],
      uniforms:JSON.parse(JSON.stringify(pipeline.uniforms)),uv:[...uv],target:[target.texture.width,target.texture.height]});
  },
};
const context = {};
const blur = new Blur(pipelines, passes, () => {});
function render(width,height) {
  blur.resize(context,width,height);
  graph.length=0;
  blur.render({}, {get_width:()=>width,get_height:()=>height},[0,0,1,1],['frame',1]);
  return JSON.parse(JSON.stringify(graph));
}
blur.setBlurRadius(3);
let start = allocated;
const graph822=render(822,523);
assert.equal(allocated-start,3,'two-pass Kawase allocates exactly its three read targets');
assert.deepEqual(graph822.map(p=>[p.key,p.width,p.height]),[
  ['kawase-down-0',411,261],['kawase-down-1',205,130],['kawase-up-1',411,261],
]);
const down0=blur._blurTextures[0], down1=blur._blurTextures[1], up0=blur._upTextures[0];
start=allocated;const graph823=render(823,523);
assert.equal(allocated-start,0,'odd source increment retains all exact-sized half/quarter targets');
assert.equal(blur._blurTextures[0],down0);assert.equal(blur._blurTextures[1],down1);assert.equal(blur._upTextures[0],up0);
assert.deepEqual(graph823.map(p=>[p.key,p.width,p.height]),graph822.map(p=>[p.key,p.width,p.height]));
render(824,523);render(825,523);
const retainedQuarter=blur._blurTextures[1];
start=allocated;render(826,523);
assert.equal(allocated-start,2,'one changed level replaces only its used down/up targets');
assert.equal(blur._blurTextures[1],retainedQuarter);
assert.equal(blur._gaussianTempTextures.length,0);
assert.equal(blur._upTextures.length,1);

// Every radius/downscale keeps the original integer layout and pass kernels.
for (const radius of [0,.25,1,3,7,15]) {
  for (const downscale of [2,4]) {
    blur.setDownscale(downscale);blur.setBlurRadius(radius);
    const count=blur.passCount;
    const actual=render(831,537);
    assert.equal(actual.length,count ? count*2-1 : 0);
    let width=831>>(downscale===4?2:1),height=537>>(downscale===4?2:1);
    for(let i=0;i<count;i++) {
      assert.equal(actual[i].width,Math.max(width,1));assert.equal(actual[i].height,Math.max(height,1));
      if(i || downscale===2)assert.equal(actual[i].uniforms.blur_radius,blur._blurRadiusDown);
      width=Math.max(width>>1,1);height=Math.max(height>>1,1);
    }
    assert.equal(blur._gaussianTempTextures.length,0);
    assert.equal(blur._upTextures.length,Math.max(count-1,0));
  }
}
// Switching methods with unchanged source and identical one-level count must
// create the Gaussian horizontal and vertical intermediates before rendering.
blur.setDownscale(2);blur.setBlurRadius(1);render(822,523);
blur.setBlurMethod(0);
assert.equal(blur.width,0);
blur._gaussianHPipeline={name:'h'};blur._gaussianVPipeline={name:'v'};
const gaussian=render(822,523);
assert.deepEqual(gaussian.map(p=>[p.key,p.width,p.height]),[
  ['gauss-pre',411,261],['gauss-h',411,261],['gauss-v',411,261],
]);
assert.equal(blur._gaussianTempTextures.length,1);assert.equal(blur._upTextures.length,1);
const gaussianTarget=blur._blurTextures[0];
blur.resize(context,823,523);assert.equal(blur._blurTextures[0],gaussianTarget);
blur.setBlurMethod(1);render(822,523);
assert.equal(blur._gaussianTempTextures.length,0);assert.equal(blur._upTextures.length,0);

// No result may survive a resize, context replacement, explicit invalidation
// or cleanup. Same-sized allocations are not valid across Cogl contexts.
const first=blur._blurTextures[0];start=allocated;
blur.resize({},822,523);assert.notEqual(blur._blurTextures[0],first);
assert.equal(allocated-start,1);
assert.equal(blur._renderedKey,null);assert.equal(blur.result,null);
for(const method of ['invalidate','clear']) {
  blur[method]();assert.equal(blur.width,0);assert.equal(blur._poolContext,null);
  blur.setBlurRadius(3);render(822,523);assert.equal(blur._blurTextures.length,2);
}

// Desktop helper reloads retain the canonical class constructor. Copying the
// four fresh plain-class methods onto a cached prototype also upgrades a
// receiver that predates _poolContext, without any GObject re-registration.
class CachedBlur {}
const cached = Object.assign(new CachedBlur(),blur);
delete cached._poolContext;
for(const name of ['resize','_resizeTarget','_destroyTexturePool','setBlurMethod']) {
  CachedBlur.prototype[name]=Blur.prototype[name];
}
cached.resize(context,822,523);
assert(cached instanceof CachedBlur);assert.equal(cached._poolContext,context);
assert.equal(cached._blurTextures.length,2);
start=allocated;cached.resize(context,823,523);assert.equal(allocated-start,0);
console.log('PASS exact Kawase/Gaussian dimensions, kernels, active targets, integer-step reuse, context/cleanup invalidation and cached-class hot upgrade');
