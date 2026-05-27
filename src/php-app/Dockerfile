# ── PHP 8.3 + Apache + SQL Server + PostgreSQL drivers ──
FROM php:8.3-apache

RUN apt-get update && apt-get install -y \
    curl gnupg2 apt-transport-https \
    libpq-dev unixodbc-dev cron \
    && rm -rf /var/lib/apt/lists/*

# Microsoft ODBC Driver 17 (modern keyring, no apt-key)
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
       > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql17 \
    && rm -rf /var/lib/apt/lists/*

# Extensiones PHP
RUN pecl install sqlsrv pdo_sqlsrv \
    && docker-php-ext-install pdo pdo_pgsql \
    && docker-php-ext-enable sqlsrv pdo_sqlsrv pdo_pgsql

RUN a2enmod rewrite

# Crontab — sync incremental cada 5 minutos
COPY crontab /etc/cron.d/dms-sync
RUN chmod 0644 /etc/cron.d/dms-sync && crontab /etc/cron.d/dms-sync

COPY . /var/www/html/

COPY apache.conf /etc/apache2/sites-available/000-default.conf

COPY start.sh /start.sh
RUN sed -i 's/\r$//' /start.sh && chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]
