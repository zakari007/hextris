FROM node:18-alpine

WORKDIR /app

# Copy package files first for better caching
COPY package*.json ./
RUN npm install

# Copy application files
COPY . .

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S hextris -u 1001 && \
    chown -R hextris:nodejs /app

USER hextris

EXPOSE 8080

CMD ["npm", "start"]