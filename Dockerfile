# ---------- Build stage ----------
FROM node:24-alpine AS builder

RUN apk add --no-cache ca-certificates

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev || npm install --production --no-audit --no-fund

COPY server.js .
COPY vrx/production ./vrx


RUN npm cache clean --force || true

# ---------- Runtime stage (distroless) ----------
FROM gcr.io/distroless/nodejs24-debian13



WORKDIR /app

COPY --from=builder --chown=nonroot:nonroot /app /app

ENV NODE_ENV=production \
    TLS=false \
    DEBUG=true \
    KEEP_ALIVE=false \
    PORT=80

USER nonroot:nonroot

EXPOSE 80
CMD ["server.js"]
