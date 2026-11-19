#!/bin/sh
# Gera os caches do Laravel (config, rotas, views, eventos) com as variáveis do container
# e então executa o comando (php-fpm ou o scheduler).
set -e

php artisan optimize --no-interaction >/dev/null

exec "$@"
