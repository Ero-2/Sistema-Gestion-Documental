# ── PHP 8.3-FPM + PostgreSQL driver ──
# PHP solo conecta a PostgreSQL. Comunicación desacoplada vía API (.NET → PHP).
# Sin driver ODBC / sqlsrv. FPM escucha en :9000; Nginx hace fastcgi_pass.
FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install pdo pdo_pgsql \
    && docker-php-ext-enable pdo_pgsql

WORKDIR /var/www/html
COPY . /var/www/html/

# Bootstrap (define DMS_BASE desde X-Forwarded-Prefix) antes de cada request.
RUN echo "auto_prepend_file=/var/www/html/config/bootstrap.php" \
    > /usr/local/etc/php/conf.d/zz-dms.ini

EXPOSE 9000
# CMD heredado de la imagen base: php-fpm
