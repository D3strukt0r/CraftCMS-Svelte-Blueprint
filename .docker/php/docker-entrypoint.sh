#!/bin/bash

set -o errexit -o nounset -o pipefail

# If command starts with an option (`-f` or `--some-option`), prepend main command
if [ "${1#-}" != "$1" ]; then
    set -- php-fpm "$@"
fi

# Logging functions
entrypoint_log() {
    local type="$1"
    shift
    printf '%s [%s] [Entrypoint]: %s\n' "$(date '+%Y-%m-%d %T %z')" "$type" "$*"
}
entrypoint_note() {
    entrypoint_log Note "$@"
}
entrypoint_warn() {
    entrypoint_log Warn "$@" >&2
}
entrypoint_error() {
    entrypoint_log ERROR "$@" >&2
    exit 1
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
#
# Will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
# "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature
# Read more: https://docs.docker.com/engine/swarm/secrets/
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [[ "${!var:-}" ]] && [ "${!fileVar:-}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [[ "${!var:-}" ]]; then
        val="${!var}"
    elif [[ "${!fileVar:-}" ]]; then
        val="$(<"${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

# Setup environment variables
manualEnvs=(
    APP_ID
    SECURITY_KEY
)
envs=(
    PHP_MAX_EXECUTION_TIME
    PHP_MEMORY_LIMIT
    PHP_POST_MAX_SIZE
    PHP_UPLOAD_MAX_FILESIZE
    "${manualEnvs[@]}"
    ENVIRONMENT
    DB_DRIVER
    DB_SERVER
    DB_PORT
    DB_USER
    DB_PASSWORD
    DB_DATABASE
    DB_SCHEMA
    DB_TABLE_PREFIX
    ASSETS_URL
    SITE_URL
    WEB_ROOT_PATH
    LICENSE_KEY
    PLUGIN_BLITZ_LICENSE
    PLUGIN_COMMERCE_LICENSE
    PLUGIN_FREEFORM_LICENSE
    PLUGIN_NAVIGATION_LICENSE
    PLUGIN_RETOUR_LICENSE
    PLUGIN_SEOMATIC_LICENSE
    PLUGIN_TRANSLATIONS_ADMIN_LICENSE
    REDIS_HOSTNAME
    REDIS_PORT
    REDIS_PASSWORD
    REDIS_DEFAULT_DB
    REDIS_CRAFT_DB
    GA_TRACKING_ID
)

# Set empty environment variable or get content from "/run/secrets/<something>"
for e in "${envs[@]}"; do
    file_env "$e"
done

# Set default environment variable values
: "${PHP_MAX_EXECUTION_TIME:=120}"
# 'memory_limit' has to be larger than 'post_max_size' and 'upload_max_filesize'
: "${PHP_MEMORY_LIMIT:=256M}"
# Important for upload limit. 'post_max_size' has to be larger than 'upload_max_filesize'
: "${PHP_POST_MAX_SIZE:=100M}"
: "${PHP_UPLOAD_MAX_FILESIZE:=100M}"

# CraftCMS settings
# The application ID used to to uniquely store session and cache data, mutex locks, and more
: "${APP_ID:=}"
# The environment Craft is currently running in (dev, staging, prod, etc.)
: "${ENVIRONMENT:=prod}"
# The secure key Craft will use for hashing and encrypting data
: "${SECURITY_KEY:=}"

# Database settings
# The database driver that will be used (mysql or pgsql)
: "${DB_DRIVER:=mysql}"
# The database server name or IP address
: "${DB_SERVER:=db}"
# The port to connect to the database with
if [[ -z "$DB_PORT" ]]; then
    if [[ "$DB_DRIVER" = "mysql" ]]; then
        : "${DB_PORT:=3306}"
    elif [[ "$DB_DRIVER" = "pgsql" ]]; then
        : "${DB_PORT:=5432}"
    else
        : "${DB_PORT:=}"
    fi
fi
# The database username to connect with
: "${DB_USER:=root}"
# The database password to connect with
: "${DB_PASSWORD:=}"
# The name of the database to select
: "${DB_DATABASE:=craft}"
# The database schema that will be used (PostgreSQL only)
: "${DB_SCHEMA:=public}"
# The prefix that should be added to generated table names (only necessary if multiple
# things are sharing the same database)
: "${DB_TABLE_PREFIX:=}"

# URL & path settings
: "${ASSETS_URL:=http://localhost/assets}"
: "${SITE_URL:=http://localhost}"
: "${WEB_ROOT_PATH:=/var/www/web}"

# Craft & Plugin Licenses
: "${LICENSE_KEY:=}"
: "${LICENSE_KEY_BLITZ:=}"
: "${LICENSE_KEY_COMMERCE:=}"
: "${LICENSE_KEY_NAVIGATION:=}"
: "${LICENSE_KEY_RETOUR:=}"
: "${LICENSE_KEY_SEOMATIC:=}"
: "${LICENSE_KEY_TRANSLATIONS_ADMIN:=}"

# Redis settings
: "${REDIS_HOSTNAME:=redis}"
: "${REDIS_PORT:=6379}"
: "${REDIS_PASSWORD:=}"
: "${REDIS_DEFAULT_DB:=0}"
: "${REDIS_CRAFT_DB:=3}"

# Google Analytics settings
: "${GA_TRACKING_ID:=}"

# Setup php
if [[ "$1" = 'php-fpm' ]] || [[ "$1" = 'php' ]]; then
    entrypoint_note 'Entrypoint script for CraftCMS started'

    # ----------------------------------------

    entrypoint_note 'Load various environment variables'

    missing_manual_settings=
    for e in "${manualEnvs[@]}"; do
        if [ -z "${!e}" ]; then
            missing_manual_settings=1
            case $e in
            APP_ID)
                : "${!e:=CraftCMS}"
                entrypoint_warn "$e=${!e}"
                ;;
            SECURITY_KEY)
                ;;
            *)
                ;;
            esac
        fi
    done
    if [[ "$missing_manual_settings" = 1 ]]; then
        entrypoint_warn "You haven't set all the important values. Above you can copy-paste the generated ones, but make sure to use them."
    fi
    unset missing_manual_settings

    # ----------------------------------------

    entrypoint_note 'Load/Create optimized PHP configs'
    PHP_INI_RECOMMENDED="$PHP_DIR/php.ini-production"
    if [[ "$ENVIRONMENT" != 'prod' ]]; then
        PHP_INI_RECOMMENDED="$PHP_DIR/php.ini-development"
    fi
    ln --symbolic --force "$PHP_INI_RECOMMENDED" "$PHP_DIR/php.ini"

    sed "s/max_execution_time = 30/max_execution_time = $PHP_MAX_EXECUTION_TIME/" -i "$PHP_DIR/php.ini"

    sed "s/memory_limit = 128M/memory_limit = $PHP_MEMORY_LIMIT/" -i "$PHP_DIR/php.ini"
    sed "s/post_max_size = 8M/post_max_size = $PHP_POST_MAX_SIZE/" -i "$PHP_DIR/php.ini"
    sed "s/upload_max_filesize = 2M/upload_max_filesize = $PHP_UPLOAD_MAX_FILESIZE/" -i "$PHP_DIR/php.ini"

    sed "s/;opcache.max_accelerated_files=10000/opcache.max_accelerated_files = $(find /var/www -type f -print | grep -c php)/" -i "$PHP_DIR/php.ini"

    # ----------------------------------------

    if [[ "$ENVIRONMENT" != 'prod' ]] && [[ -f /certs/localCA.crt ]]; then
        entrypoint_note 'Update CA certificates.'
        ln --symbolic --force /certs/localCA.crt /usr/local/share/ca-certificates/localCA.crt
        update-ca-certificates
    fi

    # ----------------------------------------

    if [[ -f $PHP_DIR/conf.d/50_xdebug.ini ]]; then
        entrypoint_note 'Preparing XDebug ...'
        su --command 'mkdir -p storage/logs && touch storage/logs/xdebug.log' www-data
    fi

    # ----------------------------------------

    if [[ "$ENVIRONMENT" != 'prod' ]] && [[ "$(command -v composer)" ]] && [[ -f composer.json ]]; then
        entrypoint_note 'Installing libraries according to non-production environment ...'
        su --command 'composer install --prefer-dist --no-scripts --no-progress --optimize-autoloader --no-interaction --no-plugins' www-data
    fi

    # ----------------------------------------

    entrypoint_note 'Waiting for db to be ready'

    ATTEMPTS_LEFT_TO_REACH_DATABASE=60
    if [ "$DB_DRIVER" = "mysql" ]; then
        until [[ $ATTEMPTS_LEFT_TO_REACH_DATABASE = 0 ]] || mysql --host="$DB_SERVER" --port="$DB_PORT" --user="$DB_USER" --password="$DB_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; do
            sleep 1
            ATTEMPTS_LEFT_TO_REACH_DATABASE=$((ATTEMPTS_LEFT_TO_REACH_DATABASE - 1))
            entrypoint_warn "Still waiting for db to be ready... Or maybe the db is not reachable. $ATTEMPTS_LEFT_TO_REACH_DATABASE attempts left"
        done
    elif [ "$DB_DRIVER" = "pgsql" ]; then
        until [[ $ATTEMPTS_LEFT_TO_REACH_DATABASE = 0 ]] || pg_isready --host="$DB_SERVER" --port="$DB_PORT" --username="$DB_USER" --dbname="$DB_DATABASE" >/dev/null 2>&1; do
            sleep 1
            ATTEMPTS_LEFT_TO_REACH_DATABASE=$((ATTEMPTS_LEFT_TO_REACH_DATABASE - 1))
            entrypoint_warn "Still waiting for db to be ready... Or maybe the db is not reachable. $ATTEMPTS_LEFT_TO_REACH_DATABASE attempts left"
        done
    else
        entrypoint_error 'Database not supported! Use either MySQL or PostgreSQL'
    fi

    if [[ $ATTEMPTS_LEFT_TO_REACH_DATABASE = 0 ]]; then
        entrypoint_error 'The db is not up or not reachable'
    else
        entrypoint_note 'The db is now ready and reachable'
    fi

    # TODO: Check if required folders are writeable by www-data
    # Requires write permission on:
    # - .env
    # - composer.json
    # - composer.lock
    # - config/license.key
    # - config/project/*
    # - storage/*
    # - vendor/*
    # - web/cpresources/*
fi

exec "$@"
