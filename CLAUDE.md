# IEOR Email Advising System

## Project Overview

Columbia IEOR email advising system built with **FastAPI** (backend) + **Next.js 16** (frontend). Automates advisor email responses using semantic matching and LLM generation.

### Stack
- **Backend:** FastAPI + SQLite with SQLAlchemy ORM
- **Frontend:** Next.js 16 with TypeScript + Tailwind
- **LLM:** OpenAI GPT-4o (via `gpt-4o` model in `Backend/email_advising/llm.py`)
- **Embeddings:** sentence-transformers (`multi-qa-MiniLM-L6-cos-v1`)
- **Auth:** Client-side password gate (no middleware)
- **Gmail:** OAuth 2.0 integration via Google API

### Directory Structure
```
/opt/ieor-email-advising/
├── Backend/
│   ├── api.py (main FastAPI app)
│   ├── email_advising/
│   │   ├── advisor.py (semantic matching + LLM composition)
│   │   ├── llm.py (OpenAI integration)
│   │   └── personal_detector.py (sensitive content detection)
│   ├── data/
│   │   ├── knowledge_base.json (FAQ articles)
│   │   ├── google_client_secrets.json (OAuth credentials)
│   │   └── gmail_token.json (stored OAuth tokens)
│   ├── .env (config: OpenAI key, URLs)
│   └── venv/
├── Frontend/
│   ├── components/ (tabs, tables, UI)
│   ├── lib/constants.ts (BACKEND_URL, ADVISORS list)
│   ├── .env.local (NEXT_PUBLIC_BACKEND_URL, ADVISOR_PASSWORD)
│   └── package.json
└── README.md
```

### Ports & Access
- **Backend:** Port 8000 (`http://128.59.149.172:8000`)
- **Frontend:** Port 3000 (`http://128.59.149.172:3000` or `http://128.59.149.172.nip.io:3000`)
- **Frontend password:** `IEOREMAILADVISOR2026` (set in `Frontend/.env.local`)

---

## Current Status (2026-04-20)

### What Works ✅
- Email syncing from Gmail (OAuth 2.0)
- Email ingestion and storage
- Personal/sensitive email detection
- Template-based email responses (fallback mode)
- Manual review and bulk actions
- Email assignment to advisors
- Auto-send for high-confidence replies

### What Needs Setup ⚠️
- **OpenAI API Key:** Currently set to placeholder `your-openai-api-key-here`
  - Without it: system uses template responses (no LLM)
  - With it: system generates smart, context-aware replies

### Running the App

**Terminal 1 - Backend:**
```bash
cd /opt/ieor-email-advising/Backend
source venv/bin/activate
uvicorn api:app --host 0.0.0.0 --port 8000
```

**Terminal 2 - Frontend:**
```bash
cd /opt/ieor-email-advising/Frontend
npm run dev -- --hostname 0.0.0.0 --port 3000
```

**Access:** `http://128.59.149.172:3000` or `http://128.59.149.172.nip.io:3000`

---

## Recent Fixes (Session 2026-04-20)

### Issue 1: "Failed to fetch" on `/gmail/fetch` endpoint
**Root cause:** Query parameter type error in `sync_emails()` function
- **Error:** `TypeError: int() argument must be a string, a bytes-like object or a real number, not 'Query'`
- **Location:** `Backend/api.py:1252` when calling Gmail API
- **Fix:** Changed `sync_emails(limit: int = Query(...))` to `limit: int = 20` and cast `int(limit)` in endpoint
- **Why:** FastAPI only parses Query params at endpoint layer; internal function calls get the raw object

### Issue 2: AttributeError when embedding model is None
**Root cause:** Advisor tries to use embeddings when OpenAI key is invalid
- **Error:** `AttributeError: 'NoneType' object has no attribute 'encode'`
- **Location:** `Backend/email_advising/advisor.py:117` in `rank_articles()`
- **Fix:** Added null check: `if not self.embedding_model: return []`
- **Why:** Invalid OpenAI key causes advisor init without embedder, but code didn't handle it gracefully

