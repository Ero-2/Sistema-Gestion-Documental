FROM php:8.3-apache

# PHP solo conecta a PostgreSQL. Comunicación desacoplada vía API (.NET → PHP).
# Sin driver ODBC / sqlsrv: PHP no conecta a SQL Server.
RUN apt-get update && apt-get install -y \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install pdo pdo_pgsql \
    && docker-php-ext-enable pdo_pgsql

RUN a2enmod rewrite

COPY . /var/www/html/

CMD ["apache2-foreground"]
