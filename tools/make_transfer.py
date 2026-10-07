"""Create an editable, offline Windows transfer package without copying a venv."""
from pathlib import Path
import argparse, hashlib, json, shutil, sqlite3, sys, zipfile

ROOT = Path(__file__).resolve().parents[1]

def ignored(directory, names):
    return [name for name in names if name in {'__pycache__', '.cache', '.godot', '.venv'}
            or name.endswith(('.pyc', '.blend1', '.lnk', '.log', '.pid'))
            or name in {'server_info.json', 'conversations.sqlite3', 'conversations.sqlite3-wal', 'conversations.sqlite3-shm'}]

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--python-base', type=Path, required=True)
    parser.add_argument('--godot', type=Path, required=True)
    args = parser.parse_args()
    target = args.destination.resolve()
    if target.exists(): raise RuntimeError(f'Use a new destination: {target}')
    if target == ROOT or ROOT in target.parents: raise RuntimeError('Package must be outside the source project')
    target.mkdir(parents=True)
    for file in ROOT.iterdir():
        if file.is_file() and file.suffix in {'.gd', '.uid', '.tscn', '.godot', '.md', '.ps1', '.cmd'}:
            shutil.copy2(file, target / file.name)
    for directory in ['ai', 'assets', 'tools', 'ui', 'tests']:
        shutil.copytree(ROOT / directory, target / directory, ignore=ignored)
    (target / 'previews').mkdir()
    for file in (ROOT / 'previews').glob('*.json'):
        if file.name.endswith(('verification.json', 'report.json')): shutil.copy2(file, target / 'previews' / file.name)
    manifest = target / 'ai/model_manifest.json'
    metadata = json.loads(manifest.read_text(encoding='utf-8'))
    metadata['directory'] = 'ai/models/Qwen3.5-2B'
    manifest.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    source_db = ROOT / 'ai/data/conversations.sqlite3'
    dest_db = target / 'ai/data/conversations.sqlite3'
    with sqlite3.connect(source_db) as source, sqlite3.connect(dest_db) as dest:
        source.backup(dest)
        for message_id, encoded in dest.execute('SELECT id, images FROM messages').fetchall():
            attachments = json.loads(encoded)
            for attachment in attachments:
                name = Path(attachment['path'].replace('\\', '/')).name
                if not (target / 'ai/data/attachments' / name).is_file():
                    raise RuntimeError(f'Missing conversation attachment: {name}')
                attachment['path'] = 'ai/data/attachments/' + name
            dest.execute('UPDATE messages SET images=? WHERE id=?', (json.dumps(attachments, ensure_ascii=False), message_id))
        dest.commit()
        dest.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        dest.execute('PRAGMA journal_mode=DELETE')
        assert dest.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    print('Project, models and conversation snapshot copied', flush=True)
    runtime = target / 'runtime'
    runtime.mkdir()
    (runtime / '.gdignore').write_text('', encoding='utf-8')
    shutil.copy2(args.godot, runtime / 'Godot_v4.7.2-stable_win64.exe')
    def ignore_base(directory, names):
        return [n for n in names if n in {'site-packages', '__pycache__', 'Doc', 'Tools', 'Scripts'} or n.endswith('.pyc')]
    shutil.copytree(args.python_base, runtime / 'python', ignore=ignore_base)
    # Standalone Python discovers Lib beside its executable; no original venv path survives.
    shutil.copytree(ROOT / 'ai/.venv/Lib/site-packages', runtime / 'python/Lib/site-packages', ignore=ignored)
    import os
    for name in ['msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'msvcp140_atomic_wait.dll',
                 'msvcp140_codecvt_ids.dll', 'concrt140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']:
        source = Path(os.environ['SystemRoot']) / 'System32' / name
        if source.is_file(): shutil.copy2(source, runtime / 'python' / name)
    print('Standalone Python and installed AI packages copied', flush=True)
    # Godot embeds license information in its editor; keep its source notices beside the binary too.
    from urllib.request import urlopen
    for name in ['LICENSE.txt', 'COPYRIGHT.txt']:
        with urlopen('https://raw.githubusercontent.com/godotengine/godot/master/' + name, timeout=30) as response:
            (runtime / ('Godot_' + name)).write_bytes(response.read())
    files = []
    for file in sorted(target.rglob('*')):
        if file.is_file(): files.append({'path': file.relative_to(target).as_posix(), 'size': file.stat().st_size, 'sha256': digest(file)})
    (target / 'TRANSFER_MANIFEST.json').write_text(json.dumps({'format': 1, 'platform': 'Windows x86_64', 'files': files}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Manifest ready: {len(files)} files, {sum(f["size"] for f in files):,} bytes', flush=True)
    archive = target.with_suffix('.zip')
    if archive.exists(): raise RuntimeError(f'Archive already exists: {archive}')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as zipped:
        for file in sorted(target.rglob('*')):
            if file.is_file():
                # Weights are already compact; ZIP64 supports the single 4.55GB model file.
                method = zipfile.ZIP_STORED if file.suffix == '.safetensors' else zipfile.ZIP_DEFLATED
                zipped.write(file, target.name + '/' + file.relative_to(target).as_posix(), compress_type=method)
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None
    checksum = digest(archive)
    archive.with_suffix('.zip.sha256').write_text(checksum + '  ' + archive.name + '\n', encoding='utf-8')
    print(json.dumps({'archive': str(archive), 'bytes': archive.stat().st_size, 'sha256': checksum}, ensure_ascii=False), flush=True)

if __name__ == '__main__': main()
