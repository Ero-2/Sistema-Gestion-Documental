# ── PHP 8.3 + Apache + PostgreSQL driver ──
# PHP solo conecta a PostgreSQL. Comunicación desacoplada vía API (.NET → PHP).
# Sin driver ODBC / sqlsrv: PHP no conecta a SQL Server.
FROM php:8.3-apache

RUN apt-get update && apt-get install -y \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Extensiones PHP
RUN docker-php-ext-install pdo pdo_pgsql \
    && docker-php-ext-enable pdo_pgsql

RUN a2enmod rewrite

COPY . /var/www/html/

COPY apache.conf /etc/apache2/sites-available/000-default.conf

COPY start.sh /start.sh
RUN sed -i 's/\r$//' /start.sh && chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]
