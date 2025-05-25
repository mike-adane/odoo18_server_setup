
#!/bin/bash

################################################################################
# Installer: Odoo 18 Community (No Nginx) on Ubuntu 24.04
# Best Practices from Cybrosys + Yenthe666
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
AUTO_DETECT_RESOURCES="True"  # Set to False to use manual CPU_CORES and RAM_GB values
DB_NAME="ethanlabs"
# If GENERATE_RANDOM_PASSWORD is False, original OE_SUPERADMIN used
OE_SUPERADMIN="admin"

### > END CONFIG < ###

# AUTO-GENERATE SUPERADMIN IF REQUESTED
if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
    OE_SUPERADMIN=$(openssl rand -base64 12)
    echo "Generated random Odoo master password: $OE_SUPERADMIN"
fi

echo "🛠 Installing Odoo18 as '$OE_USER' on port $OE_PORT with Python3.12..."

# UPDATE SYSTEM
sudo apt update && sudo apt upgrade -y

# INSTALL DEPENDENCIES
sudo apt install -y git python3.12 python3.12-venv python3-pip build-essential wget   python3-dev libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools   node-less libjpeg-dev libpq-dev libxml2-dev libssl-dev libffi-dev   libjpeg8-dev zlib1g-dev liblcms2-dev libblas-dev libatlas-base-dev fail2ban ufw

# SETUP UFW
sudo ufw allow OpenSSH
sudo ufw allow "$OE_PORT"/tcp
sudo ufw --force enable

# INSTALL wkhtmltopdf (IF ENABLED)
if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
    cd /tmp
    wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6.1/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
    sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb || sudo apt install -f -y
fi

# CREATE SYSTEM USER
sudo adduser --system --home="$OE_HOME" --group "$OE_USER"

# INSTALL POSTGRESQL AND CREATE DB USER
sudo apt install -y postgresql
sudo -u postgres psql -c "CREATE USER $OE_USER WITH SUPERUSER PASSWORD '$OE_DB_PASSWORD';"

# CLONE ODOO SOURCE
sudo mkdir -p "$OE_HOME"
sudo chown "$OE_USER:$OE_USER" "$OE_HOME"
cd "$OE_HOME"
sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" https://www.github.com/odoo/odoo .

# ADD ENTERPRISE ADDONS (IF ENABLED)
if [ "$IS_ENTERPRISE" = "True" ]; then
    sudo -u "$OE_USER" mkdir -p "$OE_HOME/enterprise/addons"
    # (User would need to provide enterprise repo access or private clone)
    # sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" <enterprise-repo-url> "$OE_HOME/enterprise/addons"
fi

# SETUP PYTHON VENV
sudo -u "$OE_USER" python3.12 -m venv "$OE_HOME/venv"
sudo -u "$OE_USER" "$OE_HOME/venv/bin/pip" install wheel
sudo -u "$OE_USER" "$OE_HOME/venv/bin/pip" install -r requirements.txt

# LOGGING DIRECTORY
sudo mkdir -p /var/log/"$OE_USER"
sudo chown "$OE_USER:$OE_USER" /var/log/"$OE_USER"



# Detect CPU and RAM if enabled
if [ "$AUTO_DETECT_RESOURCES" = "True" ]; then
    CPU_CORES=$(nproc)
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    echo "🔍 Auto-detected resources: $CPU_CORES CPU cores, $RAM_GB GB RAM"
fi

# Calculate optimal workers and limits
WORKERS=$((CPU_CORES * 2 + 1))
MAX_CRON_THREADS=1
LIMIT_MEMORY_SOFT=$((RAM_GB * 512 * 1024 * 1024))
LIMIT_MEMORY_HARD=$((RAM_GB * 1024 * 1024 * 1024))

echo "🔢 Calculated $WORKERS workers for $CPU_CORES CPU cores and $RAM_GB GB RAM."

