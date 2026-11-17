// capture.mjs — R5-6/7; real Chromium renders and pointer/script acceptance.
// Host tool, virtual browser clock; run from repository root.
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {homedir} from 'node:os';
const require=createRequire(resolve('build/farm-sim/package.json'));
const {chromium}=require('playwright-core');
const browser=await chromium.launch({
    executablePath:resolve(homedir(),'.cache/ms-playwright/chromium-1248/chrome-linux64/chrome'),
    headless:true,args:['--no-sandbox']
});
const page=await browser.newPage({viewport:{width:2000,height:1200},hasTouch:true});
page.on('pageerror',error=>{ throw error; });
await page.clock.install({time:new Date('2026-11-17T00:00:00Z')});
await page.clock.pauseAt(new Date('2026-11-17T00:00:01Z'));
await page.addInitScript(()=>{
    let seed=17;
    Math.random=()=>((seed=(seed*1664525+1013904223)>>>0)/4294967296);
});
await page.goto('file://'+resolve('tools/demo/farm-sim/farm-sim.html'));
await page.waitForFunction(()=>[...document.images].every(i=>i.complete));
await page.screenshot({path:'outputs/farm-sim/initial.png'});
async function capture(name) {
    await page.screenshot({path:`outputs/farm-sim/${name}.png`});
    return page.evaluate(()=>animals.map(a=>({id:a.id,kind:a.kind,x:a.x,y:a.y,w:a.w,h:a.h})));
}
const positions={initial:await capture('initial')};
await page.locator('#demo').dispatchEvent('click');
while(await page.evaluate(()=>script?.index)!==2) await page.clock.runFor(200);
positions.missing=await capture('missing');
while(await page.evaluate(()=>script?.index)!==6) await page.clock.runFor(200);
positions.crossing=await capture('crossing');
while(await page.evaluate(()=>script!==null)) await page.clock.runFor(200);
if(!await page.evaluate(()=>animals.every(a=>a.pen===initial[a.id][1])))
    throw Error('Script did not return animals to their pens');
await page.locator('#demo').dispatchEvent('click');
await page.clock.runFor(4000);
await page.locator('#demo').dispatchEvent('click');
if(await page.evaluate(()=>script!==null)) throw Error('Stop did not cancel script');
await page.locator('#reset').dispatchEvent('click');
await page.mouse.move(1370,620);
await page.mouse.down();
await page.mouse.move(1010,1080,{steps:12});
await page.mouse.up();
if(await page.evaluate(()=>animals[4].pen)!==0) throw Error('Mouse cross-pen drag failed');
await page.locator('#reset').dispatchEvent('click');
const cdp=await page.context().newCDPSession(page);
for(const [type,x,y] of [['touchStart',1790,1060],['touchMove',1980,1060],['touchEnd',1980,1060]]) {
    await cdp.send('Input.dispatchTouchEvent',{type,
        touchPoints:type==='touchEnd' ? [] : [{x,y,id:1}]});
}
if(await page.evaluate(()=>animals[8].pen)!==-1) throw Error('Touch outside drag failed');
await page.clock.runFor(12000);
if(!await page.evaluate(()=>animals[8].x>2000)) throw Error('Outside animal did not leave');
const {writeFileSync}=await import('node:fs');
writeFileSync('build/farm-sim/positions.json',JSON.stringify(positions,null,2));
console.log('PASS browser: script, stop, reset, mouse and touch drag, outside exit');
await browser.close();
