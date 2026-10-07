"""Exercise the real local model and persistent conversation API."""
import base64,json,time,urllib.request
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
def request(path,payload=None):
    info=json.loads((ROOT/'ai/server_info.json').read_text())
    req=urllib.request.Request('http://127.0.0.1:'+str(info['port'])+path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={'X-Kitty-Token':info['token'],'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=20) as response:return json.load(response)
def ask(text,images=[],cid=''):
    job=request('/ask',{'text':text,'images':images,'conversation_id':cid})
    print('VERIFY_ASK_STARTED',job['job_id'],flush=True)
    start=time.monotonic();chunks=0;old=''
    while time.monotonic()-start<600:
        result=request('/jobs/'+job['job_id'])
        if result['text']!=old:chunks+=1;old=result['text']
        if result['status'] in ['done','error','cancelled']:
            print(json.dumps({k:v for k,v in result.items() if k not in ['id','pointer']},ensure_ascii=False),flush=True)
            assert result['status']=='done',result
            assert result['summary'] and result['answer']
            return result,chunks
        time.sleep(1)
    request('/cancel/'+job['job_id'],{})
    raise RuntimeError('Inference timed out')
if __name__=='__main__':
    while True:
        health=request('/health')
        if health['phase']=='ready':break
        assert health['phase']=='loading',health
        time.sleep(1)
    image=Image.new('RGB',(256,256),'white');draw=ImageDraw.Draw(image)
    draw.ellipse((40,40,216,216),fill='red')
    path=ROOT/'previews/vision_test.png';image.save(path)
    first,chunks=ask('검증: 7 곱하기 8은 얼마야? 한 문장으로 답해 줘.')
    assert '56' in first['answer'] or '56' in first['summary']
    second,_=ask('그 수에 4를 더하면?',cid=first['conversation_id'])
    assert '60' in second['answer'] or '60' in second['summary']
    vision,_=ask('이미지의 도형과 색을 한 문장으로 말해 줘.',images=[{'name':path.name,'data':base64.b64encode(path.read_bytes()).decode()}])
    assert any(s in vision['answer']+vision['summary'] for s in ['빨간','빨강','붉은','red'])
    assert any(s in vision['answer']+vision['summary'] for s in ['원','동그','circle'])
    stored=request('/conversations/'+first['conversation_id'])
    assert [m['role'] for m in stored['messages']]==['user','assistant','user','assistant']
    report={'text_pass':True,'continuation_pass':True,'vision_pass':True,'history_pass':True,'stream_updates':chunks,
            'text_seconds':first['seconds'],'continuation_seconds':second['seconds'],'vision_seconds':vision['seconds']}
    (ROOT/'previews/ai_verification.json').write_text(json.dumps(report,indent=2))
    print('REAL_QWEN_VERIFICATION_OK',report,flush=True)
