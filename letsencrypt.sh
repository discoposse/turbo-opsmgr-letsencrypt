#!/usr/bin/env bash
set -o errexit -o pipefail -o noclobber -o nounset

! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]
then
  echo "Unexpected result from 'getopt --test'. Please ensure that getopt is installed and the latest version."
  exit 1
fi

OPTIONS="e:h:"
LONGOPTS=(
"email:"
"fqdn:"
)

! PARSED=$(getopt --options "$OPTIONS" --longoptions "$(printf "%s," "${LONGOPTS[@]}")" --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]
then
  exit 2
fi

eval set -- "$PARSED"

email="" fqdn=""
reqs=y

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--email)
      email="$2"
      shift 2
      ;;
    -h|--fqdn)
      fqdn="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unexpected commandline switch $1"
      exit 3
      ;;
  esac
done

if [[ -z $email ]]
then
  echo "-e or --email is required"
  reqs=n
fi

if [[ -z $fqdn ]]
then
  echo "-h or --fqdn is required"
  reqs=n
fi

# Bail if we're performing a task which requires CLI parameters, but they aren't
# satisfied
if [[ "$reqs" == "n" ]]
then
  exit 4
fi

# Install docker to run certbot
curl -fsSL https://get.docker.com/ | sh
systemctl start docker
systemctl enable docker

# Proxy the certbot challenge requests to the certbot docker container
if [[ ! -e "/etc/httpd/conf.d/00letsencrypt.conf" ]]; then
cat > /etc/httpd/conf.d/00letsencrypt.conf << EOF
RewriteRule ^/?\.well-known - [L]
ProxyPass "/.well-known" "http://localhost:8888/.well-known"
EOF
fi

service httpd reload

docker run --rm -it -v /etc/letsencrypt:/etc/letsencrypt -p 8888:80 certbot/certbot \
  certonly --standalone --rsa-key-size 4096 -n --agree-tos -m "$email" -d "$fqdn"

if [[ -e "/etc/httpd/conf.d/ssl.conf" ]]; then
  mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.turbo
fi

cat > "/etc/httpd/conf.d/ssl.conf" << EOF
Listen 443
<IfModule mod_ssl.c>
<VirtualHost *:443>
	DocumentRoot "/var/www/html"
	ServerName "$fqdn"
  SSLEngine on

  # Intermediate configuration, tweak to your needs
  SSLProtocol             all -SSLv2 -SSLv3
  SSLCipherSuite          ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS
  SSLHonorCipherOrder     on
  SSLCompression          off

  SSLOptions +StrictRequire

  # Add vhost name to log entries:
  LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"" vhost_combined
  LogFormat "%v %h %l %u %t \"%r\" %>s %b" vhost_common

  SSLCertificateFile /etc/letsencrypt/live/$fqdn/cert.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/$fqdn/privkey.pem
  SSLCertificateChainFile /etc/letsencrypt/live/$fqdn/chain.pem
  IncludeOptional conf.d/rewrite.conf
</VirtualHost>
</IfModule>
EOF

service httpd restart

# Make sure we renew our cert in perpetuity forever
! grep "certbot renew" /etc/crontab > /dev/null
if [[ ${PIPESTATUS[0]} -eq 1 ]]; then
  echo "0 0,12 * * * docker run --rm -it -v /etc/letsencrypt:/etc/letsencrypt -p 8888:80 certbot/certbot renew --standalone" | tee -a /etc/crontab > /dev/null
fi
