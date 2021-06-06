# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target

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

LABEL maintainer="D3strukt0r <dev@d3strukt0r.me>"

# hadolint ignore=DL3018
RUN set -o errexit -o nounset -o pipefail -o xtrace; \
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

RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    # Custom bash config
    rm /etc/profile.d/color_prompt; \
    echo '. /etc/profile' >"$HOME/.bashrc"; \
    \
    # Fix no www folder
    mkdir --parents /var/www; \
    \
    # Fix missing user/group in php/nginx
    # 82 is the standard uid/gid for "www-data" in Alpine
    # https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.9-stable
    # https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.9-stable
    # https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.9-stable
    groupadd --gid 82 --system www-data; \
    useradd --uid 82 --shell /bin/bash --password '*' --create-home --system --gid www-data www-data; \
    echo '. /etc/profile' >/home/www-data/.bashrc; \
    chown --changes --silent --no-dereference --recursive www-data:www-data \
        /var/www

COPY .docker/os/color_prompt.sh /etc/profile.d/color_prompt.sh

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# NodeJS base
# -----------------------------------------------------------------------------
FROM --platform=${BUILDPLATFORM:-linux/amd64} base AS base-node

# hadolint ignore=DL3018
RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    apk update; \
    apk add --no-cache \
        nodejs-current \
        npm \
        yarn; \
    \
    # Smoke tests
    node --version; \
    npm --version; \
    yarn --version

#RUN set -o errexit -o nounset -o pipefail -o xtrace; \
#    groupadd --gid 1000 node; \
#    useradd --uid 1000 --shell /bin/bash --password '*' --create-home --system --gid node node; \
#    echo '. /etc/profile' >/home/node/.bashrc

WORKDIR /var/www

COPY .docker/node/docker-entrypoint.sh /usr/bin/docker-entrypoint
RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    chmod +x /usr/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["node"]

# -----------------------------------------------------------------------------
# NodeJS base (Dev environment)
# -----------------------------------------------------------------------------
FROM base-node AS base-node-dev

EXPOSE 3000

CMD ["yarn", "run", "start"]

# -----------------------------------------------------------------------------
# Install vendors and build application
# -----------------------------------------------------------------------------
FROM base-node AS app-build

# Prevent the reinstallation of node modules at every changes in the source code
COPY package.json yarn.lock ./
RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    su --command 'yarn install --immutable' www-data

COPY --chown=www-data:www-data public ./public
COPY --chown=www-data:www-data src ./src
COPY --chown=www-data:www-data tsconfig.json ./
RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    su --command 'yarn run build' www-data

# -----------------------------------------------------------------------------
# Nginx base
# -----------------------------------------------------------------------------
FROM base AS base-nginx

ENV NGINX_DIR="/etc/nginx"

# hadolint ignore=DL3018
RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    apk update; \
    apk add --no-cache \
        gettext \
        tzdata \
        # Nginx
        nginx

RUN set -o errexit -o nounset -o pipefail -o xtrace; \
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
RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    chmod +x /usr/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]

# -----------------------------------------------------------------------------
# App (Nginx environment)
# -----------------------------------------------------------------------------
# Depends on the "build" stage above
FROM base-nginx AS app-nginx

COPY --from=app-build --chown=www-data:www-data /var/www/build ./

RUN set -o errexit -o nounset -o pipefail -o xtrace; \
    # Empty all php files (to reduce container size). Only the file's existence is important
    find . -type f -name '*.php' -exec sh -c 'i="$1"; >"$i"' _ {} \;; \
    \
    # Fix permission
    find . -not -\( -user www-data -or -group www-data -\) -exec chown www-data:www-data {} +; \
    find . -type d -a -not -perm u=rwx,g=rx,o=rx -exec chmod u=rwx,g=rx,o=rx {} +; \
    find . -type f -a -not -perm u=rw,g=r,o=r -exec chmod u=rw,g=r,o=r {} +
