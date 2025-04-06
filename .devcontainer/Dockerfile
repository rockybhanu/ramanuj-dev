# Use a base Alpine image with Hugo installed manually for dev
FROM alpine:latest
RUN apk add --no-cache wget tar git curl
ENV HUGO_VERSION 0.129.0
RUN wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    tar -xzf hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    mv hugo /usr/local/bin/hugo && \
    rm hugo_${HUGO_VERSION}_linux-amd64.tar.gz

WORKDIR /workspaces/ramanuj-dev
# Copy your source code into the container (or mount it via devcontainer.json)
COPY . /workspaces/ramanuj-dev

# Optionally, update submodules if needed
#RUN git submodule update --init --recursive

# Expose Hugo’s default port
EXPOSE 1313

# Run Hugo server in watch mode for live reload
CMD ["hugo", "server", "--bind", "0.0.0.0", "--baseURL", "http://localhost:1313"]


