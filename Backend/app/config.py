"""Typed settings loaded from environment / `.env`."""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # API
    app_env: str = "dev"
    api_host: str = "0.0.0.0"
    api_port: int = 8100
    cors_origins: str = "http://localhost:8765"

    # Databases
    cockpit_database_url: str = (
        "postgresql+asyncpg://cockpit:cockpit@cockpit-db:5432/cockpit"
    )
    vector_database_url: str = (
        "postgresql+asyncpg://vector:vector@cockpit-vectordb:5432/vector"
    )
    embedding_dim: int = 1024
    # Shared identity/credits DB (the native octopilot Postgres). Blank => off.
    shared_database_url: str = ""

    # Object storage
    object_store_endpoint: str = "http://cockpit-minio:9000"
    object_store_region: str = "us-east-1"
    object_store_bucket: str = "cockpit-rag"
    object_store_access_key: str = "minioadmin"
    object_store_secret_key: str = "minioadmin"
    object_store_force_path_style: bool = True

    # Embeddings
    embeddings_backend: str = "fallback"  # sentence-transformers | fallback
    embeddings_model: str = "BAAI/bge-m3"

    # Auth (Firebase — reuse Octopilot's Firebase project)
    # We verify Firebase ID tokens against Google's public keys (same method as
    # octopilot's auth.py) — NO service-account JSON needed, just the project id.
    # Blank project id => verification off; the API falls back to X-User-Id (dev).
    firebase_project_id: str = ""
    # Kept for back-compat / optional ADC; not required for token verification.
    firebase_credentials: str = ""
    # Allow the X-User-Id dev header even when Firebase is on (turn off in prod).
    allow_dev_user_header: bool = True

    # LLM (OpenRouter)
    openrouter_api_key: str = ""
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    openrouter_model: str = "anthropic/claude-opus-4.6"

    # RAG
    rag_chunk_tokens: int = 512
    rag_chunk_overlap: int = 64
    rag_top_k: int = 8
    rag_context_k: int = 5

    # Hirara document-extraction hub (PDF / Office / OCR). The cockpit-api runs
    # host-networked, so the gateway is reachable on loopback. Token is opt-in.
    hirara_hub_url: str = "http://127.0.0.1:8080"
    hirara_hub_token: str = ""
    # Whole-file OCR of a PDF is extremely slow (minutes). Default off: use the
    # embedded text layer (pypdf, then Hirara pdf_read). Images still OCR.
    ingest_pdf_ocr: bool = True

    # Go workers
    embed_service_url: str = ""  # http://127.0.0.1:8091 — dedicated embed process
    search_service_url: str = ""  # http://127.0.0.1:8092
    redis_url: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def shared_db_enabled(self) -> bool:
        return bool(self.shared_database_url.strip())

    @property
    def firebase_enabled(self) -> bool:
        return bool(self.firebase_project_id.strip())


@lru_cache
def get_settings() -> Settings:
    return Settings()