WORKERS=$((CPU_CORES * 2 + 1))
MAX_CRON_THREADS=1
LIMIT_MEMORY_SOFT=$((RAM_GB * 512 * 1024 * 1024))
LIMIT_MEMORY_HARD=$((RAM_GB * 1024 * 1024 * 1024))

echo "🔢 Calculated $WORKERS workers for $CPU_CORES CPU cores and $RAM_GB GB RAM."


# CONFIG FILE /etc/odoo18.conf
cat <<EOF | sudo tee /etc/"$OE_USER".conf
[options]
admin_passwd = $OE_SUPERADMIN
db_host = False
db_port = False
db_user = $OE_USER
db_password = $OE_DB_PASSWORD
addons_path = $OE_ADDONS_PATH
logfile = /var/log/$OE_USER/odoo.log
xmlrpc_port = $OE_PORT
workers = $WORKERS
max_cron_threads = $MAX_CRON_THREADS
limit_memory_soft = $LIMIT_MEMORY_SOFT
limit_memory_hard = $LIMIT_MEMORY_HARD
EOF
[options]
admin_passwd = $OE_SUPERADMIN
db_host = False
db_port = False
db_user = $OE_USER
db_password = $OE_DB_PASSWORD
addons_path = $OE_HOME/addons$( [ "$IS_ENTERPRISE" = "True" ] && echo ",$OE_HOME/enterprise/addons" )
logfile = /var/log/$OE_USER/odoo.log
xmlrpc_port = $OE_PORT
EOF

# SYSTEMD SERVICE
cat <<EOF | sudo tee /etc/systemd/system/"$OE_USER".service
[Unit]
Description=Odoo18 ($OE_USER)
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$OE_USER
PermissionsStartOnly=true
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_HOME/venv/bin/python3.12 $OE_HOME/odoo-bin -c /etc/$OE_USER.conf
StandardOutput=journal+console
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# FINAL STEPS
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now "$OE_USER"

echo "✅ Odoo 18 CE installed!"
echo "- Master password: $OE_SUPERADMIN"
echo "- Access at: http://<VM-IP>:$OE_PORT or http://localhost:$OE_PORT"


# ============================
# 📦 POST-INSTALL ENHANCEMENTS
# ============================

echo "🔧 Setting up log rotation for /var/log/$OE_USER/odoo.log..."

# Create logrotate config
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

sudo chmod 644 /etc/logrotate.d/$OE_USER
echo "✅ Logrotate configuration installed at /etc/logrotate.d/$OE_USER"

echo "💾 Setting up daily database backup script for user $OE_USER..."

# Create backup directory
sudo mkdir -p "$OE_HOME/backups"
sudo chown $OE_USER:$OE_USER "$OE_HOME/backups"

# Create backup script
BACKUP_SCRIPT_PATH="/usr/local/bin/${OE_USER}_db_backup.sh"
sudo tee $BACKUP_SCRIPT_PATH > /dev/null <<EOF
#!/bin/bash
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
FILENAME="$OE_HOME/backups/db_backup_\${TIMESTAMP}.sql.gz"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
FILENAME="$OE_HOME/backups/db_backup_\${TIMESTAMP}.sql.gz"
pg_dump -U $OE_USER $DB_NAME | gzip > \$FILENAME
find $OE_HOME/backups -type f -name "*.sql.gz" -mtime +14 -exec rm {} \;

# Email alert
echo "Odoo DB backup completed: \$FILENAME" | mail -s "Odoo Backup Success - \$TIMESTAMP" mikead7@gmail.com
EOF

sudo chmod +x $BACKUP_SCRIPT_PATH

# Add to crontab for 2:00 AM daily backups
(crontab -l 2>/dev/null; echo "0 2 * * * $BACKUP_SCRIPT_PATH") | crontab -

echo "✅ Cron job added: Daily DB backup at 2:00 AM"
echo "📁 Backups stored in: $OE_HOME/backups"
