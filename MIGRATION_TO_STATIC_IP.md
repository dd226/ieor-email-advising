# Migration Guide: Dynamic IP → Static IP + DNS

## Overview
This guide walks through migrating the app from a dynamic IP address (e.g., `128.59.149.172`) to a static IP with a proper DNS name (e.g., `advising.ieor.columbia.edu`).

**Timeline:** ~30 minutes setup + testing

---

## Pre-Migration Checklist

Before starting, make sure you have:
- [ ] Reserved static IP address from Columbia IT
- [ ] DNS name registered (advising.ieor.columbia.edu)
- [ ] DNS pointed to your static IP
- [ ] SSL certificate (Let's Encrypt or institutional)
- [ ] SSL certificates installed on the server
- [ ] Backed up current configuration

---

## Step 1: Update Environment Variables

### Backend Configuration
File: `Backend/.env`

**Before:**
```
OPENAI_API_KEY=sk-...
FRONTEND_URL=http://128.59.149.172.nip.io:3000
BACKEND_URL=http://128.59.149.172.nip.io:8000
```

**After:**
```
OPENAI_API_KEY=sk-...
FRONTEND_URL=https://advising.ieor.columbia.edu:3000
BACKEND_URL=https://advising.ieor.columbia.edu:8000
```

### Frontend Configuration
File: `Frontend/.env.local`

**Before:**
```
NEXT_PUBLIC_BACKEND_URL=http://128.59.149.172.nip.io:8000
ADVISOR_PASSWORD=IEOREMAILADVISOR2026
```

**After:**
```
NEXT_PUBLIC_BACKEND_URL=https://advising.ieor.columbia.edu:8000
ADVISOR_PASSWORD=IEOREMAILADVISOR2026
```

---

## Step 2: Update CORS Configuration

File: `Backend/api.py` (lines 157-159)

**The code should already handle this via FRONTEND_URL**, but verify:

```python
_cors_origins = ["http://localhost:3000", "http://127.0.0.1:3000"]
if FRONTEND_URL and FRONTEND_URL not in _cors_origins:
    _cors_origins.append(FRONTEND_URL)
```

**Remove any hardcoded IP addresses** if they exist:
```python
# DELETE THIS LINE if it exists:
# "http://128.59.149.172:3000"
```

---

## Step 3: Update Gmail OAuth (CRITICAL!)

### 3a. Google Cloud Console

1. Go to Google Cloud Console → your project
2. Navigate to **APIs & Services → Credentials**
3. Find your OAuth 2.0 Client ID
4. Click **Edit**
5. Update **Authorized redirect URIs**:
   - Remove: `http://128.59.149.172:8000/gmail/oauth2callback`
   - Remove: `http://128.59.149.172.nip.io:8000/gmail/oauth2callback`
   - Add: `https://advising.ieor.columbia.edu:8000/gmail/oauth2callback`
6. Click **Save**

### 3b. Google Client Secrets File

File: `Backend/data/google_client_secrets.json`

**Check if redirect_uri needs updating** (if you manage it locally):
```json
{
  "installed": {
    "client_id": "...",
    "redirect_uris": [
      "https://advising.ieor.columbia.edu:8000/gmail/oauth2callback"
    ]
  }
}
```

---

## Step 4: Re-authenticate Gmail (Important!)

The stored Gmail token (`Backend/data/gmail_token.json`) may not work with the new redirect URI.

**Steps:**
1. **Delete the old token:**
   ```bash
   rm Backend/data/gmail_token.json
   ```

2. **Restart backend and access Settings tab**

3. **Click "Connect Gmail" button** — you'll be redirected to Google login

4. **Follow the OAuth flow** — system will generate new `gmail_token.json`

5. **Verify Gmail sync works** — click "Sync Emails" button

---

## Step 5: Configure SSL/HTTPS

### Option A: Let's Encrypt (Free)

```bash
# Install Certbot
sudo apt-get install certbot python3-certbot-nginx

# Get certificate
sudo certbot certonly --standalone -d advising.ieor.columbia.edu

# Certificates will be in:
# /etc/letsencrypt/live/advising.ieor.columbia.edu/
```

### Option B: Use Institutional Certificate
Contact Columbia IT for certificate generation and installation.

### Configure Frontend (Next.js)

Update startup command to use HTTPS:
```bash
# Create self-signed or use institutional cert
# For production, use Let's Encrypt or institutional cert
next start -- --port 3000 --experimental-https
```

Or use a reverse proxy (Nginx) to handle SSL.

### Configure Backend (FastAPI + Uvicorn)

```bash
uvicorn api:app \
  --host 0.0.0.0 \
  --port 8000 \
  --ssl-keyfile=/etc/letsencrypt/live/advising.ieor.columbia.edu/privkey.pem \
  --ssl-certfile=/etc/letsencrypt/live/advising.ieor.columbia.edu/fullchain.pem
```

---

## Step 6: Test Everything

### Test 1: DNS Resolution
```bash
nslookup advising.ieor.columbia.edu
# Should return your static IP
```

### Test 2: Frontend Access
```bash
curl -k https://advising.ieor.columbia.edu:3000
# Should return HTML (ignore SSL warnings for self-signed)
```

### Test 3: Backend Access
```bash
curl -k https://advising.ieor.columbia.edu:8000/metrics
# Should return JSON metrics
```

### Test 4: CORS
```bash
curl -k https://advising.ieor.columbia.edu:8000/metrics \
  -H "Origin: https://advising.ieor.columbia.edu:3000"
# Should include correct CORS headers
```

### Test 5: Gmail Sync
1. Open app in browser
2. Go to Settings tab
3. Click "Connect Gmail"
4. Follow OAuth flow
5. Go to main tab and click "Sync Emails"
6. Verify emails sync successfully

### Test 6: Full Email Flow
1. Send test email to `ieor.admit.info@gmail.com`
2. Sync emails
3. Verify email appears in dashboard
4. Click "Sync" again to confirm it works twice

---

## Step 7: Update DNS Records (if not already done)

```bash
# Point your domain to the static IP
# Example DNS A record:
advising.ieor.columbia.edu  IN  A  <your-static-ip>
```

Verify DNS propagation (may take 1-24 hours):
```bash
dig advising.ieor.columbia.edu
# Should show your static IP
```

---

## Rollback (If Something Breaks)

### Quick Rollback
```bash
# Revert to old IP in environment files
# Restart backend and frontend
cd Backend && source venv/bin/activate && uvicorn api:app --host 0.0.0.0 --port 8000
cd Frontend && npm run dev
```

### If Gmail OAuth Fails
```bash
# Revert Google Cloud Console OAuth redirect URIs
# Delete new gmail_token.json and re-auth with old IP
rm Backend/data/gmail_token.json
# Access Settings tab and reconnect Gmail
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Failed to fetch" | CORS origin mismatch | Verify `FRONTEND_URL` in Backend/.env matches domain |
| Gmail auth fails | Redirect URI not in Google Cloud Console | Add `https://advising.ieor.columbia.edu:8000/gmail/oauth2callback` |
| SSL certificate errors | Self-signed or expired cert | Use Let's Encrypt or institutional certificate |
| DNS not resolving | DNS not propagated | Wait 1-24 hours or verify A record created |
| Mixed content warning | HTTPS frontend + HTTP backend | Use HTTPS for both or HTTP for both |

---

## Files That Changed

- `Backend/.env` — FRONTEND_URL, BACKEND_URL
- `Frontend/.env.local` — NEXT_PUBLIC_BACKEND_URL
- `Backend/api.py` — CORS allow-list (verify)
- `Backend/data/google_client_secrets.json` — redirect_uri
- `Backend/data/gmail_token.json` — DELETE and regenerate
- SSL certificates (new)

---

## Post-Migration

After successful migration:

1. **Update documentation** — replace all IP references with domain
2. **Share new URL** with users: `https://advising.ieor.columbia.edu:3000`
3. **Monitor logs** for any issues
4. **Set up SSL renewal** — Let's Encrypt certs expire every 90 days

```bash
# Auto-renew Let's Encrypt (add to crontab)
0 0 1 * * certbot renew
```

5. **Update memory files** with new static IP and domain
6. **Commit changes** to git

```bash
git add Backend/.env Frontend/.env.local
git commit -m "Migration: Update to static IP and domain advising.ieor.columbia.edu"
git push
```

---

## Questions?

Refer to the memory file `migration_procedure.md` or ask Claude Code to migrate automatically using the migration script.
