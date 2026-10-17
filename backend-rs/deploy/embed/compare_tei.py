"""TEI vs the vectors already stored (made by the Python sentence-transformers
service): cosine per passage, plus the same check on a few queries against
the Python service live, and the time per batch of 16.

    python3 compare_tei.py [--tei http://127.0.0.1:8093] [--py http://127.0.0.1:8091] [--n 40]
"""
import argparse
import json
import subprocess
import time
import urllib.request


def post(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def tei(base, texts):
    return post(f"{base}/embed", {"inputs": texts, "truncate": True, "normalize": True})


def cos(a, b):
    return sum(x * y for x, y in zip(a, b)) / ((sum(x * x for x in a) ** 0.5) * (sum(y * y for y in b) ** 0.5))


ap = argparse.ArgumentParser()
ap.add_argument("--tei", default="http://127.0.0.1:8093")
ap.add_argument("--py", default="http://127.0.0.1:8091")
ap.add_argument("--n", type=int, default=40)
a = ap.parse_args()

out = subprocess.run(
    ["docker", "exec", "octo-pg", "psql", "-U", "octo_admin", "-d", "vector", "-Atc",
     f"SELECT json_agg(json_build_object('c', content, 'e', embedding::text)) FROM "
     f"(SELECT content, embedding FROM chunks ORDER BY random() LIMIT {a.n}) s"],
    check=True, capture_output=True, text=True,
).stdout
rows = json.loads(out)
texts = [r["c"] for r in rows]
stored = [json.loads(r["e"]) for r in rows]

t0 = time.time()
got = []
for i in range(0, len(texts), 16):
    got += tei(a.tei, texts[i:i + 16])
dt = (time.time() - t0) / max(1, (len(texts) + 15) // 16)
c = [cos(x, y) for x, y in zip(got, stored)]
print(f"passages {len(c)} | cosine min {min(c):.5f} mean {sum(c)/len(c):.5f} | dim {len(got[0])} | {dt:.2f}s per 16")

qs = ["What is congestion control?", "Explain the leader's role in a team", "database index performance"]
t0 = time.time()
tq = tei(a.tei, qs)
t_tei = time.time() - t0
t0 = time.time()
pq = post(f"{a.py}/embed", {"texts": qs})["vectors"]
t_py = time.time() - t0
print("queries cosine", [round(cos(x, y), 5) for x, y in zip(tq, pq)], f"| TEI {t_tei:.2f}s vs Python {t_py:.2f}s for 3")
