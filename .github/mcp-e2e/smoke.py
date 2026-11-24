"""Smoke-проверка `--mcp` (Windows, macOS): stdio оконного exe, список инструментов, связь с сервером WorkDesk.

python smoke.py <путь к exe>
"""
import json
import os
import subprocess
import sys

proc = subprocess.Popen([sys.argv[1], "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        text=True, encoding="utf-8", bufsize=1)
n = 0


def call(method, params=None):
    global n
    n += 1
    proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params or {}}) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise SystemExit(f"{method}: MCP-сервер закрыл stdout (код {proc.poll()})")
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        raise SystemExit(f"{method}: в stdout не JSON (ломает MCP): {line!r}")
    assert msg.get("id") == n, msg
    if "error" in msg:
        raise SystemExit(f"{method}: {msg['error']}")
    return msg["result"]


init = call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
print("initialize:", init["serverInfo"])
assert init["serverInfo"]["name"] == "workdesk"
tools = [t["name"] for t in call("tools/list")["tools"]]
print("tools:", tools)
assert "workdesk_run" in tools and "workdesk_screenshot" in tools
print("list_peers:", call("tools/call", {"name": "workdesk_list_peers", "arguments": {}})["content"][0]["text"][:200])
res = call("tools/call", {"name": "workdesk_connect", "arguments": {"id": "100000001", "password": "x", "timeout_sec": 30}})
text = res["content"][0]["text"]
print("connect к несуществующему ID:", text)
assert res.get("isError"), "подключение к несуществующему ID должно вернуть ошибку"
expect = os.environ.get("SMOKE_EXPECT", "")
if expect:  # WorkDesk AI без входа: отказ без входа, до попытки подключения
    assert expect in text, f"ожидалось «{expect}» в ответе: {text}"
proc.stdin.close()
proc.wait(timeout=30)
print(f"SMOKE: --mcp работает ({sys.platform})")
