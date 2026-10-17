"""Does `reasoning: {enabled: false}` work for each model, and does it stop
thinking tokens? One tiny call per model and setting. Run on the server.

    python3 thinking_check.py model [model …]
"""
import json
import subprocess
import sys
import time
import urllib.request

key = subprocess.run(
    ["docker", "exec", "octo-pg", "psql", "-U", "octo_admin", "-d", "octopilot", "-Atc",
     "SELECT key FROM api_keys WHERE provider = 'openrouter' AND is_active ORDER BY id LIMIT 1"],
    check=True, capture_output=True, text=True,
).stdout.strip()

Q = "A shop sells pens at 3 for $2. How much do 12 pens cost? Answer in one short sentence."


def call(model, reasoning):
    body = {"model": model, "max_tokens": 400, "temperature": 0.2, "usage": {"include": True},
            "messages": [{"role": "user", "content": Q}]}
    if reasoning is not None:
        body["reasoning"] = reasoning
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            v = json.load(r)
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code}: {e.read()[:160]!r}"
    u = v.get("usage", {})
    text = (v["choices"][0]["message"].get("content") or "").strip().replace("\n", " ")
    return (f"in {u.get('prompt_tokens')} out {u.get('completion_tokens')} "
            f"thinking {u.get('completion_tokens_details', {}).get('reasoning_tokens')} "
            f"${u.get('cost')} {time.time() - t:.1f}s | {text[:60]}")


for m in sys.argv[1:]:
    print(m)
    print("  default :", call(m, None))
    print("  off     :", call(m, {"enabled": False}))
