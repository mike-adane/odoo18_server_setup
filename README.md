
# Odoo 18 CE Installer for Ubuntu 24.04

A fully-automated bash script to install **Odoo 18 Community** (no Nginx) on Ubuntu 24.04 LTS, including:

- Python 3.12 venv
- PostgreSQL setup
- Systemd service
- UFW firewall rules
- wkhtmltopdf for PDF reports
- Automated log rotation
- Daily database backups with email alerts
- Auto-detect CPU/RAM and optimize worker settings
- Optional enterprise addons

---

## 📋 Prerequisites

- Ubuntu 24.04 LTS (fresh install recommended)
- Internet access from the VM
- `sudo` privileges

---

## ⚙️ Configuration

Edit the top of the script to customize:

```bash
OE_USER="odoo18"
OE_HOME="/opt/$OE_USER"
OE_PORT="8069"
OE_VERSION="18.0"
INSTALL_WKHTMLTOPDF="True"
IS_ENTERPRISE="False"
GENERATE_RANDOM_PASSWORD="True"
OE_DB_PASSWORD="odoo_db_pass"
DB_NAME="ethanlabs"

# Resource detection
CPU_CORES="2"
RAM_GB="4"
AUTO_DETECT_RESOURCES="True"
```

- **`AUTO_DETECT_RESOURCES`**: set to `False` to use manual `CPU_CORES`/`RAM_GB`.
- If installing **Enterprise**, set `IS_ENTERPRISE="True"` and clone your private repo.

---

## 🚀 Installation

1. **Download** the script:  
   ```bash
   wget https://…/final_odoo18_installer_with_mailutils.sh
   ```

2. **Make executable** and run:
   ```bash
   chmod +x final_odoo18_installer_with_mailutils.sh
   sudo ./final_odoo18_installer_with_mailutils.sh
   ```

3. **Access Odoo** at  
   `http://<VM-IP>:8069` or `http://localhost:8069`

---

## 🔄 Log Rotation & Backups

- Logs rotate weekly, 8 archives kept: `/var/log/odoo18/odoo.log`
- Daily DB backups at 2 AM to: `/opt/odoo18/backups/`
- Success emails sent to: `mikead7@gmail.com`

---

## 🔧 Maintenance & Tips

- To adjust backup retention, modify the `find … -mtime +14` line.
- For SMTP customization, configure `/etc/mail.rc` or install `ssmtp`.
- To run multiple instances, duplicate the script with different ports and users.

---

## 📜 License

MIT © Your Name
