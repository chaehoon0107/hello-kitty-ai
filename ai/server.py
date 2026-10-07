"""Loopback-only Qwen3.5-2B vision chat, with persistent local conversations."""
from __future__ import annotations
import base64, ctypes, io, json, os, queue, re, secrets, sqlite3, threading, time, traceback, uuid
import faulthandler
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'ai/data';DATA.mkdir(parents=True,exist_ok=True)
ATTACH=DATA/'attachments';ATTACH.mkdir(exist_ok=True)
DB=DATA/'conversations.sqlite3'
TOKEN=secrets.token_urlsafe(32)
JOBS={};LOCK=threading.RLock();REQUESTS=queue.Queue()
STATE={'phase':'loading','model':'Qwen/Qwen3.5-2B','message':'키티가 준비하고 있어요'}
MODEL=None;PROCESSOR=None
SYSTEM=('너는 사용자의 바탕화면에서 함께하는 친절한 AI 도우미 키티다. 기본적으로 한국어로 정확하고 이해하기 쉽게 답한다. '
        '모르면 모른다고 말하고 실제로 검색하거나 파일을 조작했다고 주장하지 않는다. 이미지를 받으면 실제 이미지 내용을 바탕으로 답한다. '
        '답변의 첫 줄은 반드시 "요약: " 뒤에 핵심만 1~2문장, 100자 이내로 쓴다. '
        '그 다음 빈 줄 뒤 "답변: "으로 시작하여 질문에 대한 충분한 설명을 작성한다. 생각 과정은 쓰지 않는다.')

def now():return datetime.now(timezone.utc).isoformat()
def connect():
    db=sqlite3.connect(DB,timeout=15);db.row_factory=sqlite3.Row;return db
with connect() as db:
    db.executescript('''PRAGMA journal_mode=WAL;
    CREATE TABLE IF NOT EXISTS conversations(id TEXT PRIMARY KEY,title TEXT,created_at TEXT,updated_at TEXT);
    CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,conversation_id TEXT,role TEXT,content TEXT,images TEXT,created_at TEXT,summary TEXT);
    CREATE INDEX IF NOT EXISTS messages_conversation ON messages(conversation_id,created_at);''')

def conversation(cid):
    with connect() as db:
        row=db.execute('SELECT * FROM conversations WHERE id=?',(cid,)).fetchone()
        if row is None:raise ValueError('대화를 찾을 수 없어요')
        result=dict(row)
        result['messages']=[dict(r) for r in db.execute('SELECT * FROM messages WHERE conversation_id=? ORDER BY created_at,id',(cid,))]
    for message in result['messages']:
        message['images']=json.loads(message['images'])
        for attachment in message['images']:
            # Saved attachments travel with the project; Godot receives a local absolute path.
            saved=Path(attachment['path'])
            local=ATTACH/saved.name if saved.is_absolute() else ROOT/saved
            attachment['path']=str(local)
    return result

def split_answer(text):
    text=re.sub(r'<think>.*?</think>','',text,flags=re.S).strip()
    match=re.match(r'\s*(?:\*\*)?요약\s*[:：](?:\*\*)?\s*(.*?)(?:\n\s*(?:\*\*)?답변\s*[:：](?:\*\*)?\s*)(.*)',text,re.S)
    if match:return match.group(1).strip()[:180],match.group(2).strip()
    text=re.sub(r'^요약\s*[:：]\s*','',text)
    summary=re.split(r'(?<=[.!?。])\s+|\n',text)[0].strip()[:160]
    return summary or '답변을 준비했어요.',text

def pointer():
    if os.name!='nt':return {'left_down':False}
    return {'left_down':bool(ctypes.windll.user32.GetAsyncKeyState(1)&0x8000)}

