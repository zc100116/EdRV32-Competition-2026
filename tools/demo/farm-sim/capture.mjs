// capture.mjs — R5-6/7; real Chromium renders and pointer/script acceptance.
// Host tool, virtual browser clock; run from repository root.
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {mkdirSync} from 'node:fs';
import {homedir} from 'node:os';
const require=createRequire(resolve('build/farm-sim/package.json'));
const {chromium}=require('playwright-core');
const browser=await chromium.launch({
    executablePath:resolve(homedir(),'.cache/ms-playwright/chromium-1248/chrome-linux64/chrome'),
    headless:true,args:['--no-sandbox']
});
mkdirSync('outputs/farm-sim',{recursive:true});
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
for(const [width,height,dpr] of [[1080,1728,2.5],[2400,1080,1],[2560,1600,1],[1280,800,1]]) {
    const fit=await browser.newPage({viewport:{width,height},deviceScaleFactor:dpr,hasTouch:true});
    fit.on('pageerror',error=>{ throw error; });
    await fit.clock.install();
    await fit.clock.pauseAt(Date.now()+1000);
    await fit.goto('file://'+resolve('tools/demo/farm-sim/farm-sim.html'));
    await fit.waitForFunction(()=>[...document.images].every(i=>i.complete));
    const visible=await fit.evaluate(()=>[...document.querySelectorAll('.pen,.animal')].every(el=>{
        const r=el.getBoundingClientRect();
        return r.left>=0 && r.top>=0 && r.right<=innerWidth+.01 && r.bottom<=innerHeight+.01;
    }));
    if(!visible) throw Error(`Clipped pens or animals at ${width}x${height}`);
    await fit.screenshot({path:`outputs/farm-sim/fit-${width}x${height}.png`});
    async function screenPoint(x,y) {
        return fit.evaluate(([x,y])=>{
            const r=farm.getBoundingClientRect();
            return portrait ? [r.right-y*scale,r.top+x*scale] :
                [r.left+x*scale,r.top+y*scale];
        },[x,y]);
    }
    const start=await screenPoint(1370,620), end=await screenPoint(1010,1080);
    await fit.mouse.move(...start);
    await fit.mouse.down();
    await fit.mouse.move(...end,{steps:12});
    await fit.mouse.up();
    if(!await fit.evaluate(()=>animals[4].pen===0 && Math.abs(animals[4].x-1010)<1 &&
        Math.abs(animals[4].y-1080)<1)) throw Error(`Scaled mouse drag failed at ${width}x${height}`);
    await fit.locator('#reset').dispatchEvent('click');
    const touch=await fit.context().newCDPSession(fit);
    for(const [type,p] of [['touchStart',start],['touchMove',end],['touchEnd',end]]) {
        await touch.send('Input.dispatchTouchEvent',{type,
            touchPoints:type==='touchEnd' ? [] : [{x:p[0],y:p[1],id:1}]});
    }
    if(!await fit.evaluate(()=>animals[4].pen===0 && Math.abs(animals[4].x-1010)<1 &&
        Math.abs(animals[4].y-1080)<1)) throw Error(`Scaled touch drag failed at ${width}x${height}`);
    await fit.setViewportSize({width:height,height:width});
    await fit.clock.runFor(100);
    await fit.waitForFunction(()=>portrait===(innerHeight>innerWidth),null,{polling:50});
    await fit.close();
}
await page.locator('#fullscreen').click();
await page.waitForFunction(()=>document.fullscreenElement===document.documentElement);
await page.evaluate(()=>document.exitFullscreen());
const unsupported=await browser.newPage();
unsupported.on('pageerror',error=>{ throw error; });
await unsupported.addInitScript(()=>{
    Object.defineProperty(Element.prototype,'requestFullscreen',{value:undefined});
});
await unsupported.goto('file://'+resolve('tools/demo/farm-sim/farm-sim.html'));
if(await unsupported.locator('#fullscreen').isVisible())
    throw Error('Unsupported fullscreen button is visible');
await unsupported.close();
console.log('PASS fit: four viewports, pens/animals visible, drag, resize and fullscreen');
await browser.close();
