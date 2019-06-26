if [[ -z "$EMAIL" ]]; then
  echo "The environment variable EMAIL must be set."
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "The environment variable DOMAIN must be set."
  exit 1
fi

le_ssl_conf=/etc/httpd/conf.d/00letsencrypt-le-ssl.conf

# Enable EPEL first
yum install -y epel-release

# Install certbot
yum install -y certbot python2-certbot-apache

# Turbonomic OpsMgr doesn't have a default vhost listening on
# port 80, so we need to create one for certbot to host
# challenges from
cat > /etc/httpd/conf.d/00letsencrypt.conf << EOF
<VirtualHost *:80>
	DocumentRoot "/var/www/html"
	ServerName "$DOMAIN"
</VirtualHost>

RewriteRule ^\.well-known - [L]
EOF

service httpd reload

certbot --apache --rsa-key-size 4096 -n --agree-tos -m "$EMAIL" -d "$DOMAIN" --redirect

# Once certbot has done it's job, we need to make sure that we're listening on
# port 443, and that we include the default Turbonomic rewrite rules in the
# SSL vhost
if [[ -e "$le_ssl_conf" ]]; then
        grep "Listen 443" $le_ssl_conf > /dev/null
        if [[ $? -eq 1 ]]; then
                echo -e "Listen 443\n$(cat $le_ssl_conf)" > $le_ssl_conf
        fi

        grep "IncludeOptional" $le_ssl_conf > /dev/null
        if [[ $? -eq 1 ]]; then
                sed -i 's,</VirtualHost>,IncludeOptional conf.d/rewrite.conf\n</VirtualHost>,g' $le_ssl_conf
        fi
fi

if [[ -e "/etc/httpd/conf.d/ssl.conf" ]]; then
  mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.turbo
fi

service httpd restart

# Make sure we renew our cert in perpetuity forever
grep "certbot renew" /etc/crontab > /dev/null
if [[ $? -eq 1 ]]; then
  echo "0 0,12 * * * python -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew" | tee -a /etc/crontab > /dev/null
fi
