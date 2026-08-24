FROM rocker/r-ver:4.6.1

WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev \
      libicu-dev \
      libsodium-dev \
      libssl-dev \
      libuv1-dev \
      pkg-config \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
COPY renv.lock /app/renv.lock
RUN --mount=type=cache,target=/root/.cache/R/renv \
    R -q -e "install.packages('renv', repos='https://cloud.r-project.org')" \
    && R -q -e "renv::restore(lockfile='/app/renv.lock', prompt=FALSE)"
COPY . /app

ENV PORT=8000
EXPOSE 8000

CMD ["R", "--vanilla", "-f", "run.R"]
