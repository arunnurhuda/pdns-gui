#!/bin/bash

# Update package list and install necessary dependencies
sudo apt update
sudo apt install -y git curl wget build-essential software-properties-common

# Install MariaDB server (as PowerDNS backend)
sudo apt install -y mariadb-server mariadb-client

# Secure MariaDB installation
sudo mysql_secure_installation

# Login to MariaDB and create a database and user for PowerDNS
sudo mysql -u root -p -e "
CREATE DATABASE powerdns;
CREATE USER 'powerdns'@'localhost' IDENTIFIED BY 'powerdns_password';
GRANT ALL PRIVILEGES ON powerdns.* TO 'powerdns'@'localhost';
FLUSH PRIVILEGES;
"

# Install PowerDNS and PowerDNS dependencies
sudo apt install -y pdns-server pdns-backend-mysql

# Configure PowerDNS to use MySQL backend
sudo tee /etc/powerdns/pdns.conf > /dev/null <<EOL
launch=gmysql
gmysql-host=localhost
gmysql-port=3306
gmysql-dbname=powerdns
gmysql-user=powerdns
gmysql-password=powerdns_password
EOL

# Download PowerDNS schema and import into the database
wget https://raw.githubusercontent.com/PowerDNS/pdns/master/modules/gmysqlbackend/schema.sql
sudo mysql -u root -p powerdns < schema.sql

# Restart PowerDNS service
sudo systemctl restart pdns

# Install PowerDNS Admin dependencies
sudo apt install -y python3 python3-dev python3-venv python3-pip libmysqlclient-dev libffi-dev libssl-dev

# Clone PowerDNS Admin repository
git clone https://github.com/ngoduykhanh/PowerDNS-Admin.git /opt/powerdns-admin

# Change directory to PowerDNS Admin
cd /opt/powerdns-admin

# Create a Python virtual environment
python3 -m venv /opt/powerdns-admin/venv

# Activate the virtual environment
source /opt/powerdns-admin/venv/bin/activate

# Install required Python packages
pip install wheel
pip install -r requirements.txt

# Copy the sample configuration file and edit it
cp /opt/powerdns-admin/configs/config_template.py /opt/powerdns-admin/config.py
sed -i "s/sqlalchemy_database_uri = 'sqlite:\/\/\/.*'/sqlalchemy_database_uri = 'mysql+pymysql:\/\/powerdns:powerdns_password@localhost\/powerdns'/g" /opt/powerdns-admin/config.py
sed -i "s/# SECRET_KEY = '.*'/SECRET_KEY = 'your_secret_key'/g" /opt/powerdns-admin/config.py
sed -i "s/# BIND_ADDRESS = '127.0.0.1'/BIND_ADDRESS = '0.0.0.0'/g" /opt/powerdns-admin/config.py

# Initialize the database
export FLASK_APP=powerdnsadmin/__init__.py
flask db upgrade

# Create a systemd service for PowerDNS Admin
sudo tee /etc/systemd/system/powerdns-admin.service > /dev/null <<EOL
[Unit]
Description=PowerDNS-Admin
After=network.target

[Service]
User=root
Group=www-data
WorkingDirectory=/opt/powerdns-admin
Environment="PATH=/opt/powerdns-admin/venv/bin"
ExecStart=/opt/powerdns-admin/venv/bin/gunicorn -b 0.0.0.0:9191 -w 4 "powerdnsadmin:create_app()"

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start PowerDNS Admin service
sudo systemctl daemon-reload
sudo systemctl enable powerdns-admin
sudo systemctl start powerdns-admin

# Print completion message
echo "PowerDNS and PowerDNS Admin have been successfully installed."
echo "PowerDNS Admin is running on http://<your_server_ip>:9191"
