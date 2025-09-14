# Dockerfile - with nginx
FROM nginx:stable-alpine

LABEL org.opencontainers.image.source="https://github.com/zakari007/hextris/"

# Set working dir where nginx serves files
WORKDIR /usr/share/nginx/html

# Remove default nginx content (optional), then copy project files
RUN rm -rf ./*

# Copy only the files needed for the site (faster) — adjust if you add build output.
COPY . /usr/share/nginx/html

EXPOSE 80

# Run nginx in foreground
CMD ["nginx", "-g", "daemon off;"]