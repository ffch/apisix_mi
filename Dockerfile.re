# base img
FROM gateway:v2

WORKDIR /usr/local/apisix
COPY apisix .
COPY conf .
COPY conf/config.yaml /usr/local/apisix/conf/config.yaml
COPY example/apisix/plugins/log-record.lua /usr/local/apisix/apisix/plugins/log-record.lua

