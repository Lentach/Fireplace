# syntax=docker/dockerfile:1
# Stage 1: Build — full deps, compile TS -> dist/main.js
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Production runtime — prod deps + built dist only
FROM node:20-alpine
ARG APP_VERSION=0.0.1
ARG GIT_COMMIT=unknown
ARG BUILD_TIME=
ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    BUILD_TIME=${BUILD_TIME} \
    NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist
EXPOSE 3000
CMD ["node", "dist/main.js"]
