# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target

# https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact
ARG NODE_VERSION=14
ARG NGINX_VERSION=1.19

# ---------
# Development stage
# ---------
FROM --platform=${BUILDPLATFORM:-linux/amd64} node:${NODE_VERSION}-alpine AS development

WORKDIR /app

# Prevent the reinstallation of node modules at every changes in the source code
COPY .yarn ./.yarn
COPY .yarnrc.yml package.json yarn.lock ./
RUN set -eux; \
	yarn install --immutable

COPY . .

CMD ["yarn", "run", "start"]

# ---------
# Build stage
# ---------
# Depends on the "development" stage above
FROM development AS build

RUN set -eux; \
    yarn run build

# -----------
# Nginx stage
# -----------
# Depends on the "build" stage above
FROM nginx:${NGINX_VERSION}-alpine AS nginx

WORKDIR /app

# Setup Alpine
# hadolint ignore=DL3018
RUN set -eux; \
    \
    apk update; \
    apk add --no-cache \
        bash \
        bash-completion \
        openssl; \
    \
    # Custom bash config
    { \
        echo 'source /etc/profile.d/bash_completion.sh'; \
        # <green> user@host <normal> : <blue> dir <normal> $#
        echo 'export PS1="🐳 \e[38;5;10m\u@\h\e[0m:\e[38;5;12m\w\e[0m\\$ "'; \
    } >"$HOME/.bashrc"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Setup Nginx
COPY --from=build /app/build ./

COPY docker/nginx.conf       /etc/nginx/nginx.template
COPY docker/default.conf     /etc/nginx/conf.d/default.template
COPY docker/default-ssl.conf /etc/nginx/conf.d/default-ssl.template

RUN set -eux; \
    \
    # Remove default config, will be replaced on startup with custom one
    rm /etc/nginx/conf.d/default.conf; \
    \
    # Empty all php files (to reduce container size). Only the file's existence is important
    find . -type f -name "*.php" -exec sh -c 'i="$1"; >"$i"' _ {} \;; \
    \
    # Fix permission
    adduser -u 82 -D -S -G www-data www-data

HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD curl -fsSL http://localhost >/dev/null || exit 1

COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