### Issue 3: CORS rejection from browser
**Root cause:** Frontend origin mismatch
- **Error:** "Disallowed CORS origin" from backend
- **Problem:** Frontend was using `http://128.59.149.172.nip.io:3000` but backend only allowed `http://128.59.149.172:3000`
- **Fix 1:** Updated `Backend/.env` `FRONTEND_URL` to match nip.io domain
- **Fix 2:** Added `http://128.59.149.172:3000` directly to CORS allow-list for users accessing via IP

### Commits
- `9a90c43` - Fix Gmail fetch endpoint errors and CORS configuration
- `7fd8e3b` - Allow CORS from both IP address and nip.io domain

---

## System Architecture

### Email Processing Flow
1. **Sync:** User clicks "Sync Emails" → calls `/gmail/fetch` → pulls unread emails from Gmail
2. **Ingest:** For each email:
   - Extract subject, body, sender info
   - Check for duplicates (subject + body)
   - Mark as personal if sensitive content detected
3. **Classify:** Run through advisor:
   - If personal → mark as `personal`, use sensitive response template
   - If not personal:
     - Rank knowledge base articles via semantic embedding
     - Generate reply with LLM (if key valid) or template (if not)
     - Calculate confidence score
     - If confidence ≥ threshold → auto-send; else → manual review
4. **Store:** Save to SQLite with status (`auto`, `review`, `sent`, `personal`)
5. **Send:** Auto-send high-confidence replies, or user manually approves in UI

### Fallback Behavior (No LLM)
When OpenAI key is invalid or missing:
- `rank_articles()` returns empty list (no semantic matches)
- `process_query()` triggers fallback response
- System uses hardcoded templates for replies
- **App remains fully functional** — just less intelligent

---

## Configuration

### Backend Environment (`Backend/.env`)
```
OPENAI_API_KEY=your-openai-api-key-here          # ⚠️ MUST BE VALID
FRONTEND_URL=http://128.59.149.172.nip.io:3000  # Used for CORS
BACKEND_URL=http://128.59.149.172.nip.io:8000   # Not currently used by backend
```

### Frontend Environment (`Frontend/.env.local`)
```
NEXT_PUBLIC_BACKEND_URL=http://128.59.149.172.nip.io:8000  # API endpoint
ADVISOR_PASSWORD=IEOREMAILADVISOR2026                       # UI access password
```

### Gmail Credentials
- **OAuth setup:** `Backend/data/google_client_secrets.json` (Google Cloud Console)
- **Stored tokens:** `Backend/data/gmail_token.json` (auto-created on first auth)

---

## Getting a Valid OpenAI API Key

1. Go to https://platform.openai.com/api-keys
2. Create a new API key or copy existing one
3. **Important:** Avoid pasting extra spaces — copy the full key cleanly
4. Paste into `Backend/.env` as:
   ```
   OPENAI_API_KEY=sk-proj-xxxx...
   ```
5. Restart backend: `uvicorn api:app --host 0.0.0.0 --port 8000`

Once valid, the app will:
- Use semantic matching on knowledge base
- Generate smart, context-aware LLM responses
- Provide confidence scores for auto-send decisions

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "Failed to fetch" on sync | Query param type error or CORS | Backend endpoint fixed; CORS allows both IP and nip.io |
| "Could not load dashboard data" | Backend not running or unreachable | Start backend on port 8000 |
| No LLM responses, only templates | OpenAI key invalid | Paste valid key in `Backend/.env`, restart backend |
| Gmail sync fails | OAuth tokens expired or not initialized | Re-auth via Settings tab → Connect Gmail |
| CORS rejected by browser | Origin mismatch | Use `http://128.59.149.172.nip.io:3000` or direct IP both work now |

---

## Notes for Future Development

- **No Alembic migrations:** Schema changes work directly on SQLite
- **Async:** FastAPI is async-capable but currently uses sync handlers
- **Embeddings:** Sentence-transformers uses CPU; consider GPU if scaling
- **Trash feature:** Exists on `main` and `feature/trash-tab` branches; soft-delete/restore implemented
- **Testing:** No automated tests; manual testing required
- **Grafana:** Was disabled (`sudo systemctl stop/disable grafana-server`) to free port 3000

---

## Git Branches
- `main` — Trash feature (working)
- `feature/trash-tab` — Same as main
- `before-trash` — Current working branch (endpoint fixes applied)
- Remote: `myfork` = https://github.com/dd226/ieor-email-advising
