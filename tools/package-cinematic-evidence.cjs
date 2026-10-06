// Build a local, timestamped frame player from actual browser/device captures.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve('.cache/cinematic-evidence');
const names=fs.readdirSync(root).filter(n=>n.startsWith('checked-')&&fs.existsSync(path.join(root,n,'scenario.json')));
const order=['checked-three-truth-dry','checked-one-bluff-hit','checked-multi-shot','checked-resume','checked-reduced','checked-low-power'];
names.sort((a,b)=>order.indexOf(a)-order.indexOf(b));
const data=names.map(name=>{
 const dir=path.join(root,name),s=JSON.parse(fs.readFileSync(path.join(dir,'scenario.json')));
 const match=s.logs.filter(l=>l.phase==='CHALLENGE_CALLOUT').at(-1)?.matchId;
 const phases=s.logs.filter(l=>l.matchId===match);const start=phases[0].startedAt;
 const raw=fs.readFileSync(path.join(dir,'native-frames.txt'),'utf8');
 const nativeSub=fs.existsSync(path.join(dir,'native','cine-'+name))?'native/cine-'+name:'native';
 const native=[...raw.matchAll(/FRAME:(\d+):(\d+)\s+END:\1:(\d+)/g)].map(m=>{
  const at=(Number(m[2])+Number(m[3]))/2-s.deviceOffset;
  const p=phases.filter(p=>p.startedAt<=at).at(-1);
  return {at:at-start,src:`${name}/${nativeSub}/frame-${m[1]}.jpeg`,phase:p?.phase||'等待',elapsed:p?Math.round(at-p.startedAt):0,shot:p?.shot||0};
 });
 const web=JSON.parse(fs.readFileSync(path.join(dir,'web-frames.json'))).flatMap((f,i)=>i%2===0?[{at:f.at-start,src:`${name}/web-${String(i+1).padStart(4,'0')}.png`,phase:f.phase,elapsed:f.elapsed}]:[]);
 return {name,spec:s.spec,actions:s.actions,uncertainty:s.clockUncertainty,native,web,phases:phases.map(p=>({...p,at:p.startedAt-start})),duration:Math.max(...native.map(f=>f.at)),errors:s.errors};
});
fs.writeFileSync(path.join(root,'index.html'),`<!doctype html><html lang="zh"><meta charset="utf-8"><title>质疑动画对照验收</title><style>body{background:#17110f;color:#ead9b8;font:16px system-ui;margin:24px}button,select,input{font:inherit;margin:6px;padding:8px}input{width:75%}.pair{display:flex;gap:24px}.pair>div{width:46%;max-width:430px}img{width:100%;max-height:75vh;object-fit:contain;background:#090706}small{display:block;color:#c2ae89}p{max-width:960px;line-height:1.6}</style><h1>质疑至惩罚 · 实际运行关键帧</h1><p>左：锁定提交网页版；右：Mate 90 Pro 模拟器上的 ArkUI。按同一服务端阶段时间对齐。设备截图约每 100–150ms 一帧，时间取截图调用起止的中点；此页面用于检查姿态与阶段连续性，不能证明渲染帧率或音频听感。网页截图含完整页面，尺寸差异不作为缩放比例判断依据。</p><select id="cases"></select><button id="play">播放 / 暂停</button><button id="prev">上一帧</button><button id="next">下一帧</button><div><input id="seek" type="range" min="0" step="1"><output id="time"></output></div><div id="beats"></div><small id="details"></small><div class="pair"><div>网页参考<img id="web"><small id="wl"></small></div><div>鸿蒙实际画面<img id="native"><small id="nl"></small></div></div><script>const data=${JSON.stringify(data)};let item,t=0,playing=false,last=0;const el=id=>document.getElementById(id);data.forEach((d,i)=>el('cases').add(new Option(d.name,i)));function nearest(a){return a.reduce((b,f)=>Math.abs(f.at-t)<Math.abs(b.at-t)?f:b,a[0])}function draw(){for(const k of ['web','native']){const f=nearest(item[k]);if(!f)continue;el(k).src=f.src;el(k==='web'?'wl':'nl').textContent=f.phase+' +'+f.elapsed+'ms · 采样 '+Math.round(f.at)+'ms'}el('seek').value=t;el('time').textContent=Math.round(t)+'ms'}function select(){item=data[el('cases').value];t=0;el('seek').max=item.duration;el('details').textContent=JSON.stringify(item.spec)+' · 时钟测量误差 ±'+item.uncertainty+'ms · '+JSON.stringify(item.actions);el('beats').replaceChildren();item.phases.filter(p=>p.at>=0&&p.at<=item.duration).forEach(p=>{const b=document.createElement('button');b.textContent=p.phase+' #'+(p.shot+1);b.onclick=()=>{t=p.at+100;draw()};el('beats').append(b)});draw()}el('cases').onchange=select;el('seek').oninput=e=>{t=+e.target.value;draw()};el('play').onclick=()=>playing=!playing;el('next').onclick=()=>{t=item.native.find(f=>f.at>t+1)?.at??t;draw()};el('prev').onclick=()=>{t=item.native.filter(f=>f.at<t-1).at(-1)?.at??0;draw()};function tick(now){if(playing){t=Math.min(item.duration,t+Math.min(now-last,100));draw();if(t===item.duration)playing=false}last=now;requestAnimationFrame(tick)}select();requestAnimationFrame(tick);</script></html>`);
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(data,null,2));
console.log(data.map(d=>({name:d.name,native:d.native.length,web:d.web.length,errors:d.errors})));
