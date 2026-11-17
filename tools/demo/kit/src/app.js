'use strict';
const stage=document.querySelector('#stage');
const home=document.querySelector('#home');
const scene=document.querySelector('#scene');
const sources=document.querySelector('#sources');
const media=document.querySelector('#media');
const caption=document.querySelector('#caption');
let scale=1, portrait=false, current=null, index=0, playing=true, timer=null, urls=[];
function resize() {
    const width=document.documentElement.clientWidth;
    const height=document.documentElement.clientHeight;
    portrait=height>width;
    scale=portrait ? Math.min(width/1200,height/2000) : Math.min(width/2000,height/1200);
    stage.style.transform=`rotate(${portrait ? 90 : 0}deg) scale(${scale})`;
    stage.style.left=`${portrait ? (width+1200*scale)/2 : (width-2000*scale)/2}px`;
    stage.style.top=`${(height-(portrait ? 2000 : 1200)*scale)/2}px`;
    document.querySelector('#hint').hidden=!portrait;
}
addEventListener('resize',resize);
addEventListener('orientationchange',resize);
resize();
function blobURL(item) {
    const bytes=atob(item.data);
    const array=new Uint8Array(bytes.length);
    for(let i=0;i<bytes.length;i++) array[i]=bytes.charCodeAt(i);
    const url=URL.createObjectURL(new Blob([array],{type:item.type}));
    urls.push(url);
    return url;
}
function clearMedia() {
    clearInterval(timer); timer=null;
    const video=media.querySelector('video');
    if(video) { video.pause(); video.removeAttribute('src'); video.load(); }
    media.textContent='';
    urls.forEach(url=>URL.revokeObjectURL(url)); urls=[];
}
function schedule() {
    clearInterval(timer); timer=null;
    if(playing && !current.items[index].type.startsWith('video'))
        timer=setInterval(()=>show(index+1),5000);
}
function show(next) {
    clearMedia();
    index=(next+current.items.length)%current.items.length;
    const item=current.items[index];
    const video=item.type.startsWith('video');
    const element=document.createElement(video ? 'video' : 'img');
    if(video) {
        element.muted=true; element.loop=true; element.playsInline=true;
        element.setAttribute('playsinline',''); element.setAttribute('webkit-playsinline','');
    } else { element.alt=item.name; element.draggable=false; }
    element.src=blobURL(item); media.appendChild(element);
    caption.textContent=`${current.name} / ${item.name}`;
    document.querySelector('#play').textContent=playing ? '暂停' : '播放';
    if(video && playing) element.play();
    schedule();
}
function enter(id) {
    home.hidden=true; sources.hidden=true; scene.hidden=false;
    current=DATA.find(s=>s.id===id); index=0; playing=true;
    scene.className=id==='farm' ? 'farm' : '';
    if(id==='farm') {
        const iframe=document.createElement('iframe');
        iframe.title='智慧农场'; iframe.srcdoc=FARM; iframe.allowFullscreen=true;
        media.appendChild(iframe);
    } else show(0);
}
function leave() {
    clearMedia(); current=null; scene.hidden=true; sources.hidden=true; home.hidden=false;
}
DATA.forEach((s,i)=>{
    const button=document.createElement('button'); button.className='card';
    button.dataset.scene=s.id;
    const img=document.createElement('img'); img.src=s.thumbnail; img.alt='';
    const label=document.createElement('span'); label.className='label';
    label.innerHTML=`<em>↗</em><strong>${s.name}</strong><small>${s.app}</small>`;
    button.append(img,label); button.onclick=()=>enter(s.id);
    document.querySelector('#cards').appendChild(button);
    (s.credits || s.items).forEach(item=>{
        const credit=document.createElement('div'); credit.className='credit';
        [item.name,`作者：${item.author}`,`来源：${item.source}`,`许可：${item.license}`,
            `许可地址：${item.license_url}`].forEach((text,i)=>{
            const line=document.createElement(i===0 ? 'strong' : 'p');
            line.textContent=text; credit.appendChild(line);
        });
        document.querySelector('#credits').appendChild(credit);
    });
});
document.querySelector('#back').onclick=leave;
document.querySelector('#previous').onclick=()=>show(index-1);
document.querySelector('#next').onclick=()=>show(index+1);
document.querySelector('#play').onclick=()=>{
    playing=!playing;
    const video=media.querySelector('video');
    if(video) { if(playing) video.play(); else video.pause(); }
    document.querySelector('#play').textContent=playing ? '暂停' : '播放';
    schedule();
};
document.querySelector('#sources-open').onclick=()=>{ home.hidden=true; sources.hidden=false; };
document.querySelector('#sources-back').onclick=leave;
document.querySelectorAll('.fullscreen').forEach(button=>{
    button.hidden=!(document.documentElement.requestFullscreen && document.fullscreenEnabled);
    button.onclick=()=>document.documentElement.requestFullscreen();
});
let swipeStart=0;
function stageX(e) {
    const r=stage.getBoundingClientRect();
    return (portrait ? e.clientY-r.top : e.clientX-r.left)/scale;
}
media.addEventListener('pointerdown',e=>{
    swipeStart=stageX(e); media.setPointerCapture(e.pointerId);
});
media.addEventListener('pointerup',e=>{
    if(current.id==='farm') return;
    const delta=stageX(e)-swipeStart;
    if(Math.abs(delta)>80) show(index+(delta<0 ? 1 : -1));
});
