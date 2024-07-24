# Stage 1: Build the Hugo site
FROM alpine:latest AS builder

# Install necessary packages
RUN apk add --no-cache wget tar

# Set the Hugo version
ENV HUGO_VERSION 0.129.0

# Download and install Hugo
RUN wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    tar -xzf hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    mv hugo /usr/local/bin/hugo && \
    rm hugo_${HUGO_VERSION}_linux-amd64.tar.gz

# Set the working directory
WORKDIR /src

# Copy the current directory contents into the container at /src
COPY . /src

# Build the static files using Hugo
RUN hugo --minify

# Stage 2: Serve the static files with Nginx
FROM nginx:alpine

# Create a non-root user and group
RUN addgroup -S hugo && adduser -S hugo -G hugo

# Create necessary directories and set permissions
RUN mkdir -p /var/cache/nginx /var/run/nginx /var/log/nginx && \
    chown -R hugo:hugo /var/cache/nginx /var/run/nginx /var/log/nginx /etc/nginx /usr/share/nginx/html

# Copy the static files from the builder stage to the Nginx web root
COPY --from=builder /src/public /usr/share/nginx/html

# Copy a custom Nginx configuration file
COPY nginx.conf /etc/nginx/nginx.conf

# Switch to the non-root user
USER hugo

# Expose the port that Nginx runs on
EXPOSE 8080

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
