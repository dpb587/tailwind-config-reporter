#!/bin/sh

set -e

mkdir -p /mnt/squid
chown proxy:proxy /mnt/squid

if [ ! -d /mnt/squid/ssl-bump-db ]
then
  /usr/lib/squid/security_file_certgen -c -s /mnt/squid/ssl-bump-db -M 32MB
  chown -R proxy:proxy /mnt/squid/ssl-bump-db
fi

tail -F /var/log/squid/access.log 2>/dev/null &
tail -F /var/log/squid/error.log 2>/dev/null &
tail -F /var/log/squid/store.log 2>/dev/null &
tail -F /var/log/squid/cache.log 2>/dev/null &

/usr/sbin/squid -Nz

exec /usr/sbin/squid "${@}"
