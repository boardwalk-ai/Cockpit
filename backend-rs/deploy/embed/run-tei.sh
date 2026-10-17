#!/usr/bin/env bash
# The bge-m3 embedder for study-api: Hugging Face text-embeddings-inference
# (Rust, ONNX on CPU) on 127.0.0.1:8093, replacing the Python cockpit-embed.
# Vectors match the Python service exactly (cosine 1.00000 on all stored
# passages, compare_tei.py), so nothing needs re-embedding.
#
# Limits keep it from hurting the box: 6 GB / 3 CPUs. Inputs are capped at
# 2048 tokens (the model allows 8192, whose warm-up alone took 10.7 GB and
# was OOM-killed); the longest stored passage is 1,511 tokens, new ones ~400.
# The cap lives in the model copy's sentence_bert_config.json (max_seq_length),
# which TEI reads. Run as root; safe to run again.
set -euo pipefail
DATA=/opt/tei/data
IMAGE=ghcr.io/huggingface/text-embeddings-inference:cpu-1.9
mkdir -p "$DATA"
[ -d "$DATA/models--BAAI--bge-m3" ] || cp -r /var/lib/docker/volumes/cockpit-backend_hf-cache/_data/hub/models--BAAI--bge-m3 "$DATA/"
SNAP=$(ls -d "$DATA"/models--BAAI--bge-m3/snapshots/*/ | head -1)
CFG="$SNAP/sentence_bert_config.json"
[ -L "$CFG" ] && cp --remove-destination "$(readlink -f "$CFG")" "$CFG"
python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["max_seq_length"] = 2048; json.dump(d, open(p, "w"))
PY
docker rm -f study-embed >/dev/null 2>&1 || true
docker run -d --name study-embed --restart=unless-stopped --memory=6g --memory-swap=6g --cpus=3 \
  -p 127.0.0.1:8093:80 -v "$DATA":/data -e HF_HUB_OFFLINE=1 "$IMAGE" \
  --model-id BAAI/bge-m3 --auto-truncate --max-batch-tokens 8192 --max-client-batch-size 64 >/dev/null
for i in $(seq 1 60); do curl -fsS -o /dev/null 127.0.0.1:8093/health 2>/dev/null && { echo "study-embed ready"; exit 0; }; sleep 5; done
echo "study-embed NOT ready"; docker logs study-embed 2>&1 | tail -20; exit 1
