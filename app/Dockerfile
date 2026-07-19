# syntax=docker/dockerfile:1

# --- Stage 1: install deps (none runtime, but keeps the pattern for future growth) ---
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
# No dependencies today; --omit=dev keeps it honest if any are added later.
# mkdir guarantees node_modules exists even with zero deps, so the COPY below works.
RUN npm install --omit=dev --no-audit --no-fund && mkdir -p node_modules

# --- Stage 2: minimal runtime, non-root, distroless-style hardening on alpine ---
FROM node:20-alpine AS runtime
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app

# Run as the built-in unprivileged 'node' user, never root.
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src

USER node
EXPOSE 3000

# Container-level healthcheck (belt-and-suspenders alongside the ALB check).
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "src/server.js"]
