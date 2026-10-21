"""Prototype-only tests. Provider traffic is intercepted; no real key or health data."""
from pathlib import Path
import json,time,shutil,os
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name,ok):
    if not ok: raise AssertionError(name)
    results.append({'test':name,'status':'PASS'})
    print('PASS '+name,flush=True)
with sync_playwright() as p:
    exe=os.environ.get('CHROMIUM_BIN') or shutil.which('chromium')
    b=p.chromium.launch(executable_path=exe,headless=True,args=['--no-sandbox']) if exe else p.chromium.launch(channel='chrome',headless=True,args=['--no-sandbox'])
    ctx=b.new_context(viewport={'width':1440,'height':1180},accept_downloads=True)
    pg=ctx.new_page();pg.set_default_timeout(6000);errors=[];requests=[];captured=[]
    pg.on('pageerror',lambda e:errors.append(str(e)))
    pg.on('request',lambda r:requests.append(r.url) if r.url.startswith(('https:','http:')) else None)
    pg.evaluate("Object.defineProperty(window,'localStorage',{value:{data:{},getItem(k){return this.data[k]??null},setItem(k,v){this.data[k]=v},removeItem(k){delete this.data[k]}}})")
    pg.set_content((ROOT/'prototype/index.html').read_text(),wait_until='domcontentloaded')
    check('brand is watch you',pg.title().startswith('watch you'))
    check('default view makes zero provider requests',not requests)
    for route in ['today','sleep','heart','mood','assistant','recovery','activity','habits','trends','sources','settings','aiSettings','more']:
        pg.evaluate(f"go('{route}')")
        t=pg.locator('#screen').inner_text()
        check(f'route {route} renders without device-count UI',bool(t.strip()) and not any(x in t for x in ['手表 A','手表 B','Apple Watch A','Apple Watch B','双表','两块手表']))
    pg.evaluate("go('mood')")
    check('emotion is inferred by default, no mandatory slider',pg.locator('#mood-slider').count()==0 and '自动分析' in pg.locator('#screen').inner_text())
    check('emotion displays uncertainty not a calibrated probability','有限' in pg.locator('#screen').inner_text() and '待更多情境' in pg.locator('#screen').inner_text())
    pg.evaluate("showContext()")
    pg.fill('#ai-context','TEST CONTEXT ONLY, NOT REAL HEALTH DATA')
    pg.evaluate('saveContext()')
    check('optional text excluded unless its scope is enabled',not pg.evaluate("factsFor('mood').some(x=>x.scope==='context')"))
    check('optional text is not exported', 'TEST CONTEXT ONLY' not in pg.evaluate('JSON.stringify(backup())'))
    for state in ['baseline','stale','empty']:
        pg.evaluate(f"changeScenario('{state}');go('mood')")
        check(f'{state} emotion abstains', '暂无法判断' in pg.locator('#screen').inner_text() and pg.locator('#analyze-mood').is_disabled())
    pg.evaluate("changeScenario('ready');go('habits');addWater('phone',250)")
    check('phone water entry works',pg.evaluate('phoneWater()')==1000)
    pg.evaluate("toggleConnection();watchPage='water';renderWatch();addWater('watch',250)")
    check('offline event stays local and pending',pg.evaluate('phoneWater()')==1000 and pg.evaluate('S.events.filter(x=>x.pending).length')==1)
    pg.evaluate('toggleConnection()')
    check('reconnect merges once',pg.evaluate('phoneWater()')==1250)
    pg.evaluate('go("habits");undoWater()')
    check('water undo removes the last entry once',pg.evaluate('phoneWater()')==1000)
    pg.evaluate('undoWater()')
    check('second undo restores the removed entry',pg.evaluate('phoneWater()')==1250)
    pg.evaluate('undoWater();undoWater()')
    check('undo without pending removal is a no-op',pg.evaluate('phoneWater()')==1250)
    pg.evaluate('setWaterGoal(1500)')
    check('custom water goal replaces the sample goal',pg.evaluate('S.waterGoal')==1500 and '/ 1500' in pg.evaluate('renderHabits()'))
    pg.evaluate('setWaterGoal(99999)')
    check('out-of-range water goal is clamped',pg.evaluate('S.waterGoal')==4000)
    pg.evaluate("go('activity');setRPE(4)")
    check('RPE persists and load equals minutes times RPE',pg.evaluate('S.rpe')==4 and '128' in pg.evaluate('renderActivity()'))
    pg.evaluate('setRPE(11)')
    check('invalid RPE is rejected without changing state',pg.evaluate('S.rpe')==4)
    pg.evaluate('setRPE(null)')
    check('cleared RPE produces no load number',pg.evaluate('S.rpe') is None and '等待你补充' in pg.evaluate('renderActivity()') and '任意单位' not in pg.evaluate('renderActivity()'))
    pg.evaluate("go('sleep')")
    check('nap is shown separately from the main episode', '不计入主睡眠评分' in pg.locator('#screen').inner_text())
    pg.evaluate("go('recovery')")
    check('recovery exposes baseline window, valid days and sample time', all(x in pg.locator('#screen').inner_text() for x in ['有效日','样本','基线','无缺失项']))
    pg.evaluate("changeScenario('baseline');go('recovery')")
    check('baseline scenario names the missing input', '不足' in pg.locator('#screen').inner_text() and '不输出总分' in pg.locator('#screen').inner_text())
    pg.evaluate("changeScenario('ready');go('habits');S.reminders=true;showReminderSettings()")
    pg.check('#rp-water')
    pg.fill('#rp-cap','2')
    pg.evaluate('saveReminderPrefs()')
    check('reminder categories and daily cap persist',pg.evaluate('S.reminderPrefs.water')==True and pg.evaluate('S.reminderPrefs.dailyCap')==2)
    check('reminder summary shows categories and quiet hours', '饮水' in pg.evaluate('reminderSummary()') and '静默' in pg.evaluate('reminderSummary()'))
    pg.evaluate("S.reminders=false")
    pg.evaluate("go('sources');setSource('HR','B');go('heart')")
    check('generic source preference selects without averaging','82' in pg.locator('.hr-readout').first.inner_text())
    pg.evaluate("setSource('HR','A');go('aiSettings')")
    pg.fill('#ai-name','Test profile')
    pg.fill('#ai-url','https://model.example/v1')
    pg.fill('#ai-model','mock-model')
    pg.fill('#ai-key','TEST_ONLY_NOT_A_REAL_KEY')
    pg.select_option('#ai-mode','live')
    pg.uncheck('#ai-auto')
    pg.click('#save-ai')
    check('saving profile does not send a request',not requests)
    check('key is absent from stored configuration','TEST_ONLY_NOT_A_REAL_KEY' not in pg.evaluate('JSON.stringify(localStorage.data)'))
    check('key absent from backup','TEST_ONLY_NOT_A_REAL_KEY' not in pg.evaluate('JSON.stringify(backup())'))
    check('stored/backup mode is safe demo',pg.evaluate('backup().aiConfig.mode')=='demo')
    check('watch does not invent a live summary before inference','等待 AI 分析' in pg.evaluate('renderWatchOverview()'))
    behavior={'kind':'ok'}
    def mock(route):
        req=route.request
        if req.method=='OPTIONS':route.fulfill(status=204,headers={'access-control-allow-origin':'*','access-control-allow-headers':'*'});return
        raw=req.post_data
        body=json.loads(raw) if raw else None
        captured.append({'url':req.url,'method':req.method,'body':body})
        hdr={'access-control-allow-origin':'*','content-type':'application/json'}
        if behavior['kind']=='401':route.fulfill(status=401,headers=hdr,body='{}');return
        if req.method=='GET':route.fulfill(status=200,headers=hdr,body=json.dumps({'data':[{'id':'mock-model'},{'id':'mock-model-2'}]}));return
        user=body.get('input') if '/responses' in req.url else body['messages'][-1]['content']
        if user=='只回复：连接正常':text='连接正常'
        else:
            packet=json.loads(user);ids=[x['id'] for x in packet['facts'][:2]]
            answer={'summary':'合成数据只支持有限的状态解释。','evidenceIds':ids,'uncertainties':['无法确定真实情绪。'],'suggestions':['先观察趋势。'],'emotion':{'status':'estimated','label':'可能偏平稳','arousal':'low','valence':'unknown'} if packet['module']=='mood' else None}
            if behavior['kind']=='unknown-evidence':answer['evidenceIds']=['DOES_NOT_EXIST']
            if behavior['kind']=='html':answer['summary']='<img src=x onerror="window.PWNED=true">合成示例'
            text=json.dumps(answer,ensure_ascii=False)
            if behavior['kind']=='invalid-json':text='not json'
        if '/responses' in req.url:reply={'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':text}]}]}
        elif '/messages' in req.url:reply={'content':[{'type':'text','text':text}],'stop_reason':'end_turn'}
        else:reply={'choices':[{'message':{'content':text},'finish_reason':'stop'}]}
        route.fulfill(status=200,headers=hdr,body=json.dumps(reply))
    pg.route('https://model.example/**',mock)
    pg.evaluate("prepareConnection('models')")
    check('model list requires explicit target confirmation',pg.locator('#confirm-connection').is_visible())
    pg.click('#confirm-connection');pg.wait_for_function('AIBusy===null && AIModels.length===2')
    check('model list adapter parses IDs',pg.evaluate('AIModels')==['mock-model','mock-model-2'])
    pg.evaluate('chooseModel(0)')
    pg.evaluate("prepareConnection('test')")
    pg.click('#confirm-connection');pg.wait_for_function('AIBusy===null')
    check('connection test succeeds with mock only','连接测试成功' in pg.locator('#modal').inner_text())
    check('test contains no health facts','facts' not in json.dumps(captured[-1]['body']))
    pg.evaluate("closeModal();go('mood');runAI('mood')")
    check('first health analysis previews scope and target',pg.locator('#confirm-ai-consent').is_visible() and 'model.example' in pg.locator('#modal').inner_text())
    pg.click('#confirm-ai-consent');pg.wait_for_function("AIResults.mood?.mode==='live' && AIBusy===null")
    check('mock response replaces demo, preserves source label',pg.evaluate('AIResults.mood.model')=='mock-model')
    check('unsupported positive/negative emotion remains unknown',pg.evaluate('AIResults.mood.emotion.valence')=='unknown')
    check('live result still identifies synthetic observations','合成' in pg.locator('body').inner_text() or '模拟' in pg.locator('body').inner_text())
    check('unapproved optional text is absent from request', 'TEST CONTEXT ONLY' not in json.dumps(captured[-1]['body']))
    before=len(captured)
    pg.evaluate("AIConfig.auto=true;scheduleAutoAI()")
    pg.wait_for_timeout(700)
    check('same evidence packet is not automatically resent',len(captured)==before)
    pg.evaluate("AIConfig.auto=false;go('aiSettings')")
    pg.fill('#ai-model','mock-model-2');pg.click('#save-ai')
    check('model change revokes previous consent',pg.evaluate('AIGrant===null'))
    pg.evaluate("go('mood');runAI('mood')")
    check('new model asks consent again',pg.locator('#confirm-ai-consent').is_visible())
    pg.click('#confirm-ai-consent');pg.wait_for_function("AIResults.mood?.model==='mock-model-2' && AIBusy===null")
    check('valid new model result is applied',pg.evaluate('AIResults.mood.model')=='mock-model-2')
    behavior['kind']='unknown-evidence'
    pg.evaluate("invalidateAI();runAI('mood')")
    pg.wait_for_function("AIBusy===null && AIError!==''")
    check('unknown evidence does not produce a valid result',pg.evaluate('!AIResults.mood') and '不存在' in pg.evaluate('AIError'))
    behavior['kind']='invalid-json'
    pg.evaluate("runAI('mood')");pg.wait_for_function("AIBusy===null && AIError!==''")
    check('malformed JSON is a failure, not demo fallback',pg.evaluate('!AIResults.mood') and 'JSON' in pg.evaluate('AIError'))
    behavior['kind']='401'
    pg.evaluate("runAI('mood')");pg.wait_for_function("AIBusy===null && AIError!==''")
    check('auth error shown without exposing response secrets','401' in pg.evaluate('AIError') and 'TEST_ONLY_NOT_A_REAL_KEY' not in pg.locator('body').inner_text())
    behavior['kind']='ok'
    pg.evaluate("go('aiSettings')");pg.select_option('#ai-protocol','responses');pg.fill('#ai-key','TEST_ONLY_NOT_A_REAL_KEY');pg.click('#save-ai')
    pg.evaluate("go('sleep');runAI('sleep')");pg.click('#confirm-ai-consent');pg.wait_for_function("!!AIResults.sleep && AIBusy===null")
    check('Responses request and raw blocks parsed',captured[-1]['url'].endswith('/responses') and 'instructions' in captured[-1]['body'])
    pg.evaluate("go('aiSettings')");pg.select_option('#ai-protocol','anthropic');pg.select_option('#ai-auth','x-api-key');pg.fill('#ai-key','TEST_ONLY_NOT_A_REAL_KEY');pg.click('#save-ai')
    pg.evaluate("go('recovery');runAI('recovery')");pg.click('#confirm-ai-consent');pg.wait_for_function("!!AIResults.recovery && AIBusy===null")
    check('Messages request and text blocks parsed',captured[-1]['url'].endswith('/messages') and 'system' in captured[-1]['body'])
    behavior['kind']='html'
    pg.evaluate("go('mood');runAI('mood')");pg.wait_for_function("!!AIResults.mood && AIBusy===null")
    check('model output HTML is rendered only as text',pg.evaluate('window.PWNED!==true') and pg.locator('#screen img').count()==0)
    pg.evaluate("go('aiSettings')");pg.fill('#ai-url','https://other.example/v1');pg.click('#save-ai')
    check('destination change clears secret binding',pg.evaluate('!AIKeys.has(currentProfile().id) && AIGrant===null'))
    with pg.expect_download() as dl:pg.evaluate('exportBackup()')
    dl.value.save_as(str(ROOT/'tests/export-test.json'))
    payload=json.loads((ROOT/'tests/export-test.json').read_text())
    check('export schema and synthetic label are correct',payload['schema']=='watchyou.demo.v2' and payload['synthetic'])
    check('export does not contain credentials or contextual text',all(x not in json.dumps(payload) for x in ['TEST_ONLY_NOT_A_REAL_KEY','TEST CONTEXT ONLY']))
    pg.set_input_files('#import-file',str(ROOT/'tests/export-test.json'))
    pg.locator('#modal').wait_for(state='visible')
    check('import confirms before overwrite',pg.locator('#modal').is_visible())
    pg.get_by_role('button',name='确认替换',exact=True).click()
    check('import returns to demo with no authorization',pg.evaluate("AIConfig.mode==='demo' && AIGrant===null && AIKeys.size===0"))
    check('habit amount retained after serialized restore',pg.evaluate('phoneWater()')==1250)
    pg.evaluate("go('habits');toggleBreath('phone')");pg.wait_for_timeout(1100)
    check('breathing animation has functional timer',pg.evaluate('breathSeconds')>=1)
    pg.evaluate('stopBreath(false)')
    check('early stop does not create fake complete session',pg.evaluate("S.events.filter(e=>e.kind==='mindful').length")==0)
    pg.evaluate("resetDemo();go('today');watchPage='overview';renderWatch()")
    pg.evaluate("document.getElementById('toast').classList.remove('show')")
    pg.screenshot(path=str(ROOT/'assets/desktop-overview.png'),full_page=True)
    for r in ['today','mood','sleep','settings','aiSettings','assistant','sources']:
        pg.evaluate(f"go('{r}')");pg.locator('.phone').screenshot(path=str(ROOT/f'assets/phone-{r}.png'))
    pg.evaluate("watchPage='mood';renderWatch();go('mood')")
    pg.locator('.watch-wrap').screenshot(path=str(ROOT/'assets/watch-mood.png'))
    for width in [375,390,768,1440]:
        pg.set_viewport_size({'width':width,'height':1120})
        for r in ['today','mood','aiSettings','assistant','sources']:
            pg.evaluate(f"go('{r}')")
            check(f'no viewport overflow at {width}px/{r}',pg.evaluate('document.documentElement.scrollWidth<=innerWidth'))
        if width==390:pg.evaluate("go('mood')");pg.screenshot(path=str(ROOT/'assets/mobile-responsive.png'),full_page=True)
    check('all network requests intercepted to test provider',all(u.startswith('https://model.example/') for u in requests))
    check('no uncaught browser errors',not errors)
    b.close()
report={'executed':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'passed':len(results),'tests':results,'environment':'Chromium / Linux; Playwright set_content with in-memory localStorage adapter; file navigation blocked by environment policy','network':'all provider traffic intercepted using Playwright route mocks; no external model or real credentials used','browser_errors':errors,'mock_provider_requests':len(captured),'not_tested':['real browser restart persistence','Safari/WebKit','actual provider authentication and CORS','native Xcode/HealthKit/Keychain/WatchConnectivity','Personal Team signing and on-device background scheduling','medical or emotion-recognition accuracy']}
(ROOT/'tests/browser-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print('PASSED',len(results))
