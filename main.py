"""Divine-Ollama gateway: Supabase-authenticated, rate-limited proxy to a private Ollama."""
import json
import os
import time
from collections import defaultdict, deque

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

SB_URL = os.environ["SUPABASE_URL"].rstrip("/")
SB_KEY = os.environ["SUPABASE_ANON_KEY"]
OLLAMA = os.environ.get("OLLAMA_URL", "http://ollama:11434")
ORIGINS = [o.strip() for o in os.environ["ALLOWED_ORIGINS"].split(",") if o.strip()]
MODELS = [m.strip() for m in os.environ.get("ALLOWED_MODELS", "llama3.2:3b").split(",") if m.strip()]
LIMIT = int(os.environ.get("RATE_PER_MIN", "20"))
MAX_MSGS, MAX_CHARS = 40, 12000
SYSTEM = ("You are Divine-Ollama, a clear and concise assistant for writing, coding and research. "
          "Put code in fenced blocks. If you are unsure, say so.")

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(CORSMiddleware, allow_origins=ORIGINS, allow_methods=["GET", "POST"],
                   allow_headers=["Authorization", "Content-Type"])
http = httpx.AsyncClient(timeout=httpx.Timeout(300, connect=10))
_cache: dict = {}
_hits: dict = defaultdict(deque)


async def current_user(auth: str | None) -> dict:
    """Validate the Supabase access token by asking Supabase itself (works for any signing method)."""
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(401, "Missing token")
    token = auth[7:].strip()
    hit = _cache.get(token)
    if hit and hit[0] > time.time():
        return hit[1]
    try:
        r = await http.get(f"{SB_URL}/auth/v1/user",
                           headers={"apikey": SB_KEY, "Authorization": f"Bearer {token}"})
    except httpx.HTTPError:
        raise HTTPException(503, "Auth service unreachable")
    if r.status_code != 200:
        raise HTTPException(401, "Invalid or expired session")
    user = r.json()
    if not user.get("email_confirmed_at"):
        raise HTTPException(403, "Please verify your email first")
    if len(_cache) > 2000:
        _cache.clear()
    _cache[token] = (time.time() + 60, user)
    return user


def rate_limit(uid: str) -> None:
    q, now = _hits[uid], time.time()
    while q and q[0] < now - 60:
        q.popleft()
    if len(q) >= LIMIT:
        raise HTTPException(429, "Too many requests")
    q.append(now)


@app.get("/health")
async def health():
    return {"status": True}


@app.get("/v1/models")
async def models(authorization: str | None = Header(None)):
    await current_user(authorization)
    try:
        r = await http.get(f"{OLLAMA}/api/tags")
        have = {m["name"] for m in r.json().get("models", [])}
    except Exception:
        raise HTTPException(503, "Model server unavailable")
    return {"models": [m for m in MODELS if m in have]}


@app.post("/v1/chat")
async def chat(req: Request, authorization: str | None = Header(None)):
    user = await current_user(authorization)
    rate_limit(user["id"])
    try:
        body = await req.json()
    except Exception:
        raise HTTPException(400, "Invalid JSON")
    model, msgs = body.get("model"), body.get("messages")
    if model not in MODELS:
        raise HTTPException(400, "Model not allowed")
    if not isinstance(msgs, list) or not msgs or len(msgs) > MAX_MSGS:
        raise HTTPException(400, "Invalid messages")
    clean = []
    for m in msgs:
        if (not isinstance(m, dict) or m.get("role") not in ("user", "assistant")
                or not isinstance(m.get("content"), str) or len(m["content"]) > MAX_CHARS):
            raise HTTPException(400, "Invalid message")
        clean.append({"role": m["role"], "content": m["content"]})
    payload = {"model": model, "stream": True,
               "messages": [{"role": "system", "content": SYSTEM}] + clean,
               "options": {"num_ctx": 4096, "num_predict": 1024}}

    async def stream():
        try:
            async with http.stream("POST", f"{OLLAMA}/api/chat", json=payload) as r:
                if r.status_code != 200:
                    yield json.dumps({"error": "Model server error"}) + "\n"
                    return
                async for line in r.aiter_lines():
                    if line:
                        yield line + "\n"
        except Exception:
            yield json.dumps({"error": "Model server unavailable"}) + "\n"

    return StreamingResponse(stream(), media_type="application/x-ndjson",
                             headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})
