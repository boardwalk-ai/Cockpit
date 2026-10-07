"""Compare the Rust study-api (shadow, :8110) with the Python DTOs for every
studio. Prints counts and differing paths only — no field values."""
import asyncio
import json
from datetime import datetime

import httpx
from sqlalchemy import select

from app.db import CockpitSession
from app.models.cockpit import Studio
from app.routers.stream import _db_studio_to_dto, _load_files, _load_scenarios, _load_topics


def norm(v):
    if isinstance(v, dict):
        return {k: norm(x) for k, x in v.items()}
    if isinstance(v, list):
        return [norm(x) for x in v]
    if isinstance(v, str) and len(v) >= 19 and v[4] == "-" and v[10] == "T":
        try:
            return round(datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp(), 3)
        except ValueError:
            return v
    if isinstance(v, float):
        return round(v, 6)
    return v


def diff(a, b, path="", out=None):
    out = [] if out is None else out
    if type(a) is not type(b) and not (isinstance(a, (int, float)) and isinstance(b, (int, float))):
        out.append(f"{path}: type {type(a).__name__} vs {type(b).__name__}")
    elif isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                out.append(f"{path}.{k}: missing in {'python' if k not in a else 'rust'}")
            else:
                diff(a[k], b[k], f"{path}.{k}", out)
    elif isinstance(a, list):
        if len(a) != len(b):
            out.append(f"{path}: len {len(a)} vs {len(b)}")
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, f"{path}[{i}]", out)
    elif a != b:
        out.append(f"{path}: value differs")
    return out


def sse_data(text):
    name = None
    for line in text.splitlines():
        if line.startswith("event:"):
            name = line[6:].strip()
        elif line.startswith("data:") and name == "data":
            return json.loads(line[5:].strip())
    return None


async def main():
    total = 0
    bad = 0
    async with CockpitSession() as c:
        rows = (await c.execute(select(Studio))).scalars().all()
        for row in rows:
            py = _db_studio_to_dto(
                row,
                await _load_topics(c, row.id, row.user_id),
                await _load_scenarios(c, row.id),
                await _load_files(c, row.id, row.user_id),
            ).model_dump(mode="json", by_alias=True)
            r = httpx.get(
                f"http://127.0.0.1:8110/studios/{row.id}",
                headers={"X-User-Id": str(row.user_id)},
                timeout=30,
            )
            rs = sse_data(r.text)
            total += 1
            if rs is None:
                bad += 1
                print(row.id, "rust: no data event", r.status_code)
                continue
            d = diff(norm(py), norm(rs))
            topics = len(py["topics"])
            cards = sum(len(t["flashcards"]) for t in py["topics"])
            if d:
                bad += 1
                print(str(row.id)[:8], f"topics={topics} cards={cards}", "DIFF", len(d), d[:6])
            else:
                print(str(row.id)[:8], f"topics={topics} cards={cards}", "identical")
    # Someone else's studio must not be readable.
    if rows:
        r = httpx.get(
            f"http://127.0.0.1:8110/studios/{rows[0].id}",
            headers={"X-User-Id": "00000000-0000-0000-0000-000000000001"},
            timeout=30,
        )
        print("other user's studio ->", "error event" if "event: error" in r.text else "LEAK")
    print(f"{total - bad}/{total} studios identical")


asyncio.run(main())
