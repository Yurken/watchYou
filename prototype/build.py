from pathlib import Path
p=Path(__file__).resolve().parent
html=(p/'shell.html').read_text(encoding='utf-8')
for token, filename in [('/*CSS*/','styles.css'),('/*CORE*/','core.js'),('/*APP*/','app.js'),('/*AICORE*/','ai-core.js'),('/*AIUI*/','ai-ui.js')]:
    html=html.replace(token,(p/filename).read_text(encoding='utf-8'))
(p/'index.html').write_text(html,encoding='utf-8')
print('Built standalone HTML:',p/'index.html')
