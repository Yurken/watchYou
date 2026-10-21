/* watch you AI helpers. No secrets in configuration, storage, or exported backups. */
(function(root,factory){const a=factory();if(typeof module==='object'&&module.exports)module.exports=a;else root.AIHelpers=a;})(typeof globalThis!=='undefined'?globalThis:this,function(){
'use strict';
const PROTOCOLS=['chat','responses','anthropic'];
const MODULES=['today','mood','sleep','heart','recovery','activity','habits','trends','assistant'];
const SCOPES=['sleep','heart','activity','habits','context'];
function profile(id='default',name='我的 AI 服务'){return {id,name,baseURL:'',protocol:'chat',model:'',auth:'bearer',temperature:'',maxTokens:1200,tokenField:'max_tokens',timeout:45,allowLocalHTTP:false};}
function defaults(){return {version:2,active:'default',profiles:[profile()],mode:'demo',auto:true,dailyLimit:20,modules:Object.fromEntries(MODULES.map(m=>[m,true])),scopes:{sleep:true,heart:true,activity:true,habits:false,context:false}};}
function isPrivateHost(h){h=String(h).toLowerCase().replace(/^\[|\]$/g,'');if(h==='localhost'||h==='::1')return true;if(!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(h))return false;const n=h.split('.').map(Number);if(n.some(x=>x>255))return false;return n[0]===127||n[0]===10||(n[0]===192&&n[1]===168)||(n[0]===172&&n[1]>=16&&n[1]<=31);}
function normalizeBase(input,allowLocalHTTP=false){
 if(String(input).length>2048)throw Error('URL 过长');let u;try{u=new URL(String(input).trim());}catch{throw Error('URL 无效，请填写包含 https:// 的完整地址');}
 if(u.username||u.password||u.search||u.hash)throw Error('URL 不可包含用户名、密码、查询参数或片段；密钥请单独填写');
 if(u.protocol!=='https:'&&!(u.protocol==='http:'&&allowLocalHTTP&&isPrivateHost(u.hostname)))throw Error('要求 HTTPS；仅显式允许的本机或私网测试地址可用 HTTP');
 u.pathname=u.pathname.replace(/\/+$/,'').replace(/\/(chat\/completions|responses|messages|models)$/,'');
 return u.origin+(u.pathname==='/'?'':u.pathname);
}
function endpoint(p,kind='generate'){const suffix=kind==='models'?'/models':({chat:'/chat/completions',responses:'/responses',anthropic:'/messages'}[p.protocol]);if(!suffix)throw Error('不支持的协议');return normalizeBase(p.baseURL,p.allowLocalHTTP)+suffix;}
function cleanProfile(x){if(!x||typeof x!=='object')throw Error('服务配置无效');const p=profile();p.id=/^[\w-]{1,80}$/.test(x.id)?x.id:p.id;p.name=typeof x.name==='string'?x.name.slice(0,60):p.name;p.protocol=PROTOCOLS.includes(x.protocol)?x.protocol:'chat';p.allowLocalHTTP=x.allowLocalHTTP===true;p.baseURL=typeof x.baseURL==='string'&&x.baseURL.trim()?normalizeBase(x.baseURL,p.allowLocalHTTP):'';p.model=typeof x.model==='string'?x.model.trim().slice(0,180):'';p.auth=['bearer','x-api-key','none'].includes(x.auth)?x.auth:'bearer';p.temperature=x.temperature===''||x.temperature===undefined?'':Number(x.temperature);if(p.temperature!==''&&(!Number.isFinite(p.temperature)||p.temperature<0||p.temperature>2))throw Error('Temperature 需留空或为 0–2');p.maxTokens=Number(x.maxTokens??1200);p.timeout=Number(x.timeout??45);if(!Number.isInteger(p.maxTokens)||p.maxTokens<64||p.maxTokens>16000)throw Error('输出上限需为 64–16000 的整数');if(!Number.isInteger(p.timeout)||p.timeout<5||p.timeout>180)throw Error('超时需为 5–180 秒的整数');p.tokenField=x.tokenField==='max_completion_tokens'?'max_completion_tokens':'max_tokens';return p;}
function sanitizeConfig(x){if(!x||x.version!==2||!Array.isArray(x.profiles)||!x.profiles.length||x.profiles.length>8)throw Error('AI 配置版本或服务数量无效');const d=defaults();d.profiles=x.profiles.map(cleanProfile);if(new Set(d.profiles.map(p=>p.id)).size!==d.profiles.length)throw Error('服务 ID 重复');d.active=d.profiles.some(p=>p.id===x.active)?x.active:d.profiles[0].id;d.mode='demo';d.auto=x.auto!==false;d.dailyLimit=Number.isInteger(x.dailyLimit)&&x.dailyLimit>=1&&x.dailyLimit<=200?x.dailyLimit:20;for(const k of MODULES)d.modules[k]=x.modules?.[k]!==false;for(const k of SCOPES)d.scopes[k]=x.scopes?.[k]===true;return d;}
function request(p,key,system,user){
 p=cleanProfile(p);if(!p.model)throw Error('请填写 model');if(p.auth!=='none'&&!key)throw Error('请填写当前服务的 API Key，或明确选择无认证');
 const headers={'Content-Type':'application/json'};if(key&&p.auth==='bearer')headers.Authorization='Bearer '+key;if(key&&p.auth==='x-api-key')headers['x-api-key']=key;
 let body;if(p.protocol==='responses')body={model:p.model,instructions:system,input:user,max_output_tokens:p.maxTokens,store:false,stream:false};
 else if(p.protocol==='anthropic'){headers['anthropic-version']='2023-06-01';body={model:p.model,system,messages:[{role:'user',content:user}],max_tokens:p.maxTokens,stream:false};}
 else body={model:p.model,messages:[{role:'system',content:system},{role:'user',content:user}],[p.tokenField]:p.maxTokens,stream:false};
 if(p.temperature!=='')body.temperature=p.temperature;
 return {url:endpoint(p),options:{method:'POST',headers,body:JSON.stringify(body),credentials:'omit',redirect:'error',referrerPolicy:'no-referrer'}};
}
function extractText(protocol,x){let text='';if(protocol==='responses'){text=x.output_text||x.output?.flatMap(o=>o.content||[]).filter(t=>t.type==='output_text').map(t=>t.text).join('\n')||'';if(x.status==='incomplete')throw Error('模型输出未完成，可能达到 token 上限');}else if(protocol==='anthropic'){text=x.content?.filter(t=>t.type==='text').map(t=>t.text).join('\n')||'';if(x.stop_reason==='max_tokens')throw Error('模型输出被截断');}else{const z=x.choices?.[0];if(z?.finish_reason==='length')throw Error('模型输出被截断');text=z?.message?.content||'';}if(typeof text!=='string'||!text.trim())throw Error('返回中没有可用文本；模型可能拒绝回答或协议不匹配');return text;}
function parseResult(text,facts,{hasContext=false}={}){
 if(typeof text!=='string'||text.length>128000)throw Error('模型返回过大或不是文本');const source=String(text).trim().replace(/^```(?:json)?\s*/i,'').replace(/\s*```$/,'');let x;try{x=JSON.parse(source);}catch{throw Error('模型未返回有效 JSON，未把原始输出当作健康结论');}
 const ids=new Set(facts.map(f=>f.id));if(!x||typeof x.summary!=='string'||!x.summary.trim()||x.summary.length>1800)throw Error('分析摘要格式无效');
 if(!Array.isArray(x.evidenceIds)||x.evidenceIds.length>30||x.evidenceIds.some(id=>!ids.has(id)))throw Error('分析引用了不存在的证据，结果已拦截');
 if(facts.length&&x.evidenceIds.length===0)throw Error('分析没有引用观测依据');
 const strs=(a,n)=>{if(!Array.isArray(a)||a.length>n||a.some(t=>typeof t!=='string'||t.length>700))throw Error('建议或不确定性字段无效');return a;};
 const result={summary:x.summary,evidenceIds:x.evidenceIds,uncertainties:strs(x.uncertainties,8),suggestions:strs(x.suggestions,6),emotion:null};
 if(x.emotion!=null){const e=x.emotion;if(!['estimated','insufficient'].includes(e.status)||typeof e.label!=='string'||e.label.length>40||!['low','moderate','high','unknown'].includes(e.arousal)||!['negative','neutral','positive','unknown'].includes(e.valence))throw Error('情绪字段格式无效');if(!hasContext&&e.valence!=='unknown')throw Error('缺少可授权的情境证据，不能输出确定的愉悦度方向');if(!hasContext&&!['可能偏平稳','可能偏紧绷','可能偏活跃','暂无法判断'].includes(e.label))throw Error('仅凭生理摘要不能断言具体心理情绪');if(e.status==='insufficient'&&(e.arousal!=='unknown'||e.valence!=='unknown'))throw Error('数据不足状态不能带有确定的情绪坐标');result.emotion={status:e.status,label:e.label,arousal:e.arousal,valence:e.valence,evidenceStrength:'有限 · 未校准'};}
 return result;
}
function safeError(e){const m=String(e?.message||e);if(e?.name==='AbortError')return '请求已取消或超时；未生成新结论';if(/fetch|network|load|cors/i.test(m))return '连接失败：请检查网络、HTTPS、浏览器 CORS 与服务地址；原型不会绕过安全限制';return m.slice(0,180);}
return {PROTOCOLS,MODULES,SCOPES,defaults,profile,isPrivateHost,normalizeBase,endpoint,cleanProfile,sanitizeConfig,request,extractText,parseResult,safeError};
});
