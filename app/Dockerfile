FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

# The official Node image includes a non-root "node" user (UID 1000)
USER node

EXPOSE 3000

CMD ["node", "index.js"]

