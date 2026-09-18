import httpx
from fastapi import APIRouter, HTTPException

from app.services.humanizer import HumanizerService


router = APIRouter(prefix="/humanizer", tags=["humanizer"])
service = HumanizerService()


@router.post("/stealthgpt")
async def stealthgpt(payload: dict):
    try:
        return await service.stealthgpt(payload)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except httpx.HTTPStatusError as error:
        raise HTTPException(
            status_code=error.response.status_code,
            detail=error.response.text,
        ) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@router.post("/undetectable")
async def undetectable(payload: dict):
    try:
        return await service.undetectable(payload)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except httpx.HTTPStatusError as error:
        raise HTTPException(
            status_code=error.response.status_code,
            detail=error.response.text,
        ) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@router.post("/undetectable/document")
async def undetectable_document(payload: dict):
    try:
        document_id = str(payload.get("id") or "")
        return await service.undetectable_document(document_id)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except httpx.HTTPStatusError as error:
        raise HTTPException(
            status_code=error.response.status_code,
            detail=error.response.text,
        ) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error
