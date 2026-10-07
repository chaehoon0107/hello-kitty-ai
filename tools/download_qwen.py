from pathlib import Path
import json
from huggingface_hub import snapshot_download,HfApi
root=Path(__file__).resolve().parents[1]
repo='Qwen/Qwen3.5-2B'
info=HfApi().model_info(repo)
destination=root/'ai/models/Qwen3.5-2B'
snapshot_download(repo_id=repo,revision=info.sha,local_dir=destination,
                  allow_patterns=['*.json','*.safetensors','*.jinja','*.txt','LICENSE','README.md'],max_workers=3)
(root/'ai/model_manifest.json').write_text(json.dumps({'repo':repo,'revision':info.sha,'directory':str(destination)},indent=2))
print('QWEN_MODEL_DOWNLOADED',info.sha)
