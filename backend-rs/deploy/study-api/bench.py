"""Pricing benchmark (tasklist P2): one studio built from the given files on a
throwaway study-api (see bench.sh), then the paid features on it. Every
number comes from OpenRouter's own usage (llm_usage on the copy).

    python3 bench.py --api http://127.0.0.1:8122 --user UUID --label NAME FILE [FILE …]
"""
import argparse
import json
import mimetypes
import os
import subprocess
import time
import urllib.parse
import urllib.request
import uuid

ap = argparse.ArgumentParser()
ap.add_argument("--api", required=True)
ap.add_argument("--user", required=True)
ap.add_argument("--label", required=True)
ap.add_argument("--out", default="results")
ap.add_argument("files", nargs="+")
a = ap.parse_args()
H = {"X-User-Id": a.user}


def sql(q):
    out = subprocess.run(["docker", "exec", "octo-pg", "psql", "-U", "octo_admin", "-d", "cockpit_t", "-AtF", "\t", "-c", q],
                         check=True, capture_output=True, text=True).stdout
    return [l.split("\t") for l in out.splitlines() if l]


def vsql(q):
    out = subprocess.run(["docker", "exec", "octo-pg", "psql", "-U", "octo_admin", "-d", "vector_t", "-AtF", "\t", "-c", q],
                         check=True, capture_output=True, text=True).stdout
    return [l.split("\t") for l in out.splitlines() if l]


def sse(method, path, body=None, timeout=1800):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(a.api + path, data=data, method=method,
                                 headers={**H, **({"Content-Type": "application/json"} if data else {})})
    events, name = [], None
    with urllib.request.urlopen(req, timeout=timeout) as r:
        for raw in r:
            line = raw.decode().rstrip("\n")
            if line.startswith("event:"):
                name = line[6:].strip()
            elif line.startswith("data:"):
                try:
                    events.append((name, json.loads(line[5:].strip())))
                except ValueError:
                    events.append((name, line[5:].strip()))
    return events


def first(events, name):
    return next((d for n, d in events if n == name), None)


def upload(studio, path):
    boundary = uuid.uuid4().hex
    mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
    with open(path, "rb") as f:
        payload = f.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{os.path.basename(path)}\"\r\n"
            f"Content-Type: {mime}\r\n\r\n").encode() + payload + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{a.api}/studios/{studio}/documents", data=body, method="POST",
                                 headers={**H, "Content-Type": f"multipart/form-data; boundary={boundary}",
                                          "Idempotency-Key": uuid.uuid4().hex})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)


report = {"label": a.label, "files": [], "steps": {}}
t0 = time.time()
studio = first(sse("POST", "/studios", {"title": f"Bench {a.label}"}), "data")["id"]

# 1. Upload + ingest (no AI): passages and characters per file.
for f in a.files:
    job = upload(studio, f)
    t = time.time()
    while True:
        st = sql(f"select status, coalesce(error,'') from ingest_jobs where id = '{job['id']}'")[0]
        if st[0] in ("done", "failed"):
            break
        time.sleep(2)
    n, chars = vsql(f"select count(*), coalesce(sum(length(content)),0) from chunks where document_id = '{job['document_id']}'")[0]
    report["files"].append({"file": os.path.basename(f), "bytes": os.path.getsize(f), "ingest": st[0], "error": st[1],
                            "seconds": round(time.time() - t, 1), "passages": int(n), "chars": int(chars)})
    print(f"  ingest {os.path.basename(f)}: {st[0]} {n} passages {chars} chars {time.time() - t:.0f}s {st[1]}")

# 2. Build: the usage event at the end carries tokens and cost per feature.
t = time.time()
build = first(sse("POST", f"/studios/{studio}/build"), "data")["buildId"]
ev = sse("GET", f"/studios/{studio}/build-status/{build}")
err = first(ev, "error")
usage = first(ev, "usage") or {}
lessons = sql(f"select payload from generated_topics where studio_id = '{studio}' order by ordinal")
topics = [json.loads(l[0]) for l in lessons]
scen = int(sql(f"select count(*) from generated_scenarios where studio_id = '{studio}'")[0][0])
report["build"] = {
    "seconds": round(time.time() - t, 1), "error": err, "usage": usage,
    "lessons": len(topics), "cards": sum(len(x.get("flashcards", [])) for x in topics),
    "quiz": sum(len(x.get("quizQuestions", [])) for x in topics), "scenarios": scen,
    "lessonChars": sum(len(x.get("detailedExplanation", "")) for x in topics),
    "titles": [x.get("title") for x in topics],
}
b = report["build"]
print(f"  build: {b['lessons']} lessons {b['cards']} cards {b['quiz']} quiz {b['scenarios']} scenarios in {b['seconds']}s, "
      f"${usage.get('costUsd')} ({usage.get('promptTokens')} in / {usage.get('completionTokens')} out / "
      f"{usage.get('reasoningTokens')} thinking) {err or ''}")
with open(os.path.join(a.out, f"{a.label}-lessons.json"), "w") as fh:
    json.dump(topics, fh, ensure_ascii=False, indent=1)

# 3. The paid features on the built studio.
def feature(name, fn, n):
    us = []
    for i in range(n):
        try:
            u = fn(i)
        except Exception as e:  # noqa: BLE001 — reported, the run goes on
            print(f"  {name} #{i}: {e}")
            continue
        if u:
            us.append(u)
    tot = {k: sum(u.get(k) or 0 for u in us) for k in ("promptTokens", "completionTokens", "reasoningTokens", "costUsd")}
    tot.update(calls=len(us), model=us[0]["model"] if us else None,
               avgCostUsd=round(tot["costUsd"] / len(us), 6) if us else None)
    report["steps"][name] = tot
    print(f"  {name}: {len(us)} calls avg ${tot['avgCostUsd']} ({tot['model']})")

tids = [x.get("id") for x in topics]
qs = ["What are the main ideas of this material?", "Explain the most important concept with an example.",
      "How do the first two topics relate to each other?"]
feature("ask", lambda i: first(sse("GET", "/ask?" + urllib.parse.urlencode({"studio_id": studio, "q": qs[i]})), "meta")["usage"], 3)
feature("concepts", lambda i: first(sse("POST", f"/studios/{studio}/topics/{tids[i]}/concepts"), "data").get("usage")
        if i < len(tids) else None, 2)
cards = [c for x in topics for c in x.get("flashcards", [])][:3]
feature("grade", lambda i: first(sse("POST", f"/studios/{studio}/grade",
                                     {"question": cards[i].get("front"), "answer": cards[i].get("back"),
                                      "said": " ".join(str(cards[i].get("back", "")).split()[:6])}), "data")["usage"]
        if i < len(cards) else None, 3)

report["wallSeconds"] = round(time.time() - t0, 1)
with open(os.path.join(a.out, f"{a.label}.json"), "w") as fh:
    json.dump(report, fh, ensure_ascii=False, indent=1)
print(f"  saved {a.out}/{a.label}.json")