def receive(payload):
    if STATE['phase']!='ready':raise ValueError('모델을 준비하고 있어요. 잠시 후 질문해 주세요.')
    text=str(payload.get('text','')).strip()
    image_data=payload.get('images',[])
    if len(text)>16000 or len(image_data)>4:raise ValueError('질문이나 첨부 파일이 너무 커요')
    if not text and not image_data:raise ValueError('질문을 입력해 주세요')
    if not text:text='이 이미지를 설명해 주세요.'
    cid=str(payload.get('conversation_id',''))
    if cid:conversation(cid)
    else:
        cid=uuid.uuid4().hex
        with connect() as db:db.execute('INSERT INTO conversations VALUES(?,?,?,?)',(cid,text[:28],now(),now()))
    from PIL import Image,ImageOps
    images=[]
    for upload in image_data:
        raw=base64.b64decode(upload['data'],validate=True)
        if len(raw)>20*1024*1024:raise ValueError('이미지는 20MB 이하로 첨부해 주세요')
        with Image.open(io.BytesIO(raw)) as source:
            if source.format not in ['PNG','JPEG','WEBP']:raise ValueError('PNG, JPG, WEBP 이미지를 첨부해 주세요')
            source.load();image=ImageOps.exif_transpose(source).convert('RGB')
            image.thumbnail((1024,1024))
            path=ATTACH/(uuid.uuid4().hex+'.png');image.save(path)
        images.append({'path':path.relative_to(ROOT).as_posix(),'name':Path(upload.get('name','이미지')).name})
    with connect() as db:
        db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?,?)',(uuid.uuid4().hex,cid,'user',text,json.dumps(images,ensure_ascii=False),now(),''))
        db.execute('UPDATE conversations SET updated_at=? WHERE id=?',(now(),cid))
    job_id=uuid.uuid4().hex
    with LOCK:JOBS[job_id]={'id':job_id,'conversation_id':cid,'status':'queued','text':'','summary':'','answer':'','error':'','cancel':threading.Event()}
    REQUESTS.put(job_id)
    return {'job_id':job_id,'conversation_id':cid,'conversation':conversation(cid)}

def public_job(job):return {k:v for k,v in job.items() if k!='cancel'}

def load_model():
    global MODEL,PROCESSOR
    try:
        import torch
        from transformers import AutoProcessor,AutoModelForImageTextToText
        torch.set_num_threads(6);torch.set_num_interop_threads(2)
        path=ROOT/'ai/models/Qwen3.5-2B'
        if not (path/'config.json').is_file():raise RuntimeError('Model files have not been downloaded')
        PROCESSOR=AutoProcessor.from_pretrained(path,local_files_only=True,trust_remote_code=False)
        MODEL=AutoModelForImageTextToText.from_pretrained(path,dtype=torch.bfloat16,
            device_map='cpu',attn_implementation='eager',local_files_only=True,trust_remote_code=False).eval()
        # Quantize one Linear at a time to avoid a full FP32 model copy on 16GB PCs.
        # Vision convolutions, embeddings and normalization stay in FP32.
        import gc,warnings
        STATE.update(message='이 PC에 맞게 모델을 준비하고 있어요')
        supported=torch.backends.quantized.supported_engines
        torch.backends.quantized.engine=next(engine for engine in ['x86','onednn','fbgemm'] if engine in supported)
        def quantize_linear(module):
            for name,child in list(module.named_children()):
                if isinstance(child,torch.nn.Linear):
                    block=torch.nn.Sequential(child.float())
                    with warnings.catch_warnings():
                        warnings.simplefilter('ignore',DeprecationWarning)
                        quantized=torch.ao.quantization.quantize_dynamic(block,{torch.nn.Linear},dtype=torch.qint8,inplace=True)[0]
                    setattr(module,name,quantized)
                else:quantize_linear(child)
        quantize_linear(MODEL)
        MODEL.float();gc.collect()
        STATE.update(phase='ready',message='키티가 질문을 기다리고 있어요')
        print('QWEN_READY',flush=True)
    except Exception:
        STATE.update(phase='error',message='모델을 준비하지 못했어요')
        traceback.print_exc()

