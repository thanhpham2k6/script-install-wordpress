#!/bin/bash

# WordPress Auto-Install Script
# This script installs WordPress with LAMP stack on Ubuntu/Debian

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== WordPress Auto-Install Script ===${NC}\n"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Get user input
read -p "Enter domain name (e.g., example.com): " DOMAIN
read -p "Enter database name: " DB_NAME
read -p "Enter database user: " DB_USER
read -sp "Enter database password: " DB_PASS
echo
read -p "Enter WordPress admin username: " WP_ADMIN
read -sp "Enter WordPress admin password: " WP_PASS
echo
read -p "Enter WordPress admin email: " WP_EMAIL

WEB_ROOT="/var/www/$DOMAIN"

echo -e "\n${YELLOW}Starting installation...${NC}\n"

# Update system
echo -e "${GREEN}[1/8] Updating system packages...${NC}"
apt update && apt upgrade -y

# Install Apache
echo -e "${GREEN}[2/8] Installing Apache...${NC}"
apt install apache2 -y
systemctl start apache2
systemctl enable apache2

# Install MySQL
echo -e "${GREEN}[3/8] Installing MySQL...${NC}"
apt install mysql-server -y
systemctl start mysql
systemctl enable mysql

# Install PHP
echo -e "${GREEN}[4/8] Installing PHP and extensions...${NC}"
apt install php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip -y

# Create database
echo -e "${GREEN}[5/8] Creating MySQL database...${NC}"
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Download WordPress
echo -e "${GREEN}[6/8] Downloading WordPress...${NC}"
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz

# Move WordPress files
echo -e "${GREEN}[7/8] Setting up WordPress files...${NC}"
mkdir -p $WEB_ROOT
cp -r /tmp/wordpress/* $WEB_ROOT/
chown -R www-data:www-data $WEB_ROOT
chmod -R 755 $WEB_ROOT

# Configure WordPress
cd $WEB_ROOT
cp wp-config-sample.php wp-config.php

sed -i "s/database_name_here/$DB_NAME/" wp-config.php
sed -i "s/username_here/$DB_USER/" wp-config.php
sed -i "s/password_here/$DB_PASS/" wp-config.php

# Generate unique salts
curl -s https://api.wordpress.org/secret-key/1.1/salt/ > /tmp/wp-salts.txt

# Replace the salt section
sed -i "/AUTH_KEY/,/NONCE_SALT/d" wp-config.php
sed -i "/^define( 'DB_COLLATE'/r /tmp/wp-salts.txt" wp-config.php

# Configure Apache
echo -e "${GREEN}[8/8] Configuring Apache...${NC}"
cat > /etc/apache2/sites-available/$DOMAIN.conf <<EOF
<VirtualHost *:80>
    ServerAdmin $WP_EMAIL
    ServerName $DOMAIN
    DocumentRoot $WEB_ROOT

    <Directory $WEB_ROOT>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF

a2ensite $DOMAIN.conf
a2enmod rewrite
a2dissite 000-default.conf
systemctl restart apache2

# Install WP-CLI for completing setup
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Complete WordPress installation
cd $WEB_ROOT
sudo -u www-data wp core install --url="http://$DOMAIN" --title="WordPress Site" --admin_user="$WP_ADMIN" --admin_password="$WP_PASS" --admin_email="$WP_EMAIL"

# Clean up
rm -rf /tmp/wordpress /tmp/latest.tar.gz

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}WordPress installation completed!${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "\nSite URL: ${YELLOW}http://$DOMAIN${NC}"
echo -e "Admin URL: ${YELLOW}http://$DOMAIN/wp-admin${NC}"
echo -e "Username: ${YELLOW}$WP_ADMIN${NC}"
echo -e "\nDatabase: ${YELLOW}$DB_NAME${NC}"
echo -e "DB User: ${YELLOW}$DB_USER${NC}"
echo -e "\n${YELLOW}Note: Configure DNS to point $DOMAIN to this server's IP${NC}"
echo -e "${YELLOW}Consider installing SSL certificate with certbot/Let's Encrypt${NC}\n"
