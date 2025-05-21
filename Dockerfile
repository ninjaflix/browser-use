# syntax=docker/dockerfile:1

# Dockerfile simplificado para Railway para browser-use
FROM python:3.11-slim

LABEL name="browseruse" \
    maintainer="Nick Sweeting <dockerfile@browser-use.com>" \
    description="Make websites accessible for AI agents. Automate tasks online with ease." \
    homepage="https://github.com/browser-use/browser-use" \
    documentation="https://docs.browser-use.com"

# Global system-level config
ENV TZ=UTC \
    LANGUAGE=en_US:en \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 \
    PYTHONIOENCODING=UTF-8 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_CACHE_DIR=/root/.cache/uv \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_PREFERENCE=only-system \
    npm_config_loglevel=error \
    IN_DOCKER=True

# User config
ENV BROWSERUSE_USER="browseruse" \
    DEFAULT_PUID=911 \
    DEFAULT_PGID=911

# Paths
ENV CODE_DIR=/app \
    DATA_DIR=/data \
    VENV_DIR=/app/.venv \
    PATH="/app/.venv/bin:$PATH"

# Build shell config
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-o", "errtrace", "-o", "nounset", "-c"] 

# Simplified apt configuration 
RUN echo 'Binary::apt::APT::Keep-Downloaded-Packages "1";' > /etc/apt/apt.conf.d/99keep-cache \
    && echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/99no-intall-recommends \
    && echo 'APT::Install-Suggests "0";' > /etc/apt/apt.conf.d/99no-intall-suggests \
    && rm -f /etc/apt/apt.conf.d/docker-clean

# Create non-privileged user
RUN echo "[*] Setting up $BROWSERUSE_USER user..." \
    && groupadd --system $BROWSERUSE_USER \
    && useradd --system --create-home --gid $BROWSERUSE_USER --groups audio,video $BROWSERUSE_USER \
    && usermod -u "$DEFAULT_PUID" "$BROWSERUSE_USER" \
    && groupmod -g "$DEFAULT_PGID" "$BROWSERUSE_USER" \
    && mkdir -p /data \
    && mkdir -p /home/$BROWSERUSE_USER/.config \
    && chown -R $BROWSERUSE_USER:$BROWSERUSE_USER /home/$BROWSERUSE_USER \
    && ln -s $DATA_DIR /home/$BROWSERUSE_USER/.config/browseruse

# Install base dependencies
RUN apt-get update -qq \
    && apt-get install -qq -y --no-install-recommends \
        apt-transport-https ca-certificates apt-utils gnupg2 unzip curl wget grep \
        nano iputils-ping dnsutils jq \
    && rm -rf /var/lib/apt/lists/*

# Copy UV binary
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set up working directory and copy manifest
WORKDIR /app
COPY pyproject.toml uv.lock* /app/

# Set up virtual environment
RUN uv venv

# Install playwright with version from pyproject.toml
RUN uv pip install "$(grep -oP 'p....right>=([0-9.])+' pyproject.toml | head -n 1)" \
    && uv pip install "$(grep -oP 'p....right>=([0-9.])+' pyproject.toml | tail -n 1)"

# Install Chromium
RUN apt-get update -qq \
    && playwright install --with-deps --no-shell chromium \
    && rm -rf /var/lib/apt/lists/* \
    && export CHROME_BINARY="$(python -c 'from playwright.sync_api import sync_playwright; print(sync_playwright().start().chromium.executable_path)')" \
    && ln -s "$CHROME_BINARY" /usr/bin/chromium-browser \
    && ln -s "$CHROME_BINARY" /app/chromium-browser \
    && mkdir -p "/home/${BROWSERUSE_USER}/.config/chromium/Crash Reports/pending/" \
    && chown -R "$BROWSERUSE_USER:$BROWSERUSE_USER" "/home/${BROWSERUSE_USER}/.config"

# Install dependencies
RUN uv sync --all-extras --no-dev --no-install-project

# Copy the rest of the codebase
COPY . /app

# Install browser-use
RUN uv sync --all-extras --locked --no-dev

# Set up data directory
RUN mkdir -p "$DATA_DIR/profiles/default" \
    && chown -R $BROWSERUSE_USER:$BROWSERUSE_USER "$DATA_DIR" "$DATA_DIR"/*

USER "$BROWSERUSE_USER"
# Volume removed for Railway compatibility
EXPOSE 9242
EXPOSE 9222

ENTRYPOINT ["browser-use"]
