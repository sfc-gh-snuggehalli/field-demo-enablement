# ACME Studio runner (Cortex Code headless via @snowflake/cortex-agent-sdk/code, CLI mode).
# Build context: app/ (so the generated coco-runner/skills.json is included).
#   docker build -f coco-runner/Dockerfile -t acme-coco-runner .
FROM node:22-slim
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip ca-certificates curl \
 && pip3 install --no-cache-dir --break-system-packages openpyxl reportlab matplotlib streamlit snowflake-cli \
 && rm -rf /var/lib/apt/lists/*
# The Cortex Code CLI (`cortex`) must be on PATH: the SDK's CLI mode spawns it.
# Provide it at build time from a vetted location (see README "Studio"), e.g.:
#   docker build --build-arg CORTEX_CLI_TARBALL=cortex-linux-x64.tar.gz ...
ARG CORTEX_CLI_TARBALL=""
COPY coco-runner/vendor/ /opt/vendor/
RUN if [ -n "$CORTEX_CLI_TARBALL" ]; then tar -xzf "/opt/vendor/$CORTEX_CLI_TARBALL" -C /usr/local/bin; fi
WORKDIR /runner
COPY coco-runner/package.json ./
RUN npm install --omit=dev
COPY coco-runner/src ./src
COPY coco-runner/skills.json ./skills.json
RUN useradd -m runner && mkdir -p /work && chown runner /work
USER runner
ENV PORT=8790 WORK_ROOT=/work
EXPOSE 8790
HEALTHCHECK CMD node -e "fetch('http://localhost:8790/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["npx", "tsx", "src/server.ts"]
