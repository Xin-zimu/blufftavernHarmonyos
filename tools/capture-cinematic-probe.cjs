// Capture the unmodified web reference and actual installed ArkUI app together.
// NODE_PATH must expose playwright, or use the bundled runtime path below.
const fs=require('fs'),path=require('path'),{spawn,execFileSync}=require('child_process');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/86139/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const hdc=process.env.HDC_PATH || 'D:/HUAWEI-DEV/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const name=process.argv[2]||'three-truth-dry';
const spec=JSON.parse(process.argv[3]||'{"cards":["A","A","JOKER"],"bluff":false,"hits":[false]}');
const out=path.resolve('.cache/cinematic-evidence',name);fs.mkdirSync(out,{recursive:true});
if(fs.existsSync(path.join(out,'scenario.json')))throw new Error('Use a new capture name; do not mix old frames with a new manifest.');
const post=(p,b={})=>fetch('http://127.0.0.1:3015/'+p,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}).then(r=>r.json());
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function clickNativeText(text) {
 execFileSync(hdc,['shell','uitest dumpLayout -p /data/local/tmp/cine-controls.json'],{windowsHide:true});
 execFileSync(hdc,['file','recv','/data/local/tmp/cine-controls.json',path.join(out,'controls.json')],{windowsHide:true});
 const nodes=[];function visit(n){if(n.attributes?.text===text)nodes.push(n.attributes);for(const c of n.children||[])visit(c)}
 visit(JSON.parse(fs.readFileSync(path.join(out,'controls.json'))));
 if(!nodes.length)return false;
 const [x1,y1,x2,y2]=nodes[0].bounds.match(/\d+/g).map(Number);
 execFileSync(hdc,['shell',`uitest uiInput click ${(x1+x2)/2} ${(y1+y2)/2}`],{windowsHide:true});return true;
}
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH || 'C:/Users/86139/AppData/Local/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-win64/chrome-headless-shell.exe'});
 const context=await browser.newContext({viewport:{width:412,height:914},recordVideo:{dir:out,size:{width:640,height:1416}},reducedMotion:spec.reduced?'reduce':'no-preference'});
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:5173/cinematic-probe.html');await page.waitForSelector('.game-screen');
 if(spec.reduced)await page.getByRole('button',{name:'动画全',exact:true}).click({force:true});
 if(spec.low)await page.getByRole('button',{name:'性能满',exact:true}).click({force:true});
 await post('run',{phase:'TURN',duration:60000});await sleep(400);
 clickNativeText(spec.reduced?'动画全':'动画少');
 clickNativeText(spec.low?'性能满':'性能省');
 clickNativeText(spec.muted?'音效开':'音效关');
 if(!/动画[全少]/.test(fs.readFileSync(path.join(out,'controls.json'),'utf8')))throw new Error('Native app is not on the game page; enter the local fixture room first.');
 const clockBefore=Date.now();
 const deviceNow=Number(execFileSync(hdc,['shell','date +%s%3N'],{windowsHide:true}).toString().trim());
 const clockAfter=Date.now(),deviceOffset=deviceNow-(clockBefore+clockAfter)/2;
 const result=await post('run',{...spec,delay:1500});
 const stop=Date.now()+(result.duration||5000)+500;
 const nativeDir='/data/local/tmp/cine-'+name;
 execFileSync(hdc,['shell','mkdir -p '+nativeDir],{windowsHide:true});
 let nativeOutput='';
 const seconds=Math.ceil(((result.duration||5000)+500)/1000);
 // Device-side loop avoids per-frame CLI startup/transfer overhead. Each frame
 // retains its real capture time; no frames are synthesized or slowed down.
 const cmd=`end=$(( $(date +%s) + ${seconds} )); i=0; while [ $(date +%s) -lt $end ]; do echo FRAME:$i:$(date +%s%3N); snapshot_display -f ${nativeDir}/frame-$i.jpeg -w 640 -h 1416 >/dev/null; echo END:$i:$(date +%s%3N); i=$((i+1)); done`;
 const native=spawn(hdc,['shell',cmd],{windowsHide:true});native.stdout.on('data',d=>nativeOutput+=d.toString());
 const done=new Promise(resolve=>native.on('exit',resolve));
 const frames=[];let idx=0,resumed=false,duplicated=false;const actions=[];
 while(Date.now()<stop){
   const state=await fetch('http://127.0.0.1:3015/state').then(r=>r.json());
   const phaseElapsed=Date.now()-state.game.phaseStartedAt;
   if(spec.coldResume&&!resumed&&state.game.phase==='REVEAL'&&phaseElapsed>=1050){
     resumed=true;actions.push({type:'cold-resume',at:Date.now(),phaseElapsed});
     execFileSync(hdc,['shell','aa force-stop com.blufftavern.app'],{windowsHide:true});
     execFileSync(hdc,['shell','aa start -a EntryAbility -b com.blufftavern.app'],{windowsHide:true});
   }
   if(spec.duplicate&&!duplicated&&state.game.phase==='REVEAL'&&phaseElapsed>=1700){duplicated=true;await post('duplicate');actions.push({type:'duplicate',at:Date.now(),phaseElapsed});}
   const computed=await page.evaluate(()=>({uiPhase:document.querySelector('.cinematic__phase')?.textContent,cards:[...document.querySelectorAll('.reveal-card')].map(e=>({transform:getComputedStyle(e).transform,back:getComputedStyle(e.querySelector('.reveal-card__back')).backfaceVisibility})),staticCards:document.querySelectorAll('.static-reveal-card').length,cylinder:document.querySelector('.revolver-stage__cylinder')?getComputedStyle(document.querySelector('.revolver-stage__cylinder')).transform:null}));
   const at=Date.now();frames.push({at,phase:state.game.phase,elapsed:at-state.game.phaseStartedAt,...computed});
   if(idx++%2===0)await page.screenshot({path:path.join(out,`web-${String(idx).padStart(4,'0')}.png`)});
   await sleep(65);
 }
 await done;fs.writeFileSync(path.join(out,'native-frames.txt'),nativeOutput);
 execFileSync(hdc,['file','recv',nativeDir,path.join(out,'native')],{windowsHide:true});
 fs.writeFileSync(path.join(out,'web-frames.json'),JSON.stringify(frames,null,2));
 fs.writeFileSync(path.join(out,'scenario.json'),JSON.stringify({name,spec,errors,actions,deviceOffset,clockUncertainty:(clockAfter-clockBefore)/2,logs:await fetch('http://127.0.0.1:3015/logs').then(r=>r.json())},null,2));
 await context.close();await browser.close();console.log(JSON.stringify({out,frames:frames.length,nativeFrames:(nativeOutput.match(/FRAME:/g)||[]).length,errors}));
})().catch(e=>{console.error(e);process.exit(1)});
