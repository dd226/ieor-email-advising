# IEOR Email Advising System

## Project Overview

Columbia IEOR email advising system built with **FastAPI** (backend) + **Next.js 16** (frontend). Automates advisor email responses using semantic matching and LLM generation.

### Stack
- **Backend:** FastAPI + SQLite with SQLAlchemy ORM
- **Frontend:** Next.js 16 with TypeScript + Tailwind
- **LLM:** OpenAI GPT-4o (via `gpt-4o` model in `Backend/email_advising/llm.py`)
- **Embeddings:** sentence-transformers (`multi-qa-MiniLM-L6-cos-v1`)
- **Auth:** Client-side password gate (`/api/auth/login` Next.js route)
- **Gmail:** OAuth 2.0 integration via Google API
- **Reverse Proxy:** nginx (SSL termination, routing)

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
│   ├── .env (OpenAI key, FRONTEND_URL, BACKEND_URL)
│   └── venv/
├── Frontend/
│   ├── components/ (tabs, tables, UI)
│   ├── app/api/auth/login/route.ts (password check — server-side Next.js route)
│   ├── lib/constants.ts (BACKEND_URL, ADVISORS list)
│   ├── .env.local (NEXT_PUBLIC_BACKEND_URL, ADVISOR_PASSWORD)
│   └── package.json
└── README.md
```

---

## Production Architecture (as of 2026-04-22)

```
Browser → https://advising.ieor.columbia.edu (port 443)
    nginx (SSL termination with Let's Encrypt)
        /backend/* → strips prefix → FastAPI on localhost:8000 (HTTP)
        /*          → Next.js on 127.0.0.1:3000 (HTTP)
```

- **nginx** is the only public entry point — ports 3000 and 8000 are blocked externally
- **SSL cert:** Let's Encrypt at `/etc/letsencrypt/live/advising.ieor.columbia.edu/` (expires 2026-07-21, auto-renews)
- **Firewall (UFW):** ports 22/tcp, 80/tcp, 443/tcp open only

### Why This Architecture
- Columbia's campus network firewall blocks non-standard ports (3000, 8000) from the internet
- Next.js dev server doesn't support native SSL — nginx handles it
- Backend and frontend listen on localhost only — only reachable through nginx
- Port 80 stays open for Let's Encrypt auto-renewal (HTTP-01 challenge)

---

## Current Status (2026-04-23)

### What Works ✅
- Full HTTPS at `https://advising.ieor.columbia.edu` (padlock, valid cert)
- Password login (to be replaced with Google OAuth — plan ready, not yet implemented)
- Email syncing from Gmail (OAuth 2.0 connected)
- Email ingestion, deduplication, personal email detection
- LLM-generated email responses via GPT-4o (confirmed 81% confidence score)
- Template fallback for unmatched emails
- Manual review and bulk actions
- Email assignment to advisors
- All services managed by systemd (auto-restart, start on boot)

### What Needs Setup ⚠️
- **Google OAuth Login:** Plan is ready (see Future Work). Needs new GCP Web OAuth Client ID before implementing.

---

## Access

| | |
|---|---|
| **URL** | `https://advising.ieor.columbia.edu` |
| **Password** | `IEOREMAILADVISOR2026` |
| **Gmail OAuth callback** | `https://advising.ieor.columbia.edu/backend/gmail/oauth2callback` |

**Note:** The LastPass browser extension causes a React hydration warning on the login page — this is cosmetic and the app works fine. Disable LastPass on this domain or use incognito to suppress it.

---

## Managing Services

All services run as systemd units — **do not start manually**.

```bash
# Status
sudo systemctl status nginx
sudo systemctl status ieor-backend
sudo systemctl status ieor-frontend

# Restart (e.g. after config change)
sudo systemctl restart ieor-backend
sudo systemctl restart ieor-frontend
sudo systemctl reload nginx   # for nginx config changes

# Logs
sudo journalctl -u ieor-backend -n 50 --no-pager
sudo journalctl -u ieor-frontend -n 50 --no-pager
```

### Service Definitions
- `/etc/systemd/system/ieor-backend.service` — FastAPI on localhost:8000 (no SSL, nginx handles it)
- `/etc/systemd/system/ieor-frontend.service` — Next.js dev on 127.0.0.1:3000 (uses full nvm node path)
- `/etc/nginx/sites-available/ieor-advising` — nginx config (symlinked to sites-enabled)

---

## Configuration

### Backend/.env (current values)
```
OPENAI_API_KEY=<active key set 2026-04-23>
FRONTEND_URL=https://advising.ieor.columbia.edu
BACKEND_URL=https://advising.ieor.columbia.edu/backend
```

### Frontend/.env.local (current values)
```
NEXT_PUBLIC_BACKEND_URL=https://advising.ieor.columbia.edu/backend
ADVISOR_PASSWORD=IEOREMAILADVISOR2026
```

### CORS (Backend/api.py ~line 157)
```python
_cors_origins = ["http://localhost:3000", "http://127.0.0.1:3000", "http://128.59.146.240:3000", "https://advising.ieor.columbia.edu"]
```
The `FRONTEND_URL` env var is appended dynamically, so `https://advising.ieor.columbia.edu` appears twice — harmless.

### Gmail OAuth (Google Cloud Console)
- **App mode:** Testing (NOT production — no Google verification needed for single user)
- **Test user:** `dd226@columbia.edu` must be added to test users list
- **Registered redirect URI:** `https://advising.ieor.columbia.edu/backend/gmail/oauth2callback`
- **Client ID:** `1007215112214-iedfi53ogsmtr76tsempj38ssh58mqrl`

---

## nginx Config Summary

```nginx
# Port 80: redirect to HTTPS, allow Let's Encrypt renewal
server {
    listen 80;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://$host$request_uri; }
}

# Port 443: SSL termination, proxy routing
server {
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/advising.ieor.columbia.edu/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/advising.ieor.columbia.edu/privkey.pem;

    location /backend/ { proxy_pass http://localhost:8000/; }  # FastAPI
    location / { proxy_pass http://localhost:3000; }           # Next.js
}
```

**Critical:** `/backend/` prefix routes to FastAPI. `/api/` is reserved for Next.js internal routes (e.g. `/api/auth/login`). Do not use `/api/` as the FastAPI prefix.

---

## Email Processing Flow

1. **Sync:** "Sync Emails" → `/backend/gmail/fetch` → pulls unread from Gmail
2. **Ingest:** extract fields, check duplicates, detect personal emails
3. **Classify:** semantic embedding match → LLM reply (if key valid) or template fallback → confidence score
4. **Store:** SQLite with status (`auto`, `review`, `sent`, `personal`)
5. **Send:** auto-send high-confidence, or manual approval in UI

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Dashboard data fails to load | Old process on port 8000 without SSL | `sudo fuser -k 8000/tcp` then `sudo systemctl restart ieor-backend` |
| 502 Bad Gateway | Frontend or backend service down | `sudo systemctl restart ieor-frontend` or `ieor-backend` |
| Gmail OAuth "redirect URI not registered" | URI changed, GCP not updated | Update in Google Cloud Console → OAuth 2.0 Client ID |
| "App not verified" on Gmail OAuth | GCP app in Testing mode | Click Advanced → proceed anyway; or add test user in GCP console |
| No LLM responses, only templates | OpenAI key placeholder | Paste valid key in `Backend/.env`, `sudo systemctl restart ieor-backend` |
| Hydration warning on login | LastPass extension injecting HTML | Disable LastPass on this domain or use incognito — app works fine |
| Cert renewal fails | Port 80 blocked | `sudo ufw allow 80/tcp` — must stay open always |
| Frontend not picking up new env var | NEXT_PUBLIC vars baked in at compile | `sudo systemctl restart ieor-frontend` and wait ~30s for recompile |

---

## Troubleshooting nginx Issues

```bash
# Test config syntax before reloading
sudo nginx -t

# Check what's blocking a port
sudo fuser -k 8000/tcp
sudo fuser -k 3000/tcp

# Firewall status
sudo ufw status
```

---

## Session History

### Session 1 (2026-04-20) — Initial fixes
- Fixed `/gmail/fetch` Query param type error (`api.py:1252`)
- Fixed embedding model null check (`advisor.py:117`)
- Fixed CORS for both IP and nip.io domain

### Session 2 (2026-04-22) — Production HTTPS setup
- Migrated to static IP `128.59.146.240` / hostname `advising.ieor.columbia.edu`
- Installed Let's Encrypt certificate via certbot
- Installed nginx as SSL reverse proxy (port 443)
- Moved backend and frontend to systemd services
- Blocked ports 3000/8000 externally via UFW
- Updated Gmail OAuth redirect URI to `/backend/gmail/oauth2callback`
- Fixed `/api/` vs `/backend/` prefix conflict with Next.js routes
- Gmail OAuth working; app fully accessible over HTTPS

### Session 3 (2026-04-23) — OpenAI key + planning
- Activated OpenAI API key in `Backend/.env` — LLM (GPT-4o) now live, confirmed 81% confidence score
- Investigated sending emails from `info@ieor.columbia.edu` (Grouper group) — unresolved, needs Columbia IT SMTP relay or service account
- Discussed dev VM cloning strategy (hot snapshot from Windows Server, own SSL cert needed)
- **Planned** Google OAuth login (Auth.js v5) — plan at `/home/dd226/.claude/plans/the-website-cuurent-has-tranquil-puddle.md` — NOT YET IMPLEMENTED

---

## Git Branches
- `main` — Trash feature (soft-delete/restore)
- `feature/trash-tab` — Same as main
- `before-trash` — Current running branch (all fixes applied here)
- Remote: `myfork` = https://github.com/dd226/ieor-email-advising

---

## Backup & Recovery Strategy

### Current State
No backup/recovery plan yet. Recommended approach for warm VM failover:

**Known Issue:** Gmail sync has a backup/failover risk
- Sync relies on Gmail's `is:unread` flag + naive subject+body duplicate check
- Database does NOT store Gmail message IDs
- On failover to stale backup: old emails may be reprocessed, causing duplicate auto-sends

**Solutions (prioritized):**
1. **Best:** Store Gmail message IDs in database (`EmailORM.gmail_message_id`). Use as authoritative duplicate key. ~10 min code change to `api.py`.
2. **Workaround:** Before failover, sync once on primary to mark all emails read in Gmail.
3. **Mitigate:** Keep backup snapshots daily to minimize stale window.

**Recommended backup strategy:**
- Daily SQLite database backups to offsite storage
- Automated restore script (reinstall stack, restore DB + certs + configs)
- Warm standby VM image on another physical host (optional, for cold failover)

---

## Future Work
- **BLOCKING for production backup:** Implement Gmail message ID tracking (see Backup & Recovery section)
- **Google OAuth Login (plan ready):** Replace password gate with per-user Google OAuth using Auth.js v5. Plan at `/home/dd226/.claude/plans/the-website-cuurent-has-tranquil-puddle.md`. Pre-requisite: create new Web OAuth Client ID in GCP (separate from Gmail client).
- **Dev VM:** Clone production VM via Windows Server snapshot. Needs own hostname + SSL cert. Update .env files, nginx config, GCP redirect URIs.
- **Email sending from `info@ieor.columbia.edu`:** Grouper group, no SMTP credentials. Contact Columbia IT for SMTP relay or service account. Backend change: SMTP for sending only, keep Gmail OAuth for receiving.
- Consider upgrading Python 3.10 → 3.11+ (3.10 EOL: 2026-10-04)
- Consider `npm run build && npm run start` (production mode) instead of `dev` for better performance
- Merge `before-trash` fixes into `main`
