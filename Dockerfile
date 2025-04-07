FROM alpine:latest AS builder
RUN apk add --no-cache wget tar git
ENV HUGO_VERSION 0.129.0
RUN wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    tar -xzf hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    mv hugo /usr/local/bin/hugo && \
    rm hugo_${HUGO_VERSION}_linux-amd64.tar.gz
WORKDIR /src
COPY . /src
#RUN git submodule update --init --recursive
RUN hugo --minify
FROM nginx:alpine
RUN addgroup -S hugo && adduser -S hugo -G hugo
RUN mkdir -p /var/cache/nginx /var/run/nginx /var/log/nginx && \
    chown -R hugo:hugo /var/cache/nginx /var/run/nginx /var/log/nginx /etc/nginx /usr/share/nginx/html
COPY --from=builder /src/public /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
USER hugo
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]