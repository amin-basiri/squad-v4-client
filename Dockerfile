# Use a minimal base image
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Enable Yarn (since corepack is built-in with Node.js 20)
RUN corepack enable && corepack prepare yarn@1.22.22 --activate

# For build purposes we need dev dependencies
ENV NODE_ENV=development

# Ensure consistent timestamps for deterministic builds
ENV SOURCE_DATE_EPOCH=315532800

# Copy dependencies first (for better caching)
COPY package.json yarn.lock ./

# Install dependencies in a reproducible way (including dev dependencies)
RUN yarn install --frozen-lockfile --non-interactive --check-files

# Copy the full source code after dependencies are cached
COPY . .

# Build the application using Webpack
RUN yarn build

# Set NODE_ENV back to production for any post-build steps
ENV NODE_ENV=production

# Ensure consistent timestamps for all files in dist/
RUN find dist -exec touch -d @${SOURCE_DATE_EPOCH} {} + && \
    find dist -exec chmod 644 {} +

# Prepare final output structure
RUN mkdir -p /squads-public-build/dist && \
    mv dist/* /squads-public-build/dist && \
    cd /squads-public-build/dist && \
    find . -type f -print0 | sort -z | xargs -0 cat | sha256sum | awk '{ print $1 }' > /squads-public-build/hash.txt

# Set proper permissions
RUN chmod -R u+rwX,go+rX /squads-public-build/dist && \
    chmod u+rw,go+r /squads-public-build/hash.txt

# Copy the build output to a standard location
RUN mkdir -p /output && cp -r /squads-public-build/* /output/

# Create nginx config file
RUN echo 'server { \
    listen 80; \
    server_name localhost; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri /index.html; \
    } \
}' > /output/default.conf

# Use a lightweight web server for serving static files
FROM nginx:alpine AS server

# Copy built files and hash into the nginx root directory
COPY --from=builder /output/dist /usr/share/nginx/html
COPY --from=builder /output/hash.txt /var/build-metadata/hash.txt

# Ensure Nginx serves the correct index.html
RUN rm /etc/nginx/conf.d/default.conf
COPY --from=builder /output/default.conf /etc/nginx/conf.d/default.conf

# Expose port 80 for serving the static site
EXPOSE 80

# Default command to run nginx
CMD ["nginx", "-g", "daemon off;"]
