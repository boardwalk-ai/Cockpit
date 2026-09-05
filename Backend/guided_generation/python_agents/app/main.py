import json

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse

from app.agents.alvin import AlvinAgent
from app.agents.hein import HeinAgent
from app.agents.lily import LilyAgent
from app.agents.lucas import LucasAgent
from app.agents.octo import OctoAgent
from app.agents.spoonie import SpoonieAgent
from app.agents.su import SuAgent
from app.agents.zuly import ZulyAgent
from app.model_client import ModelClient
from app.routes.humanizer import router as humanizer_router


app = FastAPI(title="Guided Generation Agents")
app.include_router(humanizer_router)

secondary_model_client = ModelClient("OPENROUTER_SECONDARY_MODEL")
primary_model_client = ModelClient("OPENROUTER_PRIMARY_MODEL")

hein = HeinAgent(secondary_model_client)
lily = LilyAgent(secondary_model_client)
lucas = LucasAgent(primary_model_client)
alvin = AlvinAgent(secondary_model_client)
zuly = ZulyAgent(secondary_model_client)
spoonie = SpoonieAgent(secondary_model_client)
su = SuAgent(secondary_model_client)
octo = OctoAgent(secondary_model_client)


def sse_event(name: str, data=None) -> str:
    payload = {} if data is None else data
    return f"event: {name}\ndata: {json.dumps(payload)}\n\n"


@app.get("/health")
async def health():
    return {"status": "ok", "service": "guided-generation-python-agents"}


async def call_agent(callback, payload):
    try:
        return await callback(payload)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@app.post("/agents/hein/analyze")
async def analyze_assignment(payload: dict):
    return await call_agent(hein.analyze, payload)


@app.post("/agents/lily/generate")
async def generate_outline(payload: dict):
    return await call_agent(lily.generate, payload)


@app.post("/agents/alvin/search")
async def search_sources(payload: dict):
    return await call_agent(alvin.search, payload)


@app.post("/agents/zuly/compact")
async def compact_source(payload: dict):
    return await call_agent(zuly.run, payload)


@app.post("/agents/spoonie/citation")
async def spoonie_task(payload: dict):
    return await call_agent(spoonie.run, payload)


@app.post("/agents/su/assist")
async def su_assist(payload: dict):
    return await call_agent(su.assist, payload)


@app.post("/agents/octo/assist")
async def octo_assist(payload: dict):
    return await call_agent(octo.assist, payload)


@app.post("/agents/lucas/generate")
async def generate_essay(payload: dict):
    async def stream():
        try:
            async for delta in lucas.generate_stream(payload):
                yield sse_event("delta", {"text": delta})
            client = getattr(lucas, "model_client", primary_model_client)
            yield sse_event("meta", {"model": client.model})
            yield sse_event("done")
        except ValueError as error:
            yield sse_event("error", {"message": str(error), "status": 400})
        except Exception as error:
            yield sse_event("error", {"message": str(error), "status": 502})

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
