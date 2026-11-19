#!/usr/bin/env bash
# Restaura um backup do banco do Phamani.
#   ./deploy/restore-backup.sh                       → lista os backups
#   ./deploy/restore-backup.sh phamani-2026-11-18_0300.sql.gz
#
# ATENÇÃO: apaga o banco atual e recria a partir do arquivo.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${PHAMANI_ENV_FILE:-/home/pholaroid/apps/phamani/.env.production}"
export PHAMANI_ENV_FILE="$ENV_FILE"
dc() { docker compose -p phamani -f docker-compose.prod.yml --env-file "$ENV_FILE" "$@"; }

get() { grep -E "^$1=" "$ENV_FILE" | cut -d= -f2- | tr -d '"'; }
BACKUP_DIR="$(get BACKUP_DIR)"; BACKUP_DIR="${BACKUP_DIR:-/media/dados/backups/phamani}"
DB="$(get DB_DATABASE)"; DB="${DB:-phamani}"
USER_DB="$(get DB_USERNAME)"; USER_DB="${USER_DB:-phamani}"

if [ $# -lt 1 ]; then
  echo "Backups em $BACKUP_DIR:"
  ls -1t "$BACKUP_DIR"/phamani-*.sql.gz 2>/dev/null | head -20 | xargs -n1 basename
  echo; echo "Uso: $0 <arquivo.sql.gz>"
  exit 0
fi

FILE="$1"; [ -f "$FILE" ] || FILE="$BACKUP_DIR/$1"
[ -f "$FILE" ] || { echo "✗ Arquivo não encontrado: $1" >&2; exit 1; }

read -r -p "Isso SUBSTITUI o banco atual por $(basename "$FILE"). Digite 'restaurar' para continuar: " ok
[ "$ok" = "restaurar" ] || { echo "Cancelado."; exit 1; }

echo "→ Parando app e scheduler"
dc stop app scheduler web

echo "→ Recriando o banco"
dc exec -T postgres psql -U "$USER_DB" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE);" \
  -c "CREATE DATABASE \"$DB\" OWNER \"$USER_DB\";"

echo "→ Importando"
gunzip -c "$FILE" | dc exec -T postgres psql -U "$USER_DB" -d "$DB" -v ON_ERROR_STOP=1 -q

echo "→ Subindo de novo"
dc up -d
echo "✓ Restaurado de $(basename "$FILE")"
