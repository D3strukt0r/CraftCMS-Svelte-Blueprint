# The different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target

# ---------
# PHP stage
# ---------
# Supported architectures: amd64, arm32v5, arm32v7, arm64v8, i386, mips64le, ppc64le, s390x
FROM debian:10-slim AS base

# Setup OS
RUN set -eux; \
    apt-get update; \
    apt-get dist-upgrade; \
    apt-get -y install \
        # Helpers
        bash-completion \
        # To get the php repository
        apt-transport-https \
        lsb-release \
        ca-certificates \
        curl; \
    # Enable autocompletion
    { \
        "if [ -f /etc/bash_completion ]; then"; \
        "    . /etc/bash_completion"; \
        "fi"; \
    } >> /etc/profile; \

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

 # Setup php
COPY .docker/php/php-development.ini $PHP_INI_DIR/php.ini-development
COPY .docker/php/php-production.ini $PHP_INI_DIR/php.ini-production
RUN set -eux; \
    # Install php repository
    curl -sSL -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg; \
    sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'; \
    apt-get update; \
    # Install php binaries
    apt-get -y install \
        php8.0-apcu \
        php8.0-curl \
        php8.0-fpm \
        php8.0-gd \
        php8.0-imagick \
        php8.0-intl \
        php8.0-mbstring \
        php8.0-mysql \
        php8.0-opcache \
        php8.0-pgsql \
        php8.0-xml \
        php8.0-zip; \
    # Clean
	rm -rf /var/lib/apt/lists/*; \
   \
   # Set default php configuration
   rm "$PHP_INI_DIR/php.ini"; \
   ln -s "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
   \
   # Setup fpm
   sed -i 's/user = nobody/user = www-data/g' "$PHP_INI_DIR/php-fpm.d/www.conf"; \
   sed -i 's/group = nobody/group = www-data/g' "$PHP_INI_DIR/php-fpm.d/www.conf"; \
   { \
       echo '[global]'; \
       echo 'error_log = /proc/self/fd/2'; \
       echo; \
       echo '; https://github.com/docker-library/php/pull/725#issuecomment-443540114'; \
       echo 'log_limit = 8192'; \
       echo; \
       echo '[www]'; \
       echo '; if we send this to /proc/self/fd/1, it never appears'; \
       echo 'access.log = /proc/self/fd/2'; \
       echo; \
       echo 'clear_env = no'; \
       echo; \
       echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
       echo 'catch_workers_output = yes'; \
       echo 'decorate_workers_output = no'; \
   } | tee $PHP_INI_DIR/php-fpm.d/docker.conf; \
   { \
       echo '[global]'; \
       echo 'daemonize = no'; \
       echo; \
       echo '[www]'; \
       echo 'listen = 9000'; \
   } | tee $PHP_INI_DIR/php-fpm.d/zz-docker.conf; \
   \
   # Install composer
   curl -fsSL -o composer-setup.php https://getcomposer.org/installer; \
   EXPECTED_CHECKSUM="$(curl -fsSL https://composer.github.io/installer.sig)"; \
   ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"; \
   \
   if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then \
       >&2 echo 'ERROR: Invalid installer checksum'; \
       rm composer-setup.php; \
       exit 1; \
   fi; \
   \
   php composer-setup.php --quiet; \
   rm composer-setup.php; \
   mv composer.phar /usr/bin/composer

ENV PHP_INI_DIR /etc/php/8.0/fpm

WORKDIR /app

EXPOSE 9000

# Override stop signal to stop process gracefully
STOPSIGNAL SIGQUIT

ENTRYPOINT ["entrypoint"]
CMD ["php-fpm8.0"]
