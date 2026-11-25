# 在沙箱里运行（只读）：cd ~/sandbox-vm && docker compose exec -T box python3 - < tools/vscode_check.py
# 在沙箱里运行（只读）：沙箱里的软件能从哪些地方拿到外部的文件和数据
import os, socket, subprocess, glob
def listen_ports():
    ports = set()
    for fn in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            for l in open(fn).read().splitlines()[1:]:
                f = l.split()
                if len(f) > 3 and f[3] == '0A':
                    ports.add(int(f[1].rsplit(':', 1)[1], 16))
        except Exception:
            pass
    return ports

def x11probe(fam, addr):
    try:
        s = socket.socket(fam, socket.SOCK_STREAM); s.settimeout(3); s.connect(addr)
        s.sendall(b'l\x00\x0b\x00\x00\x00\x00\x00\x00\x00\x00\x00')
        r = s.recv(1); s.close()
    except Exception as e:
        return '连不上（%s）' % type(e).__name__
    if r == b'\x01': return 'ok'
    if r in (b'\x00', b'\x02'): return '存在，但拒绝没有认证的连接'
    return '没有正常回应'

def ok(m): print('  ✔ ' + m)
def warn(m): print('  ⚠ ' + m)
def info(m): print('  · ' + m)

def procs():
    for p in os.listdir('/proc'):
        if not p.isdigit(): continue
        try:
            cmd = open('/proc/%s/cmdline' % p, 'rb').read()
            env = open('/proc/%s/environ' % p, 'rb').read().split(b'\0')
        except Exception:
            continue
        d = {}
        for e in env:
            k, _, v = e.partition(b'=')
            if k: d[k.decode(errors='replace')] = v.decode(errors='replace')
        yield p, cmd, d

print('-- 沙箱里能不能看到 Windows 的盘')
bad = []
for l in open('/proc/mounts'):
    f = l.split()
    if len(f) >= 3 and (f[2] in ('drvfs', '9p', 'virtiofs') or f[1].startswith('/mnt/')):
        bad.append('%s（%s）' % (f[1], f[2]))
if bad: warn('能看到：' + '，'.join(bad))
else: ok('看不到 C 盘、D 盘或其它 Windows 文件夹')

P = list(procs())
vs = [x for x in P if b'/sandbox/.vscode-server/' in x[1]]
def _exe(c):
    a = c.split(b'\0')[0].decode(errors='replace')
    return a.rsplit('/', 1)[-1]
# VS Code 终端里的 shell 带 --init-file /sandbox/.vscode-server/...（终端集成脚本），所以不能按路径排除；按 TERM_PROGRAM 找，排除 node（VS Code 自己）
term = [x for x in P if x[2].get('TERM_PROGRAM') == 'vscode' and _exe(x[1]) != 'node']
print('-- VS Code 打开的通道（VS Code 连着沙箱时才有）')
if not vs:
    ok('VS Code 现在没连着沙箱，这些通道都不存在')
