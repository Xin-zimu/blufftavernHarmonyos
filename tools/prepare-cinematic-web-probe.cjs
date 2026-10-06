// Adds only a local harness to the ignored, commit-pinned reference checkout.
// Production GameScreen/CinematicLayer/styles are imported without modification.
const fs=require('fs'),path=require('path');
const root=path.resolve('.cache/web-locked/apps/web');
fs.writeFileSync(path.join(root,'cinematic-probe.html'),`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div><script type="module" src="/src/cinematic-probe.tsx"></script></body></html>`);
fs.writeFileSync(path.join(root,'src/cinematic-probe.tsx'),`
import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { GameScreen } from './screens/GameScreen';
import './styles.css';
function Probe() {
  const [state,setState]=useState<any>(null);
  const [reduced,setReduced]=useState(false), [low,setLow]=useState(false);
  useEffect(()=>{const poll=()=>fetch('http://127.0.0.1:3015/state').then(r=>r.json()).then(s=>setState((old:any)=>old?.game.sequence===s.game.sequence?old:s));poll();const id=setInterval(poll,30);return()=>clearInterval(id)},[]);
  if(!state)return null;
  const noop=()=>{};
  return <div className={'app-shell'+(reduced?' app-shell--reduce-motion':' app-shell--force-motion')+(low?' app-shell--low-power':'')}>
    <GameScreen room={state.room} game={state.game} playerId="p1" audioMuted={true} lowPowerActive={low} reduceMotion={reduced}
      onToggleAudio={noop} onToggleLowPower={()=>setLow(!low)} onToggleReduceMotion={()=>setReduced(!reduced)}
      onPlay={noop} onChallenge={noop} onReturnToRoom={noop} onLeaveRoom={noop} onFullscreen={noop} onUseItem={noop} onShare={noop}/>
  </div>;
}
createRoot(document.getElementById('root')!).render(<Probe/>);
`);
console.log('http://127.0.0.1:5173/cinematic-probe.html');
