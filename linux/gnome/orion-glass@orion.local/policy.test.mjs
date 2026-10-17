import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
// Import as a module without changing GNOME's extension package structure.
const source = await readFile(new URL('./policy.js', import.meta.url), 'utf8');
const {validateRequest, ruleKey, windowMatches, RequestEpochs, MAX_RULES} = await import(`data:text/javascript,${encodeURIComponent(source)}`);
assert.equal(validateRequest(100,100,'Orion',24),null);
assert.equal(validateRequest(100,101,'Orion',24).reason,'caller-pid-mismatch');
assert.equal(validateRequest(100,100,'',24).reason,'invalid-window-title');
assert.equal(validateRequest(100,100,'Orion\u0000',24).reason,'invalid-window-title');
assert.equal(validateRequest(100,100,'x'.repeat(257),24).reason,'invalid-window-title');
for(const radius of [NaN,Infinity,-1,129])assert.equal(validateRequest(100,100,'Orion',radius).reason,'invalid-corner-radius');
assert.equal(ruleKey(100,'Orion'),'100:Orion');
const fake={get_pid:()=>100,get_title:()=> 'Orion'};
assert.equal(windowMatches(fake,{pid:100,title:'Orion'}),true);
assert.equal(windowMatches(fake,{pid:101,title:'Orion'}),false);
assert.equal(windowMatches(fake,{pid:100,title:'Other'}),false);
assert.equal(MAX_RULES,16);
console.log('PASS: owner PID, title, radius, exact window matching and bounded rules');

assert.equal(windowMatches(null,{pid:100,title:'Orion'}),false);
const epochs=new RequestEpochs(2), enable=epochs.begin('window'), disable=epochs.begin('window');
assert.equal(epochs.isCurrent('window',enable),false);
assert.equal(epochs.isCurrent('window',disable),true);
epochs.finish('window',enable);
assert.equal(epochs.isCurrent('window',disable),true);
assert.notEqual(epochs.begin('second'),null);
assert.equal(epochs.begin('third'),null);
epochs.finish('window',disable);
assert.notEqual(epochs.begin('third'),null);
epochs.clear();assert.equal(epochs.latest.size,0);
console.log('PASS: late enable cannot override newer disable; pending requests bounded');

// Exercise the actual production ConfigureAsync method across a lifecycle
// reset, with delayed bus-PID authorization. No compositor dependency needed.
const vm=await import('node:vm');
const extensionSource=(await readFile(new URL('./extension.js',import.meta.url),'utf8'))
  .replace(/^import .*;\n/gm,'')
  .replace('export default class OrionDesktopGlass extends Extension','globalThis.OrionDesktopGlass=class OrionDesktopGlass extends Extension');
const scope={Extension:class{},RequestEpochs,validateRequest,ruleKey,windowMatches,MAX_RULES};
vm.runInNewContext(extensionSource,scope);
const instance=new scope.OrionDesktopGlass();
instance._disabled=false;instance._requests=new RequestEpochs();instance._rules=new Map();
instance._reply=(invocation,value)=>{invocation.value=value;};
instance._status=()=>({ok:true,active:false,reason:'disabled'});
instance._reconcile=()=>{};instance._pruneCallers=()=>{};
let releaseOld,releaseNew;
instance._callerPid=()=>new Promise(resolve=>{releaseOld=resolve;});
const invocationOld={get_sender:()=>':owned'};
const oldPending=instance.ConfigureAsync([100,'Orion',true,24],invocationOld);
const oldRequests=instance._requests;
oldRequests.clear();instance._requests=new RequestEpochs();
instance._callerPid=()=>new Promise(resolve=>{releaseNew=resolve;});
const invocationNew={get_sender:()=>':owned'};
const newPending=instance.ConfigureAsync([100,'Orion',false,24],invocationNew);
assert.equal(oldRequests.serial,1);assert.equal(instance._requests.serial,1);
releaseOld({pid:100,sender:':owned'});await oldPending;
assert.equal(invocationOld.value.reason,'superseded');
assert.equal(instance._rules.size,0);
assert.equal(instance._requests.latest.size,1,'old finally must not delete new request');
releaseNew({pid:100,sender:':owned'});await newPending;
assert.equal(invocationNew.value.reason,'disabled');
assert.equal(instance._requests.latest.size,0);
console.log('PASS: actual delayed authorization cannot cross extension lifecycle');

// The actual wrapper's profile must keep genuine backdrop filtering separate
// from app opacity, and configuring an unchanged window must not stack layers.
const material = {values:new Map(), writes:0};
const blur = {_blurMethod:1,passCount:2,radius:3,_blurRadiusDown:.5,_blurRadiusUp:.75,repaints:0,_repaint(){this.repaints++;}};
const glass = {
  blurCalls:0,
  setBlurRadius(value){this.blur=value;this.blurCalls++;blur.radius=value;blur._blurRadiusDown=.5;blur._blurRadiusUp=.75;},
  setTintStrength(value){this.tint=value;},
  setSurfaceLightEnabled(value){this.light=value;},
  _renderer:{blur,uniforms:{set(name,value){
    assert.equal(Number.isFinite(value),true,`${name} must be finite`);
    if(material.values.get(name)!==value){material.values.set(name,value);material.writes++;}
  }}},
};
instance._applyOptics(glass);
assert.equal(glass.blur,3,'retain two-level blur schedule');
assert.equal(blur._blurRadiusDown,.4725,'5% wider downsample kernel');
assert.equal(blur._blurRadiusUp,.70875,'5% wider upsample kernel');
assert.equal(blur.repaints,1,'kernel update schedules fresh rendering');
assert.equal(glass.tint,0,'no white or coloured veil');
assert.equal(material.values.get('sheen_intensity'),0);
assert.equal(material.values.get('specular_intensity'),0);
assert.equal(material.values.get('displacement_scale'),43.125,'bevel refraction increases by another 15%');
assert.equal(material.values.get('body_refraction_px'),34.5,'whole-sheet refraction increases by another 15%');
assert.ok(material.values.get('body_refraction_px')<=34.5,'body lens remains bounded');
const shader=await readFile(new URL('./shaders/glass.frag',import.meta.url),'utf8');
assert.match(shader,/clamp\(body_refraction_px,\s*0\.0,\s*34\.5\)/,'shader permits the configured body lens instead of silently clamping it');
assert.match(shader,/const float edgeLimitPx = 20\.125;/,'bevel soft cap scales with the field to preserve its shape');
assert.ok(20.125+Math.SQRT2*34.5*2/(3*Math.sqrt(3))<96,'combined refraction stays within the captured backdrop reach');
const writes=material.writes;
instance._applyOptics(glass);
assert.equal(material.writes,writes,'repeated profile application changes no uniforms');
assert.equal(glass.blurCalls,1,'repeated application preserves configured kernel without resetting it');
assert.equal(blur.repaints,1,'unchanged profile schedules no blur repaint');
blur._blurMethod=0;blur._blurRadiusDown=.8;blur._blurRadiusUp=.9;
instance._applyOptics(glass);
// The fake setBlurRadius resets these; custom offsets must not replace them
// when a renderer has explicitly selected a different blur algorithm.
assert.equal(blur._blurRadiusDown,.5);assert.equal(blur._blurRadiusUp,.75);
console.log('PASS: actual bounded edge/body optics, zero tint/sheen and idempotent uniforms');
