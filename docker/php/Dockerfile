# Imagem única de desenvolvimento: PHP-FPM 8.4 + Composer + Node 24
# (o Node fica junto porque o plugin do Wayfinder roda `php artisan wayfinder:generate` durante o Vite)

FROM php:8.4-fpm-alpine AS builder

RUN apk add --no-cache $PHPIZE_DEPS postgresql-dev libzip-dev icu-dev linux-headers \
        libpng-dev libjpeg-turbo-dev libwebp-dev \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" pdo_pgsql bcmath intl zip pcntl opcache gd

FROM node:24-alpine AS node

FROM php:8.4-fpm-alpine

ARG UID=1000
ARG GID=1000
ARG USER=laravel

# Extensões compiladas no estágio anterior
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Node 24 + npm
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Bibliotecas de runtime
RUN apk add --no-cache libzip icu-libs postgresql-libs libstdc++ git unzip libpng libjpeg-turbo libwebp \
    tesseract-ocr tesseract-ocr-data-eng poppler-utils

# Usuário com o mesmo UID/GID do host (evita arquivos com dono root no volume)
RUN addgroup -g ${GID} -S ${USER} \
    && adduser -u ${UID} -G ${USER} -S -s /bin/sh ${USER} \
    && sed -i "s/user = www-data/user = ${USER}/g" /usr/local/etc/php-fpm.d/www.conf \
    && sed -i "s/group = www-data/group = ${USER}/g" /usr/local/etc/php-fpm.d/www.conf

COPY custom.ini /usr/local/etc/php/conf.d/zz-custom.ini

WORKDIR /var/www/html
USER ${USER}

EXPOSE 9000 5173
CMD ["php-fpm"]