def worker():
    import torch
    from PIL import Image
    from transformers import TextIteratorStreamer,StoppingCriteria,StoppingCriteriaList
    class Cancel(StoppingCriteria):
        def __init__(self,event):self.event=event
        def __call__(self,*args,**kwargs):return self.event.is_set()
    while True:
        job_id=REQUESTS.get();job=JOBS[job_id]
        while STATE['phase']=='loading' and not job['cancel'].is_set():time.sleep(.15)
        if job['cancel'].is_set():job.update(status='cancelled');continue
        if MODEL is None:job.update(status='error',error='모델 준비에 실패했어요. 펫을 다시 실행해 주세요.');continue
        try:
            job.update(status='generating')
            messages=[{'role':'system','content':SYSTEM}]
            all_history=conversation(job['conversation_id'])['messages']
            history=all_history[-10:]
            if history and history[0]['role']=='assistant':history=history[1:]
            older=[m['summary'] for m in all_history[:-len(history)] if m['role']=='assistant' and m['summary']]
            if older:messages[0]['content']+='\n이전 대화의 요약:\n'+'\n'.join(older[-4:])[:600]
            for message in history:
                content=[]
                for attachment in message['images']:
                    with Image.open(attachment['path']) as src:
                        image=src.convert('RGB');image.thumbnail((512,512));content.append({'type':'image','image':image.copy()})
                content.append({'type':'text','text':message['content']})
                messages.append({'role':message['role'],'content':content})
            inputs=PROCESSOR.apply_chat_template(messages,add_generation_prompt=True,tokenize=True,
                return_dict=True,return_tensors='pt',enable_thinking=False)
            while inputs['input_ids'].shape[-1]>3584 and len(messages)>3:
                messages.pop(1)
                if len(messages)>2 and messages[1]['role']=='assistant':messages.pop(1)
                inputs=PROCESSOR.apply_chat_template(messages,add_generation_prompt=True,tokenize=True,
                    return_dict=True,return_tensors='pt',enable_thinking=False)
            if inputs['input_ids'].shape[-1]>3584:raise ValueError('입력 내용이 너무 길어요. 질문을 조금 줄여 주세요.')
            if 'pixel_values' in inputs:inputs['pixel_values']=inputs['pixel_values'].to(torch.float32)
            streamer=TextIteratorStreamer(PROCESSOR.tokenizer,skip_prompt=True,skip_special_tokens=True,timeout=180)
            failures=[]
            def generate():
                try:
                    with torch.inference_mode():MODEL.generate(**inputs,streamer=streamer,max_new_tokens=512,
                        do_sample=True,temperature=.7,top_p=.8,top_k=20,repetition_penalty=1.08,
                        stopping_criteria=StoppingCriteriaList([Cancel(job['cancel'])]))
                except Exception as exc:
                    failures.append(exc);streamer.end()
            thread=threading.Thread(target=generate,daemon=True);thread.start()
            start=time.monotonic()
            for chunk in streamer:
                with LOCK:job['text']+=chunk
            thread.join()
            if failures:raise failures[0]
            if job['cancel'].is_set():job.update(status='cancelled');continue
            summary,answer=split_answer(job['text'])
            if not answer:raise RuntimeError('Empty model response')
            with connect() as db:
                db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?,?)',(uuid.uuid4().hex,job['conversation_id'],'assistant',answer,'[]',now(),summary))
                db.execute('UPDATE conversations SET updated_at=? WHERE id=?',(now(),job['conversation_id']))
            job.update(status='done',summary=summary,answer=answer,seconds=round(time.monotonic()-start,2))
        except Exception as exc:
            traceback.print_exc()
            job.update(status='error',error=str(exc) if isinstance(exc,ValueError) else '답변을 생성하지 못했어요. 다시 질문해 주세요.')

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def send_json(self,data,status=200):
        raw=json.dumps(data,ensure_ascii=False).encode()
        self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(raw)));self.end_headers()
        try:self.wfile.write(raw)
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
    def authenticate(self):
        if self.headers.get('X-Kitty-Token')!=TOKEN:self.send_json({'error':'Unauthorized'},401);return False
        return True
    def do_GET(self):
        if not self.authenticate():return
        path=self.path.split('?')[0]
        try:
            if path=='/health':return self.send_json({**STATE,'pointer':pointer()})
            if path=='/conversations':
                with connect() as db:rows=[dict(r) for r in db.execute('SELECT * FROM conversations ORDER BY updated_at DESC')]
                return self.send_json({'conversations':rows})
            if path.startswith('/conversations/'):return self.send_json(conversation(path.split('/')[-1]))
            if path.startswith('/jobs/'):
                with LOCK:job=public_job(JOBS[path.split('/')[-1]])
                return self.send_json({**job,'pointer':pointer()})
            self.send_json({'error':'Not found'},404)
        except (ValueError,KeyError) as exc:self.send_json({'error':str(exc)},404)
    def do_POST(self):
        if not self.authenticate():return
        try:
            size=int(self.headers.get('Content-Length','0'))
            if size>32*1024*1024:raise ValueError('첨부 파일이 너무 커요')
            data=json.loads(self.rfile.read(size) or b'{}')
            if self.path=='/ask':return self.send_json(receive(data),202)
            if self.path.startswith('/cancel/'):
                JOBS[self.path.split('/')[-1]]['cancel'].set();return self.send_json({'ok':True})
            if self.path=='/shutdown':
                for job in JOBS.values():job['cancel'].set()
                self.send_json({'ok':True});threading.Thread(target=self.server.shutdown,daemon=True).start();return
            self.send_json({'error':'Not found'},404)
        except (ValueError,KeyError) as exc:self.send_json({'error':str(exc)},400)
        except Exception:
            traceback.print_exc();self.send_json({'error':'질문을 보내지 못했어요'},500)

if __name__=='__main__':
    server=ThreadingHTTPServer(('127.0.0.1',18935),Handler)
    (ROOT/'ai/server_info.json').write_text(json.dumps({'port':18935,'token':TOKEN,'pid':os.getpid()}))
    def inference_runtime():
        load_model()
        worker()
    if '--diagnostics' in __import__('sys').argv:faulthandler.dump_traceback_later(90,repeat=True)
    threading.Thread(target=inference_runtime,daemon=True).start()
    print('KITTY_SERVER_LISTENING',flush=True)
    server.serve_forever(poll_interval=.2)
