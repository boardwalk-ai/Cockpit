#!/usr/bin/env bash
# Builds and (re)starts the formula reader on 127.0.0.1:8096.
set -euo pipefail
cd "$(dirname "$0")"
docker build -t octonotes-formula .
docker rm -f octonotes-formula 2>/dev/null || true
docker run -d --name octonotes-formula --restart unless-stopped --memory 2g --cpus 2 -p 127.0.0.1:8096:8000 octonotes-formula
for i in $(seq 1 60); do
  if curl -fsS 127.0.0.1:8096/health >/dev/null; then echo "formula ready"; exit 0; fi
  sleep 2
done
echo "formula NOT READY"; docker logs --tail 50 octonotes-formula; exit 1
