"""E2e-проверка `workdesk --mcp`: говорит с MCP-сервером по stdio так же, как Claude Code.

python3 driver.py <команда workdesk> <ID хоста> <пароль> <папка для результатов>
"""
import base64
import json
import os
import subprocess
import sys
import threading
import time

exe, peer_id, password, out_dir = sys.argv[1:5]
os.makedirs(out_dir, exist_ok=True)
log = open(os.path.join(out_dir, "mcp-transcript.jsonl"), "w", encoding="utf-8")

proc = subprocess.Popen([exe, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1)
threading.Thread(target=lambda: [sys.stderr.write("[mcp stderr] " + l) for l in proc.stderr], daemon=True).start()
next_id = 0


def call(method, params=None, timeout=180):
    global next_id
    next_id += 1
    req = {"jsonrpc": "2.0", "id": next_id, "method": method, "params": params or {}}
    proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()
    start = time.time()
    while time.time() - start < timeout:
        line = proc.stdout.readline()
        if not line:
            raise SystemExit(f"MCP-сервер закрыл stdout (код {proc.poll()})")
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            raise SystemExit(f"В stdout не JSON (мусор ломает MCP): {line!r}")
        short = json.loads(json.dumps(msg))
        for c in short.get("result", {}).get("content", []) or []:
            if c.get("type") == "image":
                c["data"] = f"<{len(c['data'])} base64>"
        log.write(json.dumps({"request": req, "response": short}, ensure_ascii=False) + "\n")
        log.flush()
        if msg.get("id") == next_id:
            if "error" in msg:
                raise SystemExit(f"{method}: {msg['error']}")
            return msg["result"]
    raise SystemExit(f"{method}: нет ответа за {timeout} с")


def tool(name, args=None, expect_ok=True):
    res = call("tools/call", {"name": name, "arguments": args or {}})
    texts = "\n".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
    print(f"== {name}: {'ОШИБКА ' if res.get('isError') else ''}{texts[:2000]}")
    if expect_ok and res.get("isError"):
        raise SystemExit(f"{name} вернул ошибку")
    return res, texts


init = call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                           "clientInfo": {"name": "e2e", "version": "1"}})
assert init["serverInfo"]["name"] == "workdesk", init
proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
proc.stdin.flush()
names = [t["name"] for t in call("tools/list")["tools"]]
print("Инструменты:", names)
for n in ["workdesk_connect", "workdesk_screenshot", "workdesk_mouse", "workdesk_type", "workdesk_key", "workdesk_run"]:
    assert n in names, n

_, t = tool("workdesk_connect", {"id": peer_id, "password": "wrong-password-1"}, expect_ok=False)
assert "assword" in t or "арол" in t, "неверный пароль должен давать понятную ошибку"

tool("workdesk_connect", {"id": peer_id, "password": password, "timeout_sec": 90})
tool("workdesk_status")

res, t = tool("workdesk_screenshot")
img = [c for c in res["content"] if c.get("type") == "image"][0]
png = base64.b64decode(img["data"])
assert png[:8] == b"\x89PNG\r\n\x1a\n", "снимок не PNG"
open(os.path.join(out_dir, "screenshot.png"), "wb").write(png)
assert int.from_bytes(png[16:20], "big") > 100, "снимок слишком маленький"
assert png[25] == 2, "снимок должен быть RGB без прозрачности"

_, t = tool("workdesk_run", {"command": "echo hello-$((40+2)); uname -s; exit_test() { return 3; }; exit_test", "timeout_sec": 60})
assert "hello-42" in t, "в выводе нет результата команды"
assert "Linux" in t
assert "Код выхода: 3" in t, "код выхода не передан"
assert "exit_test()" not in t, "эхо введенной команды не убрано"
_, t = tool("workdesk_run", {"command": "whoami && pwd"})
assert "root" in t, t

tool("workdesk_mouse", {"action": "move", "x": 50, "y": 50})
tool("workdesk_mouse", {"action": "click", "x": 60, "y": 60})
tool("workdesk_mouse", {"action": "scroll", "scroll_y": -2})
tool("workdesk_type", {"text": "workdesk"})
tool("workdesk_key", {"key": "Enter"})
time.sleep(1)
_, t = tool("workdesk_run", {"command": "cat /tmp/typed.txt"})
assert "workdesk" in t, "набранный текст не дошел до окна на удаленной стороне"
tool("workdesk_key", {"key": "a", "ctrl": True})
tool("workdesk_disconnect")
_, t = tool("workdesk_status")
assert peer_id not in t, "после отключения подключение не должно оставаться"

proc.stdin.close()
proc.wait(timeout=30)
print("E2E: все проверки пройдены")
