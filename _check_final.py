import os, subprocess
root = r'C:\Users\Joyce_SUN\Desktop\FJSP\logs'
log = os.path.join(root, 'stage7_run.log')
sota = os.path.join(root, 'stage7_sota.json')
bench = os.path.join(root, 'stage7_benchmark.json')

# process count
out = subprocess.run(['tasklist'], capture_output=True, text=True).stdout
print('matlab processes:', out.lower().count('matlab.exe'))

if os.path.exists(log):
    txt = open(log, encoding='utf-8', errors='ignore').read()
    lines = txt.splitlines()
    print('log lines:', len(lines), 'size:', os.path.getsize(log))
    # completion markers
    for kw in ['stage7_run PASS', 'SOTA comparison saved', '[7.2]', 'ERROR', 'Undefined', 'Error']:
        hits = [l for l in lines if kw.lower() in l.lower()]
        if hits:
            print(f'[{kw}] {len(hits)} hits; last: {hits[-1][:120]}')
    print('--- last 12 lines ---')
    for l in lines[-12:]:
        print(l)

print('\nbenchmark.json size:', os.path.getsize(bench) if os.path.exists(bench) else 'MISSING')
print('sota.json size:', os.path.getsize(sota) if os.path.exists(sota) else 'MISSING')
