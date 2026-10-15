# syntax=docker/dockerfile:1
ARG RUBY_VERSION="4.0.7"
ARG DEBIAN_BASE="trixie"
# Add SBOM scan context for intermediate steps
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true
ARG BUILDKIT_SBOM_SCAN_STAGE=true

# Compile a patched json gem to replace the outdated default gem that ships with Ruby.
# CVE-2026-33210 is fixed in 2.19.2, CVE-2026-54696 in 2.19.9.
FROM ruby:${RUBY_VERSION}-slim-${DEBIAN_BASE} AS json-gem
ENV GEM_HOME=/usr/local/lib/ruby/gems/4.0.0
ENV GEM_PATH=/usr/local/lib/ruby/gems/4.0.0
RUN apt-get update \
 && apt-get install -yq --no-install-recommends build-essential \
 && gem install json -v 2.21.2 --no-document \
 && rm -rf /var/lib/apt/lists/*

FROM ruby:${RUBY_VERSION}-slim-${DEBIAN_BASE} AS runtime-base
LABEL maintainer="operations@openproject.com"

ARG NODE_VERSION="24.19.0"
# npm bundled with node lags behind on patches for its vendored deps (e.g. tar)
ARG NPM_VERSION="11.19.0"
ARG BIM_SUPPORT=true
ENV USE_JEMALLOC=false
ENV DEBIAN_FRONTEND=noninteractive
ENV BUNDLE_JOBS=8
ENV BUNDLE_RETRY=3
ENV BUNDLE_WITHOUT="development:test"

# SYSTEM
ENV DOCKER=1
ENV APP_USER=app
ENV APP_PATH=/app
ENV APP_DATA_PATH=/var/openproject/assets
ENV BUNDLE_PATH="$APP_PATH/vendor/bundle"
ENV BUNDLE_APP_CONFIG="$APP_PATH/.bundle"
ENV PGVERSION="17"
ENV PGVERSION_CHOICES="13 15 17"
ENV PGBIN="/usr/lib/postgresql/$PGVERSION/bin"
ENV PATH="$PGBIN:$PATH"

# RAILS
# Set a default key base, ensure to provide a secure value in production environments!
ENV SECRET_KEY_BASE=OVERWRITE_ME
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=1
ENV RAILS_SERVE_STATIC_FILES=1

# OPENPROJECT
# Valid values are: standard,bim
ENV OPENPROJECT_EDITION=standard
ENV OPENPROJECT_INSTALLATION__TYPE=docker
ENV OPENPROJECT_ATTACHMENTS__STORAGE__PATH=$APP_DATA_PATH/files
ENV OPENPROJECT_RAILS__CACHE__STORE=file_store
ENV OPENPROJECT_ANGULAR_UGLIFY=true

# set the following to an empty string if you don't want to automatically use the bundled hocuspocus
# (or set an external hocuspocus directly - if empty you can set it in the UI)
ENV OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__URL=auto
ENV OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET=

RUN useradd -d /home/$APP_USER -m $APP_USER && \
  mkdir -p $APP_PATH && chown $APP_USER:$APP_USER $APP_PATH && \
  mkdir -p $APP_DATA_PATH && chown $APP_USER:$APP_USER $APP_DATA_PATH && chmod g+rwx $APP_DATA_PATH

WORKDIR $APP_PATH

# upgrade bundler
RUN gem install bundler --no-document

# Replace the vulnerable json default gem shipped with the Ruby base image.
# CVE-2026-33210 is fixed in 2.19.2, CVE-2026-54696 in 2.19.9.
COPY --from=json-gem /usr/local/lib/ruby/gems/4.0.0/gems/json-2.21.2 /usr/local/lib/ruby/gems/4.0.0/gems/json-2.21.2
COPY --from=json-gem /usr/local/lib/ruby/gems/4.0.0/specifications/json-2.21.2.gemspec /usr/local/lib/ruby/gems/4.0.0/specifications/json-2.21.2.gemspec
COPY --from=json-gem /usr/local/lib/ruby/gems/4.0.0/extensions /usr/local/lib/ruby/gems/4.0.0/extensions
RUN rm -f /usr/local/lib/ruby/gems/4.0.0/specifications/default/json-*.gemspec \
 && rm -rf /usr/local/lib/ruby/gems/4.0.0/gems/json-2.18.0 \
 && rm -rf /usr/local/lib/ruby/gems/4.0.0/extensions/*/json-2.18.0 \
 && rm -f /usr/local/lib/ruby/4.0.0/json.rb \
 && rm -rf /usr/local/lib/ruby/4.0.0/json \
 && rm -rf /usr/local/lib/ruby/4.0.0/*-linux/json

# runtime dependencies
COPY ./docker/prod/setup/preinstall-common.sh ./docker/prod/setup/preinstall-common.sh
RUN sed -i 's/\r$//' ./docker/prod/setup/preinstall-common.sh && ./docker/prod/setup/preinstall-common.sh

# npm vendors vulnerable dependencies (CVE-2026-69192, CVE-2026-14257, CVE-2026-102276, CVE-2026-102278).
COPY ./docker/prod/setup/patch-npm-bundled-deps.sh ./docker/prod/setup/patch-npm-bundled-deps.sh
RUN sed -i 's/\r$//' ./docker/prod/setup/patch-npm-bundled-deps.sh && ./docker/prod/setup/patch-npm-bundled-deps.sh

FROM runtime-base AS build-base
ARG NODE_VERSION="24.19.0"
ARG NPM_VERSION="11.19.0"

# build-only dependencies
COPY ./docker/prod/setup/preinstall-build.sh ./docker/prod/setup/preinstall-build.sh
RUN sed -i 's/\r$//' ./docker/prod/setup/preinstall-build.sh && ./docker/prod/setup/preinstall-build.sh

# npm vendors vulnerable dependencies (CVE-2026-69192, CVE-2026-14257, CVE-2026-102276, CVE-2026-102278).
COPY ./docker/prod/setup/patch-npm-bundled-deps.sh ./docker/prod/setup/patch-npm-bundled-deps.sh
RUN sed -i 's/\r$//' ./docker/prod/setup/patch-npm-bundled-deps.sh && ./docker/prod/setup/patch-npm-bundled-deps.sh

# Node dependencies only depend on the package manifests, so they stay cached
# across source changes. node_modules are copied into app-build below.
FROM build-base AS node-deps
COPY package.json package-lock.json .npmrc ./
COPY frontend/package.json frontend/package-lock.json frontend/.npmrc ./frontend/
COPY frontend/patches ./frontend/patches
RUN --mount=type=cache,target=/root/.npm,sharing=locked   npm ci --ignore-scripts &&   cd frontend && npm ci

# Only what `bundle install` reads (gemspecs, Gemfiles, version files). Everything
# else is stripped, so the layer hash - and the bundle-install cache - only changes
# when dependencies change, not on every edit under modules/ or lib/.
FROM busybox AS gem-manifests
WORKDIR /m
COPY modules ./modules
COPY vendor ./vendor
COPY lib ./lib
RUN find . -type f ! -name '*.gemspec' ! -name 'Gemfile*' ! -name 'version.rb' ! -name '.ruby-version' -delete  && find . -type d -empty -delete

FROM build-base AS app-build

# stuff required for gems
COPY Gemfile Gemfile.* .ruby-version ./
COPY --from=gem-manifests /m/ ./
# Normalize CRLF -> LF (sources checked out on Windows with autocrlf)
RUN find . \( -path ./vendor/bundle -o -path ./node_modules -o -path ./frontend/node_modules \) -prune -o \
      -type f \( -name '*.rb' -o -name '*.erb' -o -name '*.rake' -o -name '*.ru' -o -name '*.sh' \
      -o -name '*.yml' -o -name '*.yaml' -o -name '*.js' -o -name '*.ts' -o -name '*.json' \
      -o -name '*.gemspec' -o -name 'Gemfile*' -o -path './docker/*' \) -print0 | xargs -0 -r sed -i 's/\r$//'

# The restored vendor/bundle cache already arrives with `COPY vendor` above. Naming
# it again here copied its *contents* into vendor/, leaving a stale second gem tree.
COPY ./docker/prod/setup/bundle-install.sh ./vendor/
RUN sed -i 's/\r$//' vendor/bundle-install.sh && bash vendor/bundle-install.sh && rm vendor/bundle-install.sh

COPY --from=node-deps /app/node_modules ./node_modules
COPY --from=node-deps /app/frontend/node_modules ./frontend/node_modules

COPY . .
# Normalize CRLF -> LF (sources checked out on Windows with autocrlf)
RUN find . \( -path ./vendor/bundle -o -path ./node_modules -o -path ./frontend/node_modules \) -prune -o \
      -type f \( -name '*.rb' -o -name '*.erb' -o -name '*.rake' -o -name '*.ru' -o -name '*.sh' \
      -o -name '*.yml' -o -name '*.yaml' -o -name '*.js' -o -name '*.ts' -o -name '*.json' \
      -o -name '*.gemspec' -o -name 'Gemfile*' -o -path './docker/*' \) -print0 | xargs -0 -r sed -i 's/\r$//'

# Copy lock file again as the updated version was overriden by COPY just now.
# `COPY . .` also restores the CI vendor/bundle cache over the installed bundle, so
# the superseded gem versions bundle-install.sh pruned are back and need pruning again.
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    --mount=type=cache,target=/app/frontend/.angular/cache,sharing=locked \
  cp Gemfile.lock.bak Gemfile.lock && rm Gemfile.lock.bak && \
  bundle clean --force && \
  ./docker/prod/setup/precompile-assets.sh

FROM app-build AS app-build-slim
COPY ./docker/prod/setup/prune-slim-runtime.sh ./docker/prod/setup/prune-slim-runtime.sh
RUN ./docker/prod/setup/prune-slim-runtime.sh

FROM runtime-base AS app-runtime

COPY --chown=$APP_USER:$APP_USER --from=app-build /app /app

RUN ./docker/prod/setup/postinstall-common.sh && \
  cp ./config/database.production.yml config/database.yml && \
  ln -s $APP_PATH/docker/prod/setup/.irbrc /home/$APP_USER/

FROM runtime-base AS app-runtime-slim

COPY --chown=$APP_USER:$APP_USER --from=app-build-slim /app /app

RUN ./docker/prod/setup/postinstall-common.sh && \
  cp ./config/database.production.yml config/database.yml && \
  ln -s $APP_PATH/docker/prod/setup/.irbrc /home/$APP_USER/

# -------------------------------------
# slim (public)
# -------------------------------------
FROM app-runtime-slim AS slim

USER $APP_USER
EXPOSE 8080
CMD ["./docker/prod/web"]
ENTRYPOINT ["./docker/prod/entrypoint-slim.sh"]
VOLUME ["$APP_DATA_PATH"]

# -------------------------------------
# slim-bim (public)
# same as slim but with BIM support enabled
# -------------------------------------
FROM app-runtime-slim AS slim-bim

USER $APP_USER
EXPOSE 8080
CMD ["./docker/prod/web"]
ENTRYPOINT ["./docker/prod/entrypoint-slim.sh"]
VOLUME ["$APP_DATA_PATH"]
ENV OPENPROJECT_EDITION=bim
# -------------------------------------
# all-in-one (public)
# -------------------------------------
FROM app-runtime AS all-in-one

ENV OPENPROJECT_RAILS__CACHE__STORE=memcache
ENV DATABASE_URL=postgres://openproject:openproject@127.0.0.1/openproject
ENV PGDATA=/var/openproject/pgdata

COPY --from=openproject/hocuspocus:17.9.1 --chown=$APP_USER:$APP_USER /app /opt/hocuspocus
# Keep node/npm in all-in-one for bundled hocuspocus even when BIM support is disabled.
COPY --from=build-base /usr/local/bin/node /usr/local/bin/node
COPY --from=build-base /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN ./docker/prod/setup/postinstall-onprem.sh && \
  ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
  ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
  ln -sf ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack && \
  ln -s /app/docker/prod/setup/.irbrc /root/

# Expose ports for apache and postgres
EXPOSE 80

# Expose the postgres data directory and OpenProject data directory as volumes
VOLUME ["$PGDATA", "$APP_DATA_PATH"]

# Set a custom entrypoint to allow for privilege dropping and one-off commands
ENTRYPOINT ["./docker/prod/entrypoint.sh"]

# Set default command to launch the all-in-one configuration supervised by supervisord
CMD ["./docker/prod/supervisord"]

# =============================================================================
# Environment targets for the standalone compose stacks (web/worker/cron/seeder
# all run the same image with a different command). They share every layer up to
# app-runtime-slim, so building several of them only costs the thin layer below.
#   docker build -f docker/prod/Dockerfile --target production .
# Use --build-arg EDITION=bim for the BIM edition.
# =============================================================================
FROM app-runtime-slim AS env-base

ARG EDITION=standard
ARG VERSION=unknown
ARG REVISION=unknown
ARG CREATED=unknown

ENV OPENPROJECT_EDITION=$EDITION

LABEL org.opencontainers.image.title="OpenProject" \
      org.opencontainers.image.vendor="OpenProject GmbH" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/opf/openproject" \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.revision=$REVISION \
      org.opencontainers.image.created=$CREATED

USER $APP_USER
EXPOSE 8080
VOLUME ["$APP_DATA_PATH"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["./docker/prod/entrypoint-slim.sh"]
CMD ["./docker/prod/web"]

# local: allocator defaults, nothing hardened.
FROM env-base AS local

# -------------------------------------
# distroless runtime for staging and production: no apt, no dpkg tooling and no
# package manager; only bash/busybox for the docker/prod/* scripts.
# The rootfs is assembled from the Debian slim runtime (see the script header).
# -------------------------------------
FROM app-runtime-slim AS distroless-rootfs
COPY ./docker/prod/setup/build-distroless-rootfs.sh ./docker/prod/setup/build-distroless-rootfs.sh
RUN ./docker/prod/setup/build-distroless-rootfs.sh

FROM gcr.io/distroless/base-debian13 AS env-distroless
ARG EDITION=standard
ARG VERSION=unknown
ARG REVISION=unknown
ARG CREATED=unknown

COPY --from=distroless-rootfs /rootfs/ /
COPY --from=app-runtime-slim --chown=app:app /app /app

# Environment of the Debian runtime-base stage and the ruby image (not inherited here).
ENV LANG=C.UTF-8 \
    GEM_HOME=/usr/local/bundle \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_JOBS=8 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT="development:test" \
    DOCKER=1 \
    APP_USER=app \
    APP_PATH=/app \
    APP_DATA_PATH=/var/openproject/assets \
    BUNDLE_PATH=/app/vendor/bundle \
    BUNDLE_APP_CONFIG=/app/.bundle \
    PGVERSION=17 \
    PGVERSION_CHOICES="13 15 17" \
    PGBIN=/usr/lib/postgresql/17/bin \
    PATH=/usr/lib/postgresql/17/bin:/usr/local/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    SECRET_KEY_BASE=OVERWRITE_ME \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1 \
    OPENPROJECT_EDITION=$EDITION \
    OPENPROJECT_INSTALLATION__TYPE=docker \
    OPENPROJECT_ATTACHMENTS__STORAGE__PATH=/var/openproject/assets/files \
    OPENPROJECT_RAILS__CACHE__STORE=file_store \
    OPENPROJECT_ANGULAR_UGLIFY=true \
    OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__URL=auto \
    OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET= \
    USE_JEMALLOC=true

LABEL org.opencontainers.image.title="OpenProject" \
      org.opencontainers.image.vendor="OpenProject GmbH" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/opf/openproject" \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.revision=$REVISION \
      org.opencontainers.image.created=$CREATED

WORKDIR /app
USER app
EXPOSE 8080
VOLUME ["/var/openproject/assets"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["./docker/prod/entrypoint-slim.sh"]
CMD ["./docker/prod/web"]

FROM env-distroless AS staging

FROM env-distroless AS production
