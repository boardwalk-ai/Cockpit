"""F9: retrieval quality of study-api's hybrid search, as recall@k.

The first run makes a fixed question set (one question per sampled passage,
written by the cheap build model from the passage alone) and saves it; every
later run reuses it, so before/after numbers compare. Then each question goes
to the loopback-only `GET /search` and we check where its source passage
ranks.

    python3 recall_eval.py [--n 30] [--api http://127.0.0.1:8110] [--set recall_set.json]
"""
import argparse
import json
import os
import random
import subprocess
import urllib.parse
import urllib.request


def psql(db, sql):
    out = subprocess.run(
        ["docker", "exec", "octo-pg", "psql", "-U", "octo_admin", "-d", db, "-AtF", "\t", "-c", sql],
        check=True, capture_output=True, text=True,
    ).stdout
    return [line.split("\t") for line in out.splitlines() if line]


def ask_model(key, model, passage):
    body = {
        "model": model,
        "max_tokens": 80,
        "temperature": 0.3,
        "messages": [
            {"role": "system", "content": "You write exam-style questions for students."},
            {"role": "user", "content": (
                "Write ONE specific question that this passage answers, the way a student would ask it. "
                "Use your own words, not phrases copied from the passage. Reply with the question only.\n\n"
                f"Passage:\n{passage[:3000]}"
            )},
        ],
    }
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        v = json.load(r)
    return v["choices"][0]["message"]["content"].strip().strip('"'), float(v.get("usage", {}).get("cost") or 0)


def make_set(n):
    studios = psql("vector", "SELECT user_id, studio_id, count(*) FROM chunks GROUP BY 1, 2 HAVING count(*) >= 5 ORDER BY 3 DESC")
    rows = []
    for user, studio, _ in studios:
        rows += [(user, studio, cid) for (cid,) in psql("vector", f"SELECT id FROM chunks WHERE studio_id = '{studio}' AND length(content) > 300")]
    random.Random(7).shuffle(rows)
    rows = rows[:n]
    key = psql("octopilot", "SELECT key FROM api_keys WHERE provider = 'openrouter' AND is_active ORDER BY id LIMIT 1")[0][0]
    model = (psql("octopilot", "SELECT value FROM system_settings WHERE key = 'secondary_model'") or [["google/gemini-3.1-flash-lite-preview"]])[0][0]
    out, cost = [], 0.0
    for user, studio, cid in rows:
        (content,) = psql("vector", f"SELECT content FROM chunks WHERE id = '{cid}'")[0]
        q, c = ask_model(key, model, content)
        cost += c
        out.append({"user": user, "studio": studio, "chunk": cid, "question": q})
    print(f"made {len(out)} questions with {model} for ${cost:.4f}")
    return out


def search(api, item, k):
    qs = urllib.parse.urlencode({"user_id": item["user"], "studio_id": item["studio"], "q": item["question"], "k": k})
    with urllib.request.urlopen(f"{api}/search?{qs}", timeout=30) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=30)
    ap.add_argument("--api", default="http://127.0.0.1:8110")
    ap.add_argument("--set", default="recall_set.json")
    a = ap.parse_args()
    if os.path.exists(a.set):
        items = json.load(open(a.set))
    else:
        items = make_set(a.n)
        json.dump(items, open(a.set, "w"), indent=1, ensure_ascii=False)
    ranks, degraded = [], 0
    for it in items:
        r = search(a.api, it, 10)
        degraded += r["degraded"]
        ids = [h["id"] for h in r["hits"]]
        ranks.append(ids.index(it["chunk"]) + 1 if it["chunk"] in ids else None)
    n = len(ranks)
    at = lambda k: sum(1 for x in ranks if x and x <= k) / n
    mrr = sum(1 / x for x in ranks if x) / n
    print(f"questions {n} | recall@1 {at(1):.2f} | recall@5 {at(5):.2f} | recall@10 {at(10):.2f} | MRR {mrr:.2f} | degraded {degraded}")
    misses = [it["question"][:90] for it, x in zip(items, ranks) if not x or x > 5]
    for m in misses[:5]:
        print("  miss:", m)


main()
