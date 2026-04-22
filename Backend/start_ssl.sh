#!/bin/bash
cd /opt/ieor-email-advising/Backend
source venv/bin/activate
sudo ./venv/bin/uvicorn api:app \
  --host 0.0.0.0 \
  --port 8000 \
  --ssl-keyfile=/etc/letsencrypt/live/advising.ieor.columbia.edu/privkey.pem \
  --ssl-certfile=/etc/letsencrypt/live/advising.ieor.columbia.edu/fullchain.pem
