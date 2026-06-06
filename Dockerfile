# STAGE 1: Builder
FROM elixir:1.19-alpine AS builder

RUN apk add --no-cache build-base git curl

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY config ./config
COPY lib ./lib
COPY priv ./priv

RUN mix compile
RUN mix release

# STAGE 2: Release
FROM alpine:3.23 AS release

RUN apk add --no-cache ncurses-libs openssl libstdc++ ca-certificates bash

RUN addgroup -g 1000 elixir && adduser -D -u 1000 -G elixir elixir

WORKDIR /app

COPY --from=builder --chown=elixir:elixir /app/_build/prod/rel/synapse ./

RUN chown -R elixir:elixir /app

RUN printf '#!/bin/sh\nset -e\necho "Running Synapse migrations..."\nbin/synapse eval "Synapse.Release.migrate()"\necho "Starting Synapse..."\nexec bin/synapse start\n' > /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

USER elixir

ENV HOME=/home/elixir
ENV PORT=4003
ENV MIX_ENV=prod
ENV PHX_SERVER=true

EXPOSE 4003

CMD ["/app/entrypoint.sh"]
