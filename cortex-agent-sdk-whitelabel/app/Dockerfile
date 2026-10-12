# ACME Assist: one image serving dist/ and /api from a single Express process on :8080.
# The PAT is never baked in: mount it at runtime (SNOWFLAKE_PAT_FILE). In SPCS no PAT is used.
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html vite.config.ts tsconfig.json ./
COPY public ./public
COPY shared ./shared
COPY src ./src
COPY scripts/chunk-report.mjs ./scripts/chunk-report.mjs
RUN npm run build

FROM node:22-slim AS runner
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm install --no-save tsx@4 && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY server ./server
COPY shared ./shared
COPY src/agent/tools ./src/agent/tools
COPY src/apps/storeops/data ./src/apps/storeops/data
COPY coco-runner/skills.json ./coco-runner/skills.json
RUN useradd -m acme && mkdir -p /app/.data && chown -R acme /app/.data
USER acme
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD node -e "fetch('http://localhost:8080/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["npx", "tsx", "server/express.ts"]
