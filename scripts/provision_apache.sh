#!/bin/bash
# script/provision_apache.sh
# Automates the setup of the "Compromised Web Server" scenario in the Vagrant VM

set -e

echo "[*] Installing Apache and PHP..."
apt-get update
apt-get install -y apache2 php

echo "[*] Configuring www-data user..."
# Add www-data to the socket group to simulate shared access
usermod -aG devteam www-data

echo "[*] Deploying Webshell..."
cp /vagrant/exploits/webshell.php /var/www/html/exploit.php
chown www-data:www-data /var/www/html/exploit.php
chmod 644 /var/www/html/exploit.php

echo "[*] Deploying Exploit Binary..."
# Compile if not ready (though typically done by 'vagrant up' provisioner)
if [ ! -f /vagrant/exploits/dirtycow_racer ]; then
    gcc /vagrant/exploits/dirtycow_racer.c -o /home/attacker/exploit/dirtycow_racer -lpthread
fi

# Move to webroot (simulating upload)
cp /home/attacker/exploit/dirtycow_racer /var/www/html/dirtycow_racer
chown www-data:www-data /var/www/html/dirtycow_racer
chmod 755 /var/www/html/dirtycow_racer

echo "[*] Setup Complete."
echo "    Webshell: http://localhost:8080/exploit.php"
echo "    Exploit:  /var/www/html/dirtycow_racer"
