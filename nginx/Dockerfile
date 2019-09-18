FROM debian:buster-slim

RUN apt-get update \
    && apt-get install -y \
       nginx-extras \
       dumb-init \
    && rm -rf /var/lib/apt/lists/*

COPY nginx.conf /etc/nginx/nginx.conf

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["nginx"]
