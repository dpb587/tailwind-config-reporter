FROM ghcr.io/dpb587/gget/gget as gget
RUN gget github.com/square/certstrap --executable certstrap=certstrap-linux-amd64

FROM ubuntu as certstrap
RUN apt update && apt install openssl
WORKDIR /export
RUN openssl dhparam -out dhparam.pem 2048
COPY --from=gget /result/certstrap /bin/certstrap
RUN certstrap init --passphrase='' --common-name ssl-bump-ca

FROM ubuntu:jammy-20240212
ENV TZ=UTC
RUN <<EOF
  apt update
  apt install -y squid-openssl
  rm -rf /var/lib/apt/lists/*
EOF
COPY --from=certstrap /export/out/ssl-bump-ca.crt /mnt/export/ssl-bump-ca.crt
COPY --from=certstrap /export/out/ssl-bump-ca.* /etc/squid/
COPY --from=certstrap /export/dhparam.* /etc/squid/ssl-bump-dhparam.pem
ADD squid.conf /etc/squid/squid.conf
ADD entrypoint.sh /usr/bin/entrypoint.sh
VOLUME [ "/mnt/squid" ]
ENTRYPOINT [ "/usr/bin/entrypoint.sh", "-N" ]
EXPOSE 3128
