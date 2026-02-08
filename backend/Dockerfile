# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependency files first for layer caching
COPY package*.json ./
RUN npm ci --only=production && \
    npm cache clean --force

# Copy source and build
COPY . .
RUN npm install --only=development && \
    npm run build && \
    npm prune --production

# Stage 2: Production
FROM node:20-alpine

WORKDIR /app

# Copy only production dependencies and built app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./

EXPOSE 3000
CMD ["node", "dist/main.js"]
