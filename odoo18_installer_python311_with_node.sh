
#!/bin/bash

################################################################################
# Installer: Odoo 18 Community (No Nginx) on Ubuntu 24.04
# Best Practices with auto-detect, mail alerts, logrotate, and custom addons
################################################################################

### > CONFIGURABLE PARAMETERS < ###
OE_USER="odoo18"
OE_HOME="/opt/$OE_USER"
OE_PORT="8069"
OE_VERSION="18.0"
INSTALL_WKHTMLTOPDF="True"
IS_ENTERPRISE="False"
GENERATE_RANDOM_PASSWORD="True"
OE_DB_PASSWORD="odoo_db_pass"
DB_NAME="ethanlabs"
CPU_CORES="2"
RAM_GB="4"
AUTO_DETECT_RESOURCES="True"  # Set False to use the above CPU_CORES/RAM_GB
### > END CONFIG < ###

if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
    OE_SUPERADMIN=$(openssl rand -base64 12)
    echo "Generated random Odoo master password: $OE_SUPERADMIN"
fi

echo "🛠 Installing Odoo18 as '$OE_USER' on port $OE_PORT with Python3.12..."

sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3.11 python3.11-venv python3-pip build-essential wget mailutils
# Install Node.js from Nodesource (recommended for Odoo)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g rtlcss
 \
  python3-dev python3-setuptools libxslt-dev libzip-dev libldap2-dev libsasl2-dev \
  node-less libjpeg-dev libpq-dev libxml2-dev libssl-dev libffi-dev \
  libjpeg8-dev zlib1g-dev liblcms2-dev libblas-dev libatlas-base-dev \
  fail2ban ufw postgresql postgresql-client

sudo ufw allow OpenSSH
sudo ufw allow "$OE_PORT"/tcp
sudo ufw allow 8072/tcp
sudo ufw allow 22/tcp
sudo ufw --force enable

if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
  cd /tmp
  wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
  sudo apt install -f ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb
  sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf || true
  sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage || true
fi

if [ "$AUTO_DETECT_RESOURCES" = "True" ]; then
    CPU_CORES=$(nproc)
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    echo "🔍 Auto-detected resources: $CPU_CORES CPU cores, $RAM_GB GB RAM"
fi

WORKERS=$((CPU_CORES * 2 + 1))
MAX_CRON_THREADS=1
LIMIT_MEMORY_SOFT=$((RAM_GB * 512 * 1024 * 1024))
LIMIT_MEMORY_HARD=$((RAM_GB * 1024 * 1024 * 1024))

sudo adduser --system --home="$OE_HOME" --group "$OE_USER"
sudo -u postgres psql -c "CREATE USER $OE_USER WITH SUPERUSER PASSWORD '$OE_DB_PASSWORD';"

sudo mkdir -p "$OE_HOME"
sudo chown "$OE_USER:$OE_USER" "$OE_HOME"
cd "$OE_HOME"
sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" https://github.com/odoo/odoo .

# Create custom_addons and optional enterprise directories
echo "Creating custom_addons and optional enterprise directories..."
sudo -u "$OE_USER" mkdir -p "$OE_HOME/custom_addons"
if [ "$IS_ENTERPRISE" = "True" ]; then
    sudo -u "$OE_USER" mkdir -p "$OE_HOME/enterprise/addons"
fi
echo "Custom and Enterprise addon paths set up."

sudo -u "$OE_USER" python3.11 -m venv "$OE_HOME/venv"
sudo -u "$OE_USER" "$OE_HOME/venv/bin/pip" install wheel
sudo -u "$OE_USER" "$OE_HOME/venv/bin/pip" install -r requirements.txt

sudo mkdir -p /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

cat <<EOF | sudo tee /etc/$OE_USER.conf
[options]
admin_passwd = $OE_SUPERADMIN
db_host = False
db_port = False
db_user = $OE_USER
db_password = $OE_DB_PASSWORD
addons_path = $OE_HOME/addons,$OE_HOME/custom_addons$( [ "$IS_ENTERPRISE" = "True" ] && echo ",$OE_HOME/enterprise/addons" )
logfile = /var/log/$OE_USER/odoo.log
xmlrpc_port = $OE_PORT
gevent_port = 8072
workers = $WORKERS
bin_path = /usr/bin
max_cron_threads = $MAX_CRON_THREADS
limit_memory_soft = $LIMIT_MEMORY_SOFT
limit_memory_hard = $LIMIT_MEMORY_HARD
EOF

cat <<EOF | sudo tee /etc/systemd/system/$OE_USER.service
[Unit]
Description=Odoo $OE_VERSION Service ($OE_USER)
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$OE_USER
PermissionsStartOnly=true
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_HOME/venv/bin/python3.11 $OE_HOME/odoo-bin -c /etc/$OE_USER.conf
StandardOutput=journal+console
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now $OE_USER.service

# Post-install: logrotate and backup
cat <<EOF | sudo tee /etc/logrotate.d/$OE_USER
/var/log/$OE_USER/odoo.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 640 $OE_USER $OE_USER
}
EOF

sudo mkdir -p "$OE_HOME/backups"
sudo chown $OE_USER:$OE_USER "$OE_HOME/backups"

cat <<EOF | sudo tee /usr/local/bin/${OE_USER}_db_backup.sh
#!/bin/bash
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
FILENAME="$OE_HOME/backups/db_backup_\${TIMESTAMP}.sql.gz"
pg_dump -U $OE_USER $DB_NAME | gzip > \$FILENAME
find $OE_HOME/backups -type f -name "*.sql.gz" -mtime +14 -exec rm {} \;
echo "Backup done: \$FILENAME" | mail -s "Odoo Backup Success - \$TIMESTAMP" mikead7@gmail.com
EOF
sudo chmod +x /usr/local/bin/${OE_USER}_db_backup.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/${OE_USER}_db_backup.sh") | crontab -

echo "✅ Odoo $OE_VERSION CE installed with custom_addons and auto-detected settings!"
