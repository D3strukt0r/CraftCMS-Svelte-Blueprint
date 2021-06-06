#!/bin/bash

set -o errexit -o nounset -o pipefail

# -----------------------------------------------------------------------------

# If command starts with an option (`-f` or `--some-option`), prepend main command
if [[ "${1#-}" != "$1" ]]; then
    set -- node "$@"
fi

# -----------------------------------------------------------------------------

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

# Usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
#
# Will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
# "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature
# Read more: https://docs.docker.com/engine/swarm/secrets/
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [[ "${!var:-}" && "${!fileVar:-}" ]]; then
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

# -----------------------------------------------------------------------------

# Setup environment variables
entrypoint_note 'Load various environment variables'
envs=(
    GROUP_ID
    USER_ID
)

# Set empty environment variable or get content from "/run/secrets/<something>"
for e in "${envs[@]}"; do
    file_env "$e"
done

# Fix mismatched host-container user id
: "${USER_ID:=}"
: "${GROUP_ID:=}"

# -----------------------------------------------------------------------------

# Fix mismatched host-container user id
user_group_changed=
if [[ -n $GROUP_ID && $GROUP_ID -ne 0 && $GROUP_ID -ne 82 ]]; then
    groupmod -g "$GROUP_ID" www-data
    user_group_changed=1
    entrypoint_note "Setting GID of group www-data to $GROUP_ID"
else
    entrypoint_warn 'Cannot set GID of group www-data to either 0 (root) or 82 (default of www-data)'
fi
if [[ -n $USER_ID && $USER_ID -ne 0 && $USER_ID -ne 82 ]]; then
    usermod -u "$USER_ID" www-data
    user_group_changed=1
    entrypoint_note "Setting UID of user www-data to $USER_ID"
else
    entrypoint_warn 'Cannot set UID of user www-data to either 0 (root) or 82 (default of www-data)'
fi

if [[ $user_group_changed -eq 1 ]]; then
    entrypoint_note 'Updating all folders and files according to new GID and UID'
    find . ! \( -user www-data -or -group www-data \) -a -writable -exec chown www-data:www-data {} +
fi
unset user_group_changed

# -----------------------------------------------------------------------------

# Prepare nginx
if [[ $1 == 'node' ]]; then
    entrypoint_note 'Entrypoint script for NodeJS (frontend) started'

    # -------------------------------------------------------------------------

    entrypoint_note 'Check necessary environment variables'
fi

exec "$@"
