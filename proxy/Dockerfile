FROM alpine:3.20
RUN apk add --no-cache tinyproxy
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 755 /entrypoint.sh
USER nobody
ENTRYPOINT ["/entrypoint.sh"]
