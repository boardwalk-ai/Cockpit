from dataclasses import dataclass, field
from math import sqrt


@dataclass
class MemoryItem:
    text: str
    vector: list[float]
    metadata: dict = field(default_factory=dict)


class SemanticMemory:
    def __init__(self):
        self.sessions: dict[str, list[MemoryItem]] = {}

    def add(
        self,
        session_id: str,
        text: str,
        vector: list[float],
        metadata: dict | None = None,
    ):
        self.sessions.setdefault(session_id, []).append(
            MemoryItem(
                text=text,
                vector=vector,
                metadata=metadata or {},
            )
        )

    def search(
        self,
        session_id: str,
        query_vector: list[float],
        limit: int = 5,
    ) -> list[MemoryItem]:
        memories = self.sessions.get(session_id, [])

        ranked = sorted(
            memories,
            key=lambda item: self._cosine(item.vector, query_vector),
            reverse=True,
        )

        return ranked[:limit]

    @staticmethod
    def _cosine(a: list[float], b: list[float]) -> float:
        if not a or not b or len(a) != len(b):
            return 0.0

        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sqrt(sum(x * x for x in a))
        norm_b = sqrt(sum(y * y for y in b))

        if norm_a == 0 or norm_b == 0:
            return 0.0

        return dot / (norm_a * norm_b)


memory = SemanticMemory()