# The different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target

ARG USER_ID
ARG GROUP_ID

# -----------------------------------------------------------------------------
# Base OS
# -----------------------------------------------------------------------------
# Supported architectures:
# - linux/amd64,
# - linux/arm64,
# - linux/ppc64le,
# - linux/s390x,
# - linux/386,
# - linux/arm/v7,
# - linux/arm/v6
FROM alpine:3.13 AS base

LABEL maintainer="Manuele Vaccari <manuele.vaccari@gmail.com>"

ARG USER_ID
ARG GROUP_ID

# hadolint ignore=DL3018
RUN set -o errexit -o nounset -o xtrace; \
    apk update; \
    apk upgrade; \
    apk add --no-cache \
        # Bash
        bash bash-completion \
        # Shell utilities
        util-linux coreutils findutils grep \
        # /etc/{shadow,group} manipulation requires
        shadow \
        # Other
        curl \
        nano \
        # SSL
        ca-certificates \
        # https://github.com/docker-library/php/issues/494
        openssl

RUN set -o errexit -o nounset -o xtrace; \
    # Custom bash config
    rm /etc/profile.d/color_prompt; \
    echo '. /etc/profile' >"$HOME/.bashrc"; \
    \
    # Fix no www folder
    mkdir --parents /var/www; \
    \
    # Fix mismatched host-container user id
    if [ ${USER_ID:=82} -ne 0 ] && [ ${GROUP_ID:=82} -ne 0 ]; then \
        # 82 is the standard uid/gid for "www-data" in Alpine
        # https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.9-stable
        # https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.9-stable
        # https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.9-stable
        groupadd --gid ${GROUP_ID} --system www-data; \
        useradd --uid ${USER_ID} --shell /bin/bash --password '*' --create-home --system --gid www-data www-data; \
        echo '. /etc/profile' >/home/www-data/.bashrc; \
    else \
        echo 'Set USER_ID and GROUP_ID to something else than root (0)'; \
        exit 1; \
    fi; \
    chown --changes --silent --no-dereference --recursive ${USER_ID}:${GROUP_ID} \
        /var/www

COPY .docker/os/color_prompt.sh /etc/profile.d/color_prompt.sh

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# PHP base
# -----------------------------------------------------------------------------
FROM base AS base-php

ENV PHP_DIR="/etc/php8"

# hadolint ignore=DL3018
RUN set -o errexit -o nounset -o xtrace; \
    apk update; \
    apk add --no-cache \
        # Alpine package for "imagemagick" contains ~120 .so files,
        # see: https://github.com/docker-library/wordpress/pull/497
        imagemagick \
        # Required to check connectivity
        mysql-client \
        postgresql-client \
        # Required for healthcheck
        fcgi \
        # PHP
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
        php8-pecl-imagick

RUN set -o errexit -o nounset -o xtrace; \
    # Fix missing default binaries
    ln --symbolic php8 /usr/bin/php; \
    ln --symbolic php-fpm8 /usr/sbin/php-fpm; \
    \
    # Link to production by default
    ln --symbolic --force "$PHP_DIR/php.ini-production" "$PHP_DIR/php.ini"

COPY .docker/php/conf/php-development.ini $PHP_DIR/php.ini-development
COPY .docker/php/conf/php-production.ini  $PHP_DIR/php.ini-production
COPY .docker/php/conf/php-fpm.ini         $PHP_DIR/php-fpm.conf
COPY .docker/php/conf/php-fpm.d/www.ini   $PHP_DIR/php-fpm.d/www.conf

WORKDIR /var/www

# Override stop signal to stop process gracefully
# https://github.com/php/php-src/blob/17baa87faddc2550def3ae7314236826bc1b1398/sapi/fpm/php-fpm.8.in#L163
STOPSIGNAL SIGQUIT

EXPOSE 9000

# https://github.com/renatomefi/php-fpm-healthcheck
RUN set -o errexit -o nounset -o xtrace; \
    curl --fail --silent --show-error --location \
        --output /usr/bin/php-fpm-healthcheck \
        https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck; \
    chmod +x /usr/bin/php-fpm-healthcheck
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 CMD php-fpm-healthcheck || exit 1

COPY .docker/php/docker-entrypoint.sh /usr/bin/docker-entrypoint
RUN set -o errexit -o nounset -o xtrace; \
    chmod +x /usr/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]

# -----------------------------------------------------------------------------
# Nginx base
# -----------------------------------------------------------------------------
FROM base AS base-nginx

ENV NGINX_DIR="/etc/nginx"

# hadolint ignore=DL3018
RUN set -o errexit -o nounset -o xtrace; \
    apk update; \
    apk add --no-cache \
        gettext \
        tzdata \
        # Nginx
        nginx

RUN set -o errexit -o nounset -o xtrace; \
    # Fix www folder already has content
    rm --recursive /var/www/*; \
    \
    # Forward request and error logs to docker log collector
    ln --symbolic --force /dev/stdout /var/log/nginx/access.log; \
    ln --symbolic --force /dev/stderr /var/log/nginx/error.log; \
    \
    # Remove default config, will be replaced on startup with custom one
    rm $NGINX_DIR/nginx.conf; \
    rm $NGINX_DIR/http.d/default.conf

COPY .docker/nginx/conf/nginx.conf              $NGINX_DIR/nginx.template
COPY .docker/nginx/conf/http.d/default.conf     $NGINX_DIR/http.d/default.template
COPY .docker/nginx/conf/http.d/default-ssl.conf $NGINX_DIR/http.d/default-ssl.template

WORKDIR /var/www

STOPSIGNAL SIGQUIT

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 CMD curl --fail http://127.0.0.1/ || exit 1

COPY .docker/nginx/docker-entrypoint.sh /usr/bin/docker-entrypoint
RUN set -o errexit -o nounset -o xtrace; \
    chmod +x /usr/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]

# -----------------------------------------------------------------------------
# Install vendors
# -----------------------------------------------------------------------------
FROM base-php AS app-php-vendor

COPY --from=composer /usr/bin/composer /usr/bin/composer

# Prevent the reinstallation of vendors at every changes in the source code
COPY --chown=www-data:www-data composer.json composer.lock ./
RUN set -o errexit -o nounset -o xtrace; \
    su --command 'composer install --prefer-dist --no-dev --no-scripts --no-progress --optimize-autoloader --no-interaction --no-plugins' www-data

# -----------------------------------------------------------------------------
# App (PHP environment)
# -----------------------------------------------------------------------------
FROM base-php AS app-php

COPY --chown=www-data:www-data craft ./
COPY --chown=www-data:www-data config ./config
COPY --chown=www-data:www-data modules ./modules
COPY --chown=www-data:www-data src ./src
COPY --chown=www-data:www-data storage ./storage
COPY --chown=www-data:www-data templates ./templates
COPY --chown=www-data:www-data web ./web
COPY --from=app-php-vendor --chown=www-data:www-data /var/www/vendor ./vendor

RUN set -o errexit -o nounset -o xtrace; \
    chown www-data:www-data --recursive .; \
    find . -type d -exec chmod u=rwx,g=rx,o=rx {} \;; \
    find . -type f -exec chmod u=rw,g=r,o=r {} \;; \
    chmod +x craft

# -----------------------------------------------------------------------------
# App (Nginx environment)
# -----------------------------------------------------------------------------
FROM base-nginx AS app-nginx

COPY --from=app-php --chown=www-data:www-data /var/www/web ./web

RUN set -o errexit -o nounset -o xtrace; \
    # Empty all php files (to reduce container size). Only the file's existence is important
    find . -type f -name "*.php" -exec sh -c 'i="$1"; >"$i"' _ {} \;; \
    \
    # Fix permission
    chown www-data:www-data --recursive .; \
    find . -type d -exec chmod u=rwx,g=rx,o=rx {} \;; \
    find . -type f -exec chmod u=rw,g=r,o=r {} \;

# -----------------------------------------------------------------------------
# App (PHP Dev environment)
# -----------------------------------------------------------------------------
FROM app-php AS app-php-dev

ENV PATH="${PATH}:/home/www-data/.composer/vendor/bin"
COPY --from=composer /usr/bin/composer /usr/bin/composer

COPY --from=app-php-vendor --chown=www-data:www-data /var/www/composer.json /var/www/composer.lock ./

RUN set -o errexit -o nounset -o xtrace; \
    # Install XDebug
    apk add --no-cache \
        php8-pecl-xdebug

RUN set -o errexit -o nounset -o xtrace; \
    sed 's/;zend_extension=xdebug.so/zend_extension = xdebug.so/' -i "$PHP_DIR/conf.d/50_xdebug.ini"; \
    sed 's/;xdebug.mode=off/xdebug.mode = develop,debug/' -i "$PHP_DIR/conf.d/50_xdebug.ini"; \
    { \
        echo 'xdebug.start_with_request = yes'; \
        echo 'xdebug.log = /var/www/storage/logs/xdebug.log'; \
        \
        echo 'xdebug.client_host = host.docker.internal'; \
        # the port (9003 by default) to which Xdebug connects
        echo 'xdebug.client_port = 9003'; \
    } >>"$PHP_DIR/conf.d/50_xdebug.ini"; \
    \
    # Update php configuration
    ln --symbolic --force "$PHP_DIR/php.ini-development" "$PHP_DIR/php.ini"

RUN set -o errexit -o nounset -o xtrace; \
    # Update app with dev libraries
    su --command 'composer install --prefer-dist --no-scripts --no-progress --optimize-autoloader --no-interaction --no-plugins' www-data

EXPOSE 9003
