#!/bin/bash
#
# Automated Migration Script: Dynamic IP → Static IP + DNS
#
# Usage: ./migrate_to_static_ip.sh <new_domain> [new_ip]
# Example: ./migrate_to_static_ip.sh advising.ieor.columbia.edu 128.59.149.173
#
# This script will:
# 1. Update environment variables
# 2. Update CORS configuration
# 3. Back up old configuration
# 4. Verify DNS resolution
# 5. Restart services (optional)

set -e  # Exit on error

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/.backups/$TIMESTAMP"

# Validate inputs
if [ -z "$1" ]; then
    log_error "Usage: $0 <new_domain> [new_ip]"
    log_info "Example: $0 advising.ieor.columbia.edu 128.59.149.173"
    exit 1
fi

NEW_DOMAIN="$1"
NEW_IP="${2:-}"

# Check if domain is valid (basic check)
if ! [[ "$NEW_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    log_error "Invalid domain name: $NEW_DOMAIN"
    exit 1
fi

echo ""
log_info "=== IEOR Email Advising System - Static IP Migration ==="
log_info "Target domain: $NEW_DOMAIN"
if [ -n "$NEW_IP" ]; then
    log_info "Target IP: $NEW_IP"
fi
echo ""

# Step 1: Create backup
log_info "Step 1/5: Creating backup..."
mkdir -p "$BACKUP_DIR"
cp "$PROJECT_ROOT/Backend/.env" "$BACKUP_DIR/.env.backend.backup"
cp "$PROJECT_ROOT/Frontend/.env.local" "$BACKUP_DIR/.env.frontend.backup"
log_success "Backup created at: $BACKUP_DIR"

# Step 2: Update Backend environment variables
log_info "Step 2/5: Updating backend environment variables..."
sed -i.bak "s|FRONTEND_URL=.*|FRONTEND_URL=https://${NEW_DOMAIN}:3000|g" "$PROJECT_ROOT/Backend/.env"
sed -i "s|BACKEND_URL=.*|BACKEND_URL=https://${NEW_DOMAIN}:8000|g" "$PROJECT_ROOT/Backend/.env"
log_success "Backend .env updated"
log_info "  FRONTEND_URL=https://${NEW_DOMAIN}:3000"
log_info "  BACKEND_URL=https://${NEW_DOMAIN}:8000"

# Step 3: Update Frontend environment variables
log_info "Step 3/5: Updating frontend environment variables..."
sed -i.bak "s|NEXT_PUBLIC_BACKEND_URL=.*|NEXT_PUBLIC_BACKEND_URL=https://${NEW_DOMAIN}:8000|g" "$PROJECT_ROOT/Frontend/.env.local"
log_success "Frontend .env.local updated"
log_info "  NEXT_PUBLIC_BACKEND_URL=https://${NEW_DOMAIN}:8000"

# Step 4: Verify configuration
log_info "Step 4/5: Verifying configuration..."

# Check if environment variables were updated
if grep -q "FRONTEND_URL=https://${NEW_DOMAIN}" "$PROJECT_ROOT/Backend/.env"; then
    log_success "Backend FRONTEND_URL verified"
else
    log_error "Backend FRONTEND_URL update failed"
    exit 1
fi

if grep -q "NEXT_PUBLIC_BACKEND_URL=https://${NEW_DOMAIN}" "$PROJECT_ROOT/Frontend/.env.local"; then
    log_success "Frontend NEXT_PUBLIC_BACKEND_URL verified"
else
    log_error "Frontend NEXT_PUBLIC_BACKEND_URL update failed"
    exit 1
fi

# Step 5: DNS and pre-flight checks
log_info "Step 5/5: Pre-flight checks..."

# Check if domain resolves
if command -v nslookup &> /dev/null; then
    log_info "Checking DNS resolution for ${NEW_DOMAIN}..."
    if nslookup "$NEW_DOMAIN" &> /dev/null; then
        resolved_ip=$(nslookup "$NEW_DOMAIN" 2>/dev/null | grep -oP '(?<=Address: ).*' | head -1)
        log_success "DNS resolves to: $resolved_ip"

        if [ -n "$NEW_IP" ] && [ "$resolved_ip" != "$NEW_IP" ]; then
            log_warn "Resolved IP ($resolved_ip) doesn't match expected IP ($NEW_IP)"
            log_warn "Verify DNS A record is correct"
        fi
    else
        log_warn "DNS resolution failed - may not be propagated yet (normal if just created)"
        log_warn "This will work once DNS propagates (can take 1-24 hours)"
    fi
else
    log_warn "nslookup not available, skipping DNS check"
fi

# Summary
echo ""
log_success "=== Migration Configuration Complete ==="
echo ""
echo "Files updated:"
echo "  ✓ Backend/.env"
echo "  ✓ Frontend/.env.local"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "  1. Verify SSL certificates are installed"
echo "  2. Update Google Cloud Console OAuth redirect URIs:"
echo "     https://${NEW_DOMAIN}:8000/gmail/oauth2callback"
echo "  3. Delete old Gmail token: rm Backend/data/gmail_token.json"
echo "  4. Restart services:"
echo "     - Backend: uvicorn api:app --host 0.0.0.0 --port 8000 --ssl-keyfile=/path/to/cert.key --ssl-certfile=/path/to/cert.pem"
echo "     - Frontend: npm run dev"
echo "  5. Test Gmail OAuth flow (Settings tab → Connect Gmail)"
echo "  6. Verify email sync works"
echo ""
echo "For detailed instructions, see: MIGRATION_TO_STATIC_IP.md"
echo ""

# Ask if user wants to delete old Gmail token
echo -n "Delete old Gmail token now? (y/n): "
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    if [ -f "$PROJECT_ROOT/Backend/data/gmail_token.json" ]; then
        rm "$PROJECT_ROOT/Backend/data/gmail_token.json"
        log_success "Old Gmail token deleted"
        log_info "You'll need to re-authenticate Gmail in the Settings tab"
    fi
else
    log_warn "Skipped deletion of gmail_token.json"
    log_warn "Remember: You should delete it before restarting the app"
fi

echo ""
log_success "Migration script completed successfully!"
