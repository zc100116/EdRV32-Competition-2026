// capture.mjs — showcase R5-8/9: offline browsing and tablet/phone acceptance.
// Host Chromium; screenshots are written to outputs/demo-kit/.
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {homedir} from 'node:os';
import {mkdirSync,statSync} from 'node:fs';
const require=createRequire(resolve('build/farm-sim/package.json'));
const {chromium}=require('playwright-core');
const output='outputs/demo-kit';
mkdirSync(output,{recursive:true});
const html=resolve('tools/demo/kit/demo-kit.html');
if(statSync(html).size>45*1024*1024) throw Error('HTML exceeds 45 MB');
const browser=await chromium.launch({
    executablePath:resolve(homedir(),'.cache/ms-playwright/chromium-1248/chrome-linux64/chrome'),
    headless:true,args:['--no-sandbox']
});
const page=await browser.newPage({viewport:{width:2560,height:1600},hasTouch:true});
const requests=[];
await page.route('**/*',route=>{
    if(/^https?:/.test(route.request().url())) {
        requests.push(route.request().url()); return route.abort();
    }
    return route.continue();
});
page.on('pageerror',error=>{throw error;});
await page.addInitScript(()=>{
    window.liveURLs=new Set();
    const create=URL.createObjectURL.bind(URL), revoke=URL.revokeObjectURL.bind(URL);
    URL.createObjectURL=blob=>{const url=create(blob);liveURLs.add(url);return url;};
    URL.revokeObjectURL=url=>{liveURLs.delete(url);revoke(url);};
});
await page.clock.install({time:new Date('2026-11-17T00:00:00Z')});
await page.clock.pauseAt(new Date('2026-11-17T00:00:01Z'));
await page.goto('file://'+html);
await page.waitForFunction(()=>[...document.images].every(i=>i.complete));
if(await page.locator('.card').count()!==7) throw Error('Expected seven scene cards');
if(await page.evaluate(()=>liveURLs.size)!==0) throw Error('Home decoded full media');
await page.screenshot({path:`${output}/home-tablet.png`});
const ids=await page.locator('.card').evaluateAll(cards=>cards.map(c=>c.dataset.scene));
for(const id of ids) {
    await page.locator(`[data-scene="${id}"]`).click();
    if(id==='farm') {
        await page.frameLocator('iframe').locator('.animal').first().waitFor();
    } else {
        await page.waitForFunction(()=>{
            const e=document.querySelector('#media').firstElementChild;
            return e.tagName==='IMG' ? e.complete : e.readyState>=2;
        },null,{polling:50});
        if(id==='traffic' || id==='dance' || id==='helmet') {
            await page.waitForFunction(()=>!document.querySelector('video').paused,
                null,{polling:50});
        }
    }
    await page.screenshot({path:`${output}/${id}-tablet.png`});
    if(id!=='farm') {
        await page.locator('#play').click();
        const paused=await page.evaluate(()=>index);
        await page.clock.runFor(5100);
        if(await page.evaluate(()=>index)!==paused) throw Error('Pause changed image');
        if(await page.locator('video').count() &&
            !await page.locator('video').evaluate(v=>v.paused))
            throw Error('Pause did not stop video');
        const count=await page.evaluate(()=>current.items.length);
        for(let i=0;i<count;i++) {
            await page.locator('#next').click();
            await page.waitForFunction(()=>{
                const e=document.querySelector('#media').firstElementChild;
                return e.tagName==='IMG' ? e.complete : e.readyState>=2;
            },null,{polling:50});
            if(await page.evaluate(()=>liveURLs.size)!==1) throw Error('Media URL leaked');
        }
        await page.locator('#previous').click();
        if(await page.evaluate(()=>index)!==(paused+count-1)%count) throw Error('Previous failed');
        if(id==='zoo') {
            await page.locator('#play').click();
            const start=await page.evaluate(()=>index);
            await page.clock.runFor(5001);
            if(await page.evaluate(()=>index)!==(start+1)%count)
                throw Error('Image auto advance failed');
        }
    }
    await page.locator('#back').click();
    if(await page.evaluate(()=>liveURLs.size)!==0) throw Error('Leaving scene leaked URLs');
    if(await page.locator('#media > *').count()) throw Error('Leaving scene kept media');
}
await page.locator('#sources-open').click();
if(await page.locator('#credits a').count()) throw Error('Source addresses are external links');
await page.screenshot({path:`${output}/sources-tablet.png`});
await page.locator('#sources-back').click();
await page.setViewportSize({width:1080,height:1728});
await page.clock.runFor(100);
await page.waitForFunction(()=>portrait,null,{polling:50});
await page.screenshot({path:`${output}/home-phone.png`});
await page.locator('[data-scene="zoo"]').click();
await page.locator('#play').click();
const points=await page.evaluate(()=>{
    const r=stage.getBoundingClientRect();
    return [[r.right-500*scale,r.top+1400*scale],[r.right-500*scale,r.top+600*scale]];
});
await page.mouse.move(...points[0]);await page.mouse.down();
await page.mouse.move(...points[1],{steps:10});await page.mouse.up();
if(await page.evaluate(()=>index)!==1) throw Error('Rotated swipe failed');
const cdp=await page.context().newCDPSession(page);
for(const [type,p] of [['touchStart',points[1]],['touchMove',points[0]],['touchEnd',points[0]]]) {
    await cdp.send('Input.dispatchTouchEvent',{type,
        touchPoints:type==='touchEnd' ? [] : [{x:p[0],y:p[1],id:1}]});
}
if(await page.evaluate(()=>index)!==0) throw Error('Rotated touch swipe failed');
await page.locator('.fullscreen').click();
await page.waitForFunction(()=>document.fullscreenElement===document.documentElement,
    null,{polling:50});
await page.evaluate(()=>document.exitFullscreen());
await page.locator('#back').click();
if(requests.length) throw Error('Unexpected network requests: '+requests.join(', '));
console.log('PASS: seven scenes, offline (0 network requests), controls, URLs, rotation;',
    statSync(html).size,'bytes');
await browser.close();
