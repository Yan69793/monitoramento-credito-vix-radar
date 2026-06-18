#!/bin/sh
# health_vix.sh — Health check padrão VIX Radar (execução na Sprite VM)
# Uso: sh /home/sprite/health_vix.sh
# Repo: scripts/sprite/health_vix.sh

URL="https://radar-credito-api.prospects-intel.workers.dev"
BODY="/home/sprite/.health_vix_body.json"

/usr/bin/curl -s "$URL" -o "$BODY" -w "HTTP:%{http_code} TEMPO:%{time_total}s\n"
cat "$BODY"
echo ""