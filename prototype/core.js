/* HealthHub prototype domain helpers. All inputs in the UI are synthetic fixtures. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.HealthCore=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
'use strict';
const clamp=(x,lo,hi)=>Math.max(lo,Math.min(hi,x));
function unionMinutes(intervals){
 const rows=intervals.filter(x=>Number.isFinite(x.start)&&Number.isFinite(x.end)&&x.end>x.start).map(x=>({...x})).sort((a,b)=>a.start-b.start);
 if(!rows.length)return 0;let start=rows[0].start,end=rows[0].end,total=0;
 for(const x of rows.slice(1)){if(x.start<=end)end=Math.max(end,x.end);else{total+=end-start;start=x.start;end=x.end;}}
 return total+end-start;
}
function resolveSleep(samples,preferred){
 const valid=samples.filter(s=>['core','deep','rem','awake','unspecified'].includes(s.stage)&&Number.isFinite(s.start)&&Number.isFinite(s.end)&&s.end>s.start);
 const cuts=[...new Set(valid.flatMap(s=>[s.start,s.end]))].sort((a,b)=>a-b);const result=[];
 for(let i=0;i<cuts.length-1;i++){
  const start=cuts[i],end=cuts[i+1];const candidates=valid.filter(s=>s.start<=start&&s.end>=end);
  if(!candidates.length)continue;
  candidates.sort((a,b)=>(a.source===preferred?0:1)-(b.source===preferred?0:1)||((a.stage==='unspecified')?1:0)-((b.stage==='unspecified')?1:0)||String(a.id).localeCompare(String(b.id)));
  const chosen=candidates[0];const prev=result.at(-1);
  if(prev&&prev.end===start&&prev.stage===chosen.stage&&prev.source===chosen.source)prev.end=end;
  else result.push({start,end,stage:chosen.stage,source:chosen.source});
 }
 const totals={core:0,deep:0,rem:0,awake:0,unspecified:0};for(const s of result)totals[s.stage]+=s.end-s.start;
 return {intervals:result,totals,asleep:totals.core+totals.deep+totals.rem+totals.unspecified,awake:totals.awake};
}
function sleepScore({asleep,awake,goal=480,midpointDeviation=18,nights=28,coverage=1}){
 if(![asleep,awake,goal,midpointDeviation,coverage].every(Number.isFinite)||asleep<=0||awake<0||goal<=0||coverage<.8||nights<7)return null;
 const duration=100*clamp(asleep/goal,0,1),regularity=100*clamp(1-Math.abs(midpointDeviation)/120,0,1),continuity=100*asleep/(asleep+awake);
 return {value:Math.round(.5*duration+.25*regularity+.25*continuity),duration,regularity,continuity,version:'sleep-experimental-0.1'};
}
function recoveryScore({hrv,rhr,baselineHRV=48,baselineRHR=58,logHRVScale=.18,rhrScale=3,sleep,nights=28,coverage=1}){
 if(![hrv,rhr,baselineHRV,baselineRHR,logHRVScale,rhrScale,sleep,coverage].every(Number.isFinite)||hrv<=0||rhr<=0||baselineHRV<=0||logHRVScale<=0||rhrScale<=0||nights<14||coverage<.8)return null;
 const h=clamp((Math.log(hrv)-Math.log(baselineHRV))/logHRVScale,-3,3),r=clamp((rhr-baselineRHR)/rhrScale,-3,3);
 const parts={intercept:65,hrv:12*h,rhr:-8*r,sleep:.2*(sleep-70)};
 return {value:Math.round(clamp(Object.values(parts).reduce((a,b)=>a+b,0),0,100)),parts,version:'recovery-experimental-0.1'};
}
function addEvent(events,event){if(!event||typeof event.id!=='string')throw Error('Missing event id');return events.some(x=>x.id===event.id)?events:[...events,event];}
function trainingLoad(minutes,rpe){if(!Number.isFinite(minutes)||!Number.isFinite(rpe)||minutes<=0||minutes>1440||!Number.isInteger(rpe)||rpe<0||rpe>10)return null;return Math.round(minutes*rpe);}
function validateReminderPrefs(x){
 const d={sleepPrep:false,habits:false,water:false,maintenance:false,quietStart:'22:00',quietEnd:'07:00',dailyCap:3};
 if(!x||typeof x!=='object')return d;
 const time=k=>{const v=typeof x[k]==='string'?x[k]:d[k];return /^([01]\d|2[0-3]):[0-5]\d$/.test(v)?v:d[k];};
 const cap=Number(x.dailyCap);
 return {sleepPrep:x.sleepPrep===true,habits:x.habits===true,water:x.water===true,maintenance:x.maintenance===true,quietStart:time('quietStart'),quietEnd:time('quietEnd'),dailyCap:Number.isInteger(cap)?clamp(cap,1,10):d.dailyCap};
}
function validateBackup(x){
 if(!x||!['healthhub.demo.v1','watchyou.demo.v2'].includes(x.schema)||x.synthetic!==true||!x.state||typeof x.state!=='object')throw Error('仅支持此原型导出的演示备份');
 const s=x.state;
 if(!Array.isArray(s.moods)||s.moods.length>500||!Array.isArray(s.events)||s.events.length>1000)throw Error('记录格式或数量无效');
 for(const m of s.moods){if(typeof m.id!=='string'||!/^[A-Za-z0-9_-]{1,100}$/.test(m.id)||!Number.isFinite(m.valence)||m.valence < -1||m.valence>1||typeof m.note!=='string'||m.note.length>300)throw Error('情绪记录无效');}
 const events=s.events.map(e=>{if(typeof e.id!=='string'||!/^[A-Za-z0-9_-]{1,100}$/.test(e.id)||typeof e.kind!=='string'||!['water','mindful'].includes(e.kind)||!Number.isFinite(e.amount)||e.amount<=0||e.amount>10000||typeof e.pending!=='boolean')throw Error('事件记录无效');return {id:e.id,kind:e.kind,amount:e.amount,pending:e.pending};});
 const uniqueEvents=events.filter((e,i,a)=>a.findIndex(t=>t.id===e.id)===i);
 return {moods:s.moods.map(m=>({id:m.id,valence:m.valence,note:m.note,tags:Array.isArray(m.tags)?m.tags.filter(t=>typeof t==='string').slice(0,8):[],time:typeof m.time==='string'?m.time.slice(0,30):'演示记录',kind:m.kind==='daily'?'daily':'momentary',pending:!!m.pending})),events:uniqueEvents,goal:Number.isFinite(s.goal)?clamp(s.goal,360,600):480,preferredHR:['A','B'].includes(s.preferredHR)?s.preferredHR:'A',preferredSleep:['A','B'].includes(s.preferredSleep)?s.preferredSleep:'B',reminders:!!s.reminders,waterGoal:Number.isFinite(s.waterGoal)?clamp(Math.round(s.waterGoal),500,4000):2000,rpe:Number.isFinite(s.rpe)?clamp(Math.round(s.rpe),0,10):null,reminderPrefs:validateReminderPrefs(s.reminderPrefs)};
}
return {clamp,unionMinutes,resolveSleep,sleepScore,recoveryScore,addEvent,trainingLoad,validateReminderPrefs,validateBackup};
});
