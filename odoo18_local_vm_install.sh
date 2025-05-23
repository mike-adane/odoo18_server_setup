#!/bin/bash
################################################################################
# Local Odoo 18 Installation Script for Ubuntu 24.04 (VMware Compatible)
################################################################################
set -euo pipefail

### Configuration
ODOO_USER="odoo"
ODOO_HOME="/opt/$ODOO_USER"
ODOO_VERSION="18.0"
DB_SUPERUSER="postgres"
DB_NAME_USER="odoo"
ADMIN_PASSWD="${ODOO_ADMIN_PASSWD:-Strong_admin_Password}"
XMLRPC_PORT=8069
LONGPOLLING_PORT=8072
CONF_FILE="/etc/odoo.conf"
LOG_DIR="/var/log/odoo"
VENV_PATH="$ODOO_HOME/venv"
DOMAIN="localhost"

### Update & Dependencies
echo "Updating system and installing dependencies..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y python3 python3-dev python3-venv python3-pip build-essential \
    libpq-dev libxml2-dev libxslt1-dev libzip-dev libldap2-dev libsasl2-dev \
    libjpeg-dev libpng-dev libffi-dev wget git curl gnupg ufw nginx

### Firewall Configuration
echo "Configuring UFW..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow "Nginx Full"
sudo ufw --force enable

### PostgreSQL Installation & User
echo "Installing PostgreSQL and creating role..."
sudo apt install -y postgresql postgresql-server-dev-all
sudo -u $DB_SUPERUSER psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_NAME_USER'" | grep -q 1 \
    || sudo -u $DB_SUPERUSER createuser -s $DB_NAME_USER

### System User & Directories
echo "Creating Odoo system user and directories..."
sudo adduser --system --home $ODOO_HOME --group --shell /bin/bash $ODOO_USER
sudo mkdir -p $ODOO_HOME/{odoo,custom_addons} $LOG_DIR
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME $LOG_DIR

### Clone Odoo Source & Virtualenv
echo "Cloning Odoo $ODOO_VERSION and setting up venv..."
sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_VERSION https://github.com/odoo/odoo.git $ODOO_HOME/odoo
sudo -u $ODOO_USER python3 -m venv $VENV_PATH
sudo -u $ODOO_USER $VENV_PATH/bin/pip install --upgrade pip wheel
sudo -u $ODOO_USER $VENV_PATH/bin/pip install -r $ODOO_HOME/odoo/requirements.txt

### wkhtmltopdf
echo "Installing wkhtmltopdf..."
sudo apt install -y wkhtmltopdf

### Odoo Configuration
echo "Creating Odoo configuration file..."
sudo tee $CONF_FILE > /dev/null <<EOF
[options]
admin_passwd = $ADMIN_PASSWD
db_host = False
db_port = False
db_user = $DB_NAME_USER
db_password = False
addons_path = $ODOO_HOME/odoo/addons,$ODOO_HOME/custom_addons
logfile = $LOG_DIR/odoo-server.log
xmlrpc_port = $XMLRPC_PORT
longpolling_port = $LONGPOLLING_PORT
proxy_mode = True
dbfilter = ^%h$
EOF
sudo chown $ODOO_USER:$ODOO_USER $CONF_FILE
sudo chmod 640 $CONF_FILE

### Systemd Service
echo "Creating systemd service for Odoo..."
sudo tee /etc/systemd/system/odoo.service > /dev/null <<EOF
[Unit]
Description=Odoo 18.0
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
PermissionsStartOnly=true
ExecStart=$VENV_PATH/bin/python3 $ODOO_HOME/odoo/odoo-bin -c $CONF_FILE
Restart=always
RestartSec=3
UMask=0027
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
MemoryMax=1G
CPUQuota=50%
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now odoo.service

### Nginx Reverse Proxy (HTTP Only)
echo "Configuring Nginx as reverse proxy (no TLS)..."
sudo tee /etc/nginx/sites-available/odoo > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$XMLRPC_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 900;
    }
}
EOF
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo
sudo nginx -t && sudo systemctl reload nginx

### Final Message
echo "-----------------------------------------------------------"
echo "Odoo 18 installed locally on your VM!"
echo "Access it at: http://localhost or http://<VM-IP>"
echo "Systemd: systemctl status odoo.service"
echo "Logs: journalctl -u odoo.service"
echo "-----------------------------------------------------------"
