#!/bin/sh
# Gera os caches do Laravel com as variáveis do container e executa o comando (php-fpm, scheduler...).
#
# Não usamos `php artisan optimize` porque ele também roda comandos de pacotes que gravam no
# cache do banco (ex.: data:cache-structures do laravel-data) — e no primeiro deploy as tabelas
# ainda não existem (o migrate roda justamente neste container). Os quatro abaixo não tocam no banco.
set -e

php artisan config:cache --no-interaction >/dev/null
php artisan route:cache --no-interaction >/dev/null
php artisan view:cache --no-interaction >/dev/null
php artisan event:cache --no-interaction >/dev/null

exec "$@"