else:
    info('VS Code 在沙箱里的进程：%d 个' % len(vs))
    if any(x[2].get('BROWSER') for x in vs):
        info('VS Code 本身（含 Claude / Codex 插件）还能让 Windows 打开网页 —— 登录要用，保留')
    if not term:
        info('现在没开 VS Code 终端，查不到终端里的情况')
    elif any(x[2].get('BROWSER') for x in term):
        warn('VS Code 终端里的程序还能让 Windows 打开网页（终端是改设置之前开的？关掉重开一个再查）')
    else:
        ok('VS Code 终端里的程序不能让 Windows 打开网页（找到 %d 个终端进程：%s）' % (len(term), '，'.join(sorted(set(_exe(x[1]) for x in term)))))
    askp = [x for x in P if x[2].get('GIT_ASKPASS')]
    if askp: warn('还有 %d 个进程带着 git 密码弹窗通道（改设置后要重连一次才会消失）' % len(askp))
    else: ok('没有 git 密码弹窗通道')
    ssh_paths = set(x[2]['SSH_AUTH_SOCK'] for x in P if x[2].get('SSH_AUTH_SOCK')) | set(glob.glob('/tmp/vscode-ssh-auth-*.sock'))
    if ssh_paths: warn('有 SSH 密钥通道：' + '，'.join(sorted(ssh_paths)))
    else: ok('没有转发 SSH 密钥')
    gpg = glob.glob('/tmp/vscode-gpg*') + glob.glob('/sandbox/.gnupg/S.gpg-agent*')
    if gpg: warn('有 GPG 通道：' + '，'.join(gpg))
    else: ok('没有转发 GPG')
    disp = sorted(set('%s=%s' % (k, x[2][k]) for x in P for k in ('DISPLAY', 'WAYLAND_DISPLAY') if x[2].get(k)))
    xs = glob.glob('/tmp/.X11-unix/*') + glob.glob('/tmp/vscode-wayland-*') + glob.glob('/tmp/wayland-*')
    x11tcp = sorted(p for p in listen_ports() if 6000 <= p <= 6063)
    if not (disp or xs or x11tcp):
        ok('没有图形界面通道')
    else:
        info('图形界面相关：' + '，'.join(disp + xs + ['TCP %d' % p for p in x11tcp])[:200])
        res = [(sp, x11probe(socket.AF_UNIX, sp)) for sp in glob.glob('/tmp/.X11-unix/X*')]
        res += [('TCP %d' % p, x11probe(socket.AF_INET, ('127.0.0.1', p))) for p in x11tcp]
        if not res:
            ok('有 DISPLAY 设置，但没有可连的图形界面通道（连不上就读不到剪贴板）')
        for name, r in res:
            if r == 'ok': warn('%s 能连上图形界面 —— 沙箱里的程序理论上能读 Windows 剪贴板' % name)
            else: ok('%s %s' % (name, r))
    try:
        w = os.access('/tmp/.X11-unix', os.W_OK) if os.path.isdir('/tmp/.X11-unix') else None
        if w is False: ok('/tmp/.X11-unix 是只读的，VS Code 建不了新的图形界面通道')
        elif w: info('/tmp/.X11-unix 可写（还没换成只读空文件夹）')
    except Exception:
        pass

print('-- 沙箱里在监听的端口（VS Code 连着时可能被转发到你电脑上）')
ports = set()
for fn in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        for l in open(fn).read().splitlines()[1:]:
            f = l.split()
            if len(f) > 3 and f[3] == '0A':
                ports.add(int(f[1].rsplit(':', 1)[1], 16))
    except Exception:
        pass
info('端口：' + ('，'.join(str(p) for p in sorted(ports)) if ports else '没有'))

print('-- git 登录')
envh = dict(os.environ, HOME='/sandbox')
try:
    r = subprocess.run(['git', 'config', '--global', '--get-all', 'credential.helper'], capture_output=True, text=True, env=envh, timeout=10)
    h = r.stdout.strip()
    if h: warn('沙箱 git 设了登录助手：' + h.replace('\n', ' | ')[:150])
    else: ok('沙箱 git 没有登录助手，借不到你电脑上的 git 登录')
except Exception as e:
    info('git 查不了：' + type(e).__name__)

print('-- 沙箱上网（经代理，白名单）')
def code(u):
    try:
        r = subprocess.run(['curl', '-s', '-o', '/dev/null', '-m', '12', '-w', '%{http_code}', u], capture_output=True, text=True, timeout=20)
        return r.stdout.strip() or '无响应'
    except Exception as e:
        return type(e).__name__
c1 = code('https://github.com/')
c2 = code('https://mobile.events.data.microsoft.com/')
(ok if c1 not in ('000', '无响应') else warn)('白名单 github.com → %s' % c1)
(ok if c2 in ('000', '无响应') else warn)('不在白名单的地址 → %s（000 = 被拦住）' % c2)
