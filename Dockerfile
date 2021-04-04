# The different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target

# ---------
# PHP stage
# ---------
# Supported architectures:
# - linux/amd64 (x),
# - linux/arm64 (x),
# - linux/ppc64le (x),
# - linux/s390x (x),
# - linux/386 (x),
# - linux/arm/v7 (x),
# - linux/arm/v6 (x)
FROM alpine:3.13 AS php

# Setup OS
# hadolint ignore=DL3018
RUN set -eux; \
    apk update; \
    apk add --no-cache \
        # Helpers
        bash \
        bash-completion \
        curl \
        ca-certificates \
        # https://github.com/docker-library/php/issues/494
        openssl \
        # Alpine package for "imagemagick" contains ~120 .so files,
        # see: https://github.com/docker-library/wordpress/pull/497
        imagemagick \
        # Required to check connectivity
        mysql-client \
        postgresql-client \
        # Required for healthcheck
        fcgi; \
    \
    # Custom bash config
    { \
        # Enable autocompletion
        echo '. /etc/profile.d/bash_completion.sh'; \
        # <green> user@host <normal> : <blue> dir <normal> $#
        echo 'export PS1="🐳 \e[38;5;10m\u@\h\e[0m:\e[38;5;12m\w\e[0m\\$ "'; \
    } >"$HOME/.bashrc"; \
    \
    # Ensure www-data user exists
    addgroup -g 82 -S www-data; \
    adduser -u 82 -D -S -G www-data www-data
    # 82 is the standard uid/gid for "www-data" in Alpine
    # https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.9-stable
    # https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.9-stable
    # https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.9-stable

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Setup PHP
# hadolint ignore=DL3018
RUN set -eux; \
    apk add --no-cache \
        php8 \
        php8-ctype \
        php8-curl \
        php8-dom \
        php8-fileinfo \
        php8-fpm \
        php8-gd \
        php8-iconv \
        php8-intl \
        php8-json \
        php8-mbstring \
        php8-opcache \
        php8-openssl \
        php8-pdo \
        php8-pdo_mysql \
        php8-pdo_pgsql \
        php8-phar \
        php8-session \
        php8-soap \
        php8-tokenizer \
        php8-xml \
        php8-xmlwriter \
        php8-zip \
        php8-pecl-apcu \
        php8-pecl-imagick; \
    \
    ln -s php8 /usr/bin/php; \
    ln -s php-fpm8 /usr/sbin/php-fpm

ENV PHP_DIR="/etc/php8"

COPY .docker/php/conf/php-development.ini $PHP_DIR/php.ini-development
COPY .docker/php/conf/php-production.ini  $PHP_DIR/php.ini-production
COPY .docker/php/conf/php-fpm.ini         $PHP_DIR/php-fpm.conf
COPY .docker/php/conf/php-fpm.d/www.ini   $PHP_DIR/php-fpm.d/www.conf

RUN set -eux; \
    ln -sf "$PHP_DIR/php.ini-production" "$PHP_DIR/php.ini"

WORKDIR /app

# Setup Composer
# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    PATH="${PATH}:/root/.composer/vendor/bin"
COPY --from=composer /usr/bin/composer /usr/bin/composer

# Prevent the reinstallation of vendors at every changes in the source code
COPY composer.json composer.lock ./
RUN set -eux; \
    composer install --prefer-dist --no-dev --no-scripts --no-progress --optimize-autoloader --no-interaction --no-plugins; \
    composer clear-cache; \
    rm /usr/bin/composer

# Setup application
COPY craft ./
COPY config ./config
COPY modules ./modules
COPY src ./src
COPY storage ./storage
COPY templates ./templates
COPY web ./web
RUN set -eux; \
    # Fix permission
    # Requires write permission on:
    # - .env
    # - composer.json
    # - composer.lock
    # - config/license.key
    # - config/project/*
    # - storage/*
    # - vendor/*
    # - web/cpresources/*
    chown www-data:www-data -R .; \
    find . -type d -exec chmod 755 {} \;; \
    find . -type f -exec chmod 644 {} \;; \
    chmod +x craft

# https://github.com/renatomefi/php-fpm-healthcheck
RUN curl -fsSL -o /usr/local/bin/php-fpm-healthcheck https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck; \
    chmod +x /usr/local/bin/php-fpm-healthcheck
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 CMD php-fpm-healthcheck || exit 1

# Override stop signal to stop process gracefully
# https://github.com/php/php-src/blob/17baa87faddc2550def3ae7314236826bc1b1398/sapi/fpm/php-fpm.8.in#L163
STOPSIGNAL SIGQUIT

EXPOSE 9000

COPY .docker/php/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]

# -----------
# Nginx stage
# -----------
# Depends on the "php" stage above
FROM alpine:3.13 as nginx

# Setup OS
# hadolint ignore=DL3018
RUN set -eux; \
    apk update; \
    apk add --no-cache \
        bash \
        bash-completion \
        curl \
        ca-certificates \
        gettext \
        openssl \
        tzdata; \
    \
    # Custom bash config
    { \
        # Enable autocompletion
        echo '. /etc/profile.d/bash_completion.sh'; \
        # <green> user@host <normal> : <blue> dir <normal> $#
        echo 'export PS1="🐳 \e[38;5;10m\u@\h\e[0m:\e[38;5;12m\w\e[0m\\$ "'; \
    } >"$HOME/.bashrc"

# Setup Nginx
# hadolint ignore=DL3018
RUN set -eux; \
    apk add --no-cache \
        nginx

ENV NGINX_DIR="/etc/nginx"

COPY .docker/nginx/conf/nginx.conf              $NGINX_DIR/nginx.template
COPY .docker/nginx/conf/http.d/default.conf     $NGINX_DIR/http.d/default.template
COPY .docker/nginx/conf/http.d/default-ssl.conf $NGINX_DIR/http.d/default-ssl.template

RUN set -eux; \
    # Forward request and error logs to docker log collector
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    \
    # Remove default config, will be replaced on startup with custom one
    rm $NGINX_DIR/http.d/default.conf; \
    \
    # Fix permission
    adduser -u 82 -D -S -G www-data www-data
    # 82 is the standard uid/gid for "www-data" in Alpine
    # https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.9-stable
    # https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.9-stable
    # https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.9-stable

WORKDIR /app

# Setup application
COPY --from=php /app/web ./web

RUN set -eux; \
    # Empty all php files (to reduce container size). Only the file's existence is important
    find . -type f -name "*.php" -exec sh -c 'i="$1"; >"$i"' _ {} \;; \
    \
    # Fix permission
    chown www-data:www-data -R .; \
    find . -type d -exec chmod 755 {} \;; \
    find . -type f -exec chmod 644 {} \;

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 CMD curl -f http://localhost/ || exit 1

STOPSIGNAL SIGQUIT

EXPOSE 80

COPY .docker/nginx/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]

# -------------
# PHP dev stage
# -------------
FROM php AS php-dev

COPY --from=composer /usr/bin/composer /usr/bin/composer

RUN set -eux; \
    # Install XDebug
    apk add --no-cache \
        php8-pecl-xdebug; \
    \
    # Update php configuration
    ln -sf "$PHP_DIR/php.ini-development" "$PHP_DIR/php.ini"; \
    \
    # Update app with dev libraries
    composer install --prefer-dist --no-scripts --no-progress --optimize-autoloader --no-interaction --no-plugins; \
    composer clear-cache
