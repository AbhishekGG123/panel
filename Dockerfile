
# Stage 0: Build frontend assets and Composer dependencies
# This stage is discarded from the final production image.
FROM --platform=$BUILDPLATFORM node:22-alpine

WORKDIR /app

COPY . ./

COPY --from=composer@sha256:d8f6343d3fae98107426bc49163ccad46ef85aabd4a27d80a74401fab4aba332 \
    /usr/bin/composer /usr/local/bin/composer

RUN apk add --no-cache \
    php \
    php-phar \
    php-json \
    php-mbstring \
    php-openssl \
    php-tokenizer \
    php-xml \
    php-fileinfo \
    php-curl \
    php-dom \
    php-ctype \
    && composer install \
        --no-dev \
        --optimize-autoloader \
        --no-scripts \
        --ignore-platform-reqs

RUN npm install -g pnpm \
    && pnpm install --frozen-lockfile \
    && pnpm run build


# Stage 1: Production application container
FROM --platform=$TARGETOS/$TARGETARCH php:8.3-fpm-alpine

ENV PANEL_INSTALLATION_TYPE=docker

WORKDIR /app

COPY . ./

COPY --from=0 /app/public/assets ./public/assets

COPY --from=composer@sha256:d8f6343d3fae98107426bc49163ccad46ef85aabd4a27d80a74401fab4aba332 \
    /usr/bin/composer /usr/local/bin/composer

# System dependencies, including PostgreSQL development libraries
RUN apk add --no-cache --update \
    ca-certificates \
    dcron \
    curl \
    git \
    supervisor \
    tar \
    unzip \
    nginx \
    libpng-dev \
    libxml2-dev \
    libzip-dev \
    certbot \
    certbot-nginx \
    freetype-dev \
    libjpeg-turbo-dev \
    icu-dev \
    mysql-client \
    postgresql-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure zip \
    && docker-php-ext-install \
        bcmath \
        gd \
        intl \
        pdo_mysql \
        pdo_pgsql \
        zip \
    && cp .env.example .env \
    && mkdir -p \
        bootstrap/cache/ \
        storage/logs \
        storage/framework/sessions \
        storage/framework/views \
        storage/framework/cache \
    && chmod 777 -R bootstrap storage \
    && composer install \
        --no-dev \
        --optimize-autoloader \
    && rm -rf .env bootstrap/cache/*.php \
    && mkdir -p /app/storage/logs/ \
    && chown -R nginx:nginx .


# Configure cron, PHP-FPM and Nginx
RUN rm /usr/local/etc/php-fpm.conf \
    && echo "* * * * * /usr/local/bin/php /app/artisan schedule:run >> /dev/null 2>&1" >> /var/spool/cron/crontabs/root \
    && echo "0 23 * * * certbot renew --nginx --quiet" >> /var/spool/cron/crontabs/root \
    && sed -i 's/ssl_session_cache/#ssl_session_cache/g' /etc/nginx/nginx.conf \
    && mkdir -p /var/run/php /var/run/nginx

# Copy application server configuration
COPY .github/docker/default.conf /etc/nginx/http.d/default.conf

COPY .github/docker/www.conf /usr/local/etc/php-fpm.conf

COPY .github/docker/supervisord.conf /etc/supervisord.conf

# Northflank should expose port 80 and manage external HTTPS
EXPOSE 80 443

ENTRYPOINT ["/bin/ash", ".github/docker/entrypoint.sh"]

CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]
