FROM node:20-alpine

WORKDIR /app

# Copy package*.json first — Docker caches the node_modules layer
# (faster rebuild when only source code changes)
COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

EXPOSE 3000
CMD ["node", "dist/main.js"]
