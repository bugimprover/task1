FROM alpine:3.9
LABEL maintainer="zhuraveldm" \
      version="1.0"

# Install packages
RUN apk update && \
    apk add --no-cache \
    lighttpd \
    smokeping \
    curl \
    supervisor \
    fping && \
    rm -rf /var/cache/apk/*

COPY lighttpd/*.conf /etc/lighttpd/
COPY smokeping/* /etc/smokeping/
COPY www/ /var/www/
COPY data_smp/ /var/lib/smokeping
COPY supervisord.conf /etc/supervisord.conf

RUN ln -s /var/lib/smokeping/.simg /var/www/localhost/htdocs/smokeping/img && \
    chown -R lighttpd:lighttpd /var/lib/smokeping/

EXPOSE 80

VOLUME /etc/lighttpd/
VOLUME /etc/smokeping
VOLUME /var/www/
VOLUME /var/lib/smokeping

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
