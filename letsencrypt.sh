#!/usr/bin/env bash
set -o errexit -o pipefail -o noclobber -o nounset

if [[ -z "$EMAIL" ]]; then
  echo "The environment variable EMAIL must be set."
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "The environment variable DOMAIN must be set."
  exit 1
fi

# Install docker to run certbot
curl -fsSL https://get.docker.com/ | sh

# Proxy the certbot challenge requests to the certbot docker container
cat > /etc/httpd/conf.d/00letsencrypt.conf << EOF
RewriteRule ^/?\.well-known - [L]
ProxyPass "/.well-known" "http://localhost:8888/.well-known"
EOF

service httpd reload

docker run --rm -it -v /etc/letsencrypt:/etc/letsencrypt -p 8888:80 certbot/certbot \
  certonly --standalone --rsa-key-size 4096 -n --agree-tos -m "$EMAIL" -d "$DOMAIN"

if [[ -e "/etc/httpd/conf.d/ssl.conf" ]]; then
  mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.turbo
fi

cat > "/etc/httpd/conf.d/ssl.conf" << EOF
Listen 443
<IfModule mod_ssl.c>
<VirtualHost *:443>
	DocumentRoot "/var/www/html"
	ServerName "$DOMAIN"
SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/cert.pem
SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
Include /etc/letsencrypt/options-ssl-apache.conf
SSLCertificateChainFile /etc/letsencrypt/live/$DOMAIN/chain.pem
IncludeOptional conf.d/rewrite.conf
</VirtualHost>
</IfModule>
EOF

service httpd restart

# Make sure we renew our cert in perpetuity forever
! grep "certbot renew" /etc/crontab > /dev/null
if [[ $? -eq 1 ]]; then
  echo "0 0,12 * * * docker run --rm -it -v /etc/letsencrypt:/etc/letsencrypt -p 8888:80 certbot/certbot renew --standalone" | tee -a /etc/crontab > /dev/null
fi
