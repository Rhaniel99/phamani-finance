#!/usr/bin/env bash
# Deploy do Phamani no servidor (usado pelo GitHub Actions e também à mão).
#   ./deploy/deploy.sh                 → build + sobe + migra
# Variáveis opcionais:
#   PHAMANI_ENV_FILE  (padrão: /home/pholaroid/apps/phamani/.env.production)
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${PHAMANI_ENV_FILE:-/home/pholaroid/apps/phamani/.env.production}"
export PHAMANI_ENV_FILE="$ENV_FILE"

if [ ! -f "$ENV_FILE" ]; then
  echo "✗ Arquivo de ambiente não encontrado: $ENV_FILE" >&2
  echo "  Copie .env.production.example para lá e preencha." >&2
  exit 1
fi

dc() { docker compose -p phamani -f docker-compose.prod.yml --env-file "$ENV_FILE" "$@"; }

BACKUP_DIR="$(grep -E '^BACKUP_DIR=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')"
mkdir -p "${BACKUP_DIR:-/media/dados/backups/phamani}"

echo "→ Build das imagens"
dc build --pull

echo "→ Banco"
dc up -d postgres
dc up -d --wait postgres

echo "→ Migrations"
dc run --rm --no-deps app php artisan migrate --force --no-interaction

echo "→ Subindo os serviços"
dc up -d --remove-orphans

echo "→ Checando a aplicação"
PORT="$(grep -E '^APP_PORT=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://127.0.0.1:${PORT:-8686}/up"; then
    echo "✓ Phamani no ar"
    docker image prune -f >/dev/null
    exit 0
  fi
  sleep 2
done

echo "✗ A aplicação não respondeu em /up. Logs:" >&2
dc logs --tail=80 app web >&2
exit 1
