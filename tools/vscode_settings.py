# VS Code 用户设置（在 WSL 里运行，改的是 Windows 上 VS Code 的用户设置）
# 目标：沙箱里的软件只能经代理端口拿外部数据；登录除外
# 改前列出改动、要输入 y 确认；原文件备份为同目录下的 settings.json.bak-<时间>
import os, re, json, glob, time, sys
MISSING = object()

def strip_jsonc(s):
    out = []; i = 0; n = len(s); in_str = False; had = False
    while i < n:
        c = s[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(s[i + 1]); i += 2; continue
            if c == '"':
                in_str = False
            i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i + 1] == '/':
            had = True; j = s.find('\n', i); i = n if j < 0 else j; continue
        if c == '/' and i + 1 < n and s[i + 1] == '*':
            had = True; j = s.find('*/', i + 2); i = n if j < 0 else j + 2; continue
        out.append(c); i += 1
    t = ''.join(out)
    t = re.sub(r',(\s*[}\]])', r'\1', t)
    return t, had

def show(v):
    return '（没设）' if v is MISSING else json.dumps(v, ensure_ascii=False)

cands = sorted(glob.glob('/mnt/c/Users/*/AppData/Roaming/Code/User'))
if not cands:
    print('  ✘ 找不到 VS Code 用户设置文件夹，这部分跳过，没改任何东西'); sys.exit(0)
pref = []  # 有多个 Windows 用户时，用环境变量 VSCODE_USER_DIR 指定
udir = os.environ.get('VSCODE_USER_DIR') or (pref or cands)[0]
path = udir + '/settings.json'
win_path = 'C:' + path[len('/mnt/c'):].replace('/', '\\')
raw = open(path, 'rb').read() if os.path.exists(path) else b''
text = raw.decode('utf-8-sig') if raw else ''
had_comment = False
if text.strip() == '':
    obj = {}
else:
    t, had_comment = strip_jsonc(text)
    try:
        obj = json.loads(t)
    except Exception as e:
        print('  ✘ 设置文件格式读不懂（%s），为安全起见不改，这部分跳过' % e); sys.exit(0)
if not isinstance(obj, dict):
    print('  ✘ 设置文件不是正常格式，不改，这部分跳过'); sys.exit(0)

ENVK = 'terminal.integrated.env.linux'
cur_env = obj.get(ENVK) if isinstance(obj.get(ENVK), dict) else {}
new_env = dict(cur_env); new_env['BROWSER'] = None

WANT = [
    ('window.restoreWindows', 'none', '打开 VS Code 不自动连沙箱'),
    ('dev.containers.copyGitConfig', False, '不把你电脑上的 git 账号信息复制进沙箱'),
    ('dev.containers.gitCredentialHelperConfigLocation', 'none', '沙箱里不能借用你电脑上的 git 登录'),
    ('dev.containers.dockerCredentialHelper', False, '沙箱里不能借用你电脑上的 Docker 登录'),
    ('remote.downloadExtensionsLocally', True, '插件由 Windows 下载再传进沙箱'),
    ('remote.autoForwardPorts', False, '沙箱里的程序开了端口，VS Code 不再自动让你电脑上的程序连进去'),
    ('remote.restoreForwardedPorts', False, '重连时不恢复上次转发的端口（登录用的 1455 登完就不会一直留着）'),
    ('dev.containers.forwardWSLServices', False, '不把 WSL 里的 SSH / GPG / 图形界面服务转进沙箱（这个设置名我不完全确定，无效也没坏处）'),
    ('dev.containers.mountWaylandSocket', False, '不把图形界面（Wayland）通道接进沙箱。WSL 的图形界面和 Windows 剪贴板是同步的'),
    ('git.useIntegratedAskPass', False, '沙箱里的 git 不能再通过 VS Code 弹框找你要密码'),
    ('git.terminalAuthentication', False, '终端里的 git 也不走 VS Code 弹框'),
    (ENVK, new_env, 'VS Code 终端里运行的程序不能再让 Windows 打开网页（官方插件登录不受影响）'),
]
changes = []
for k, v, why in WANT:
    old = obj.get(k, MISSING)
    if old != v:
        changes.append((k, old, v, why))
if obj.get('dev.containers.logLevel') in ('trace', 'debug'):
    changes.append(('dev.containers.logLevel', obj['dev.containers.logLevel'], MISSING, '排查用的详细日志，删掉'))

print('  设置文件：' + win_path)
if not changes:
    print('  ✔ 这些设置都已经是对的，不用改'); sys.exit(0)
print('  要改 %d 项：' % len(changes))
for k, old, new, why in changes:
    print('    %s：%s → %s' % (k, show(old), '（删掉）' if new is MISSING else show(new)))
    print('        （%s）' % why)
if had_comment:
    print('  注意：原文件里有注释，改完后注释会没了（备份里还在）')
if any(c[0] == 'window.restoreWindows' for c in changes):
    print('  影响：以后打开 VS Code 是空窗口，要从「文件 → 打开最近的文件」里选。')
print('  影响：已经转发着的端口要等下次重连才消失；终端里的程序要开网页时只会打印网址，你自己复制。')
a = input('  确认修改？输入 y 回车（其他 = 不改）：').strip()
if a not in ('y', 'Y'):
    print('  已取消，没改'); sys.exit(0)

for k, old, new, why in changes:
    if new is MISSING:
        obj.pop(k, None)
    else:
        obj[k] = new
bak = ''
if raw:
    bak = path + '.bak-' + time.strftime('%Y%m%d-%H%M%S')
    open(bak, 'wb').write(raw)
tmp = path + '.quick-tmp'
with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
    f.write(json.dumps(obj, indent=4, ensure_ascii=False) + '\n')
os.replace(tmp, path)
chk = json.loads(open(path, encoding='utf-8').read())
bad = [k for k, v, _ in WANT if chk.get(k, MISSING) != v]
if bad:
    print('  ✘ 写完检查不对：' + ', '.join(bad))
else:
    print('  ✔ 已修改 %d 项（VS Code 开着也会自动读到新设置）' % len(changes))
if bak:
    print('  退回方法：把 ' + 'C:' + bak[len('/mnt/c'):].replace('/', '\\') + ' 复制回 ' + win_path)
