#!/bin/bash
# Saves a copy of the 1stalbum canvas to ~/Documents/1stalbum backups/ (one folder per run).
# Public copy: every name and painting on the canvas.
# Full copy (hidden marks + the signer list): only if your owner key is saved in ~/.1stalbum-owner-key
set -euo pipefail
URL="https://ggkfxynpjounkruwnlse.supabase.co"
KEY="sb_publishable_rn4Jpr_0aCQHAX7_dUQbnQ_R7-RYZiW"          # public key, same as the website's
DEST="${BACKUP_DIR:-$HOME/Documents/1stalbum backups}"
STAMP=$(TZ=America/New_York date "+%Y-%m-%d-%H%M")
OUT="$DEST/$STAMP"
mkdir -p "$OUT"
get() { curl -fsS -m 60 "$URL/rest/v1/$1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -o "$OUT/$2"; }
get "signatures?select=*&order=created_at.asc" signatures.json
get "drawings?select=*&order=created_at.asc" drawings.json
if [ -s "$HOME/.1stalbum-owner-key" ]; then
  OWNER=$(tr -d '[:space:]' < "$HOME/.1stalbum-owner-key")
  curl -fsS -m 60 -X POST "$URL/rest/v1/rpc/export_all" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
       -H 'Content-Type: application/json' -d "{\"p_key\":\"$OWNER\"}" -o "$OUT/everything-private.json"
  chmod 600 "$OUT/everything-private.json"
fi
echo "$(date '+%Y-%m-%d %H:%M') saved $(ls "$OUT" | tr '\n' ' ')-> $OUT"
