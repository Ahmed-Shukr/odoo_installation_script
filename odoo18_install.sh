#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 16.04, 18.04, 20.04 and 22.04
# Author: Yenthe Van Ginneken (modified ONLY for Odoo 18 compatibility)
#-------------------------------------------------------------------------------
# This script installs Odoo and supports multiple instances via different ports
################################################################################

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"

INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"

# =========================
# ODOO 18 CHANGE
# =========================
OE_VERSION="18.0"

IS_ENTERPRISE="False"

# PostgreSQL 16 recommended for Odoo 18
INSTALL_POSTGRESQL_FOURTEEN="True"

INSTALL_NGINX="False"

OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"

WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"

ENABLE_SSL="True"
ADMIN_EMAIL="odoo@example.com"

# =========================
# WKHTMLTOPDF (0.12.6)
# =========================
WKHTMLTOX_X64="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.jammy_amd64.deb"
WKHTMLTOX_X32="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.jammy_i386.deb"

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install libpq-dev -y

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Install PostgreSQL Server ----"
if [ $INSTALL_POSTGRESQL_FOURTEEN = "True" ]; then
    echo -e "\n---- Installing PostgreSQL 16 (Odoo 18 compatible) ----"
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    sudo apt-get update
    sudo apt-get install postgresql-16 postgresql-server-dev-16 -y
else
    sudo apt-get install postgresql postgresql-server-dev-all -y
fi

echo -e "\n---- Creating PostgreSQL user ----"
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
echo -e "\n---- Installing system dependencies ----"
sudo apt-get install -y \
  python3 python3-pip python3-dev python3-venv \
  git build-essential wget \
  libxslt-dev libzip-dev libldap2-dev libsasl2-dev \
  libjpeg-dev libpng-dev gdebi

#--------------------------------------------------
# Python Requirements (Odoo 18)
#--------------------------------------------------
echo -e "\n---- Installing Python requirements ----"
sudo -H pip3 install -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt

#--------------------------------------------------
# NodeJS (Odoo 18 requires Node 18)
#--------------------------------------------------
echo -e "\n---- Installing NodeJS 18 ----"
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g rtlcss

#--------------------------------------------------
# Install wkhtmltopdf
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Installing wkhtmltopdf ----"
  if [ "`getconf LONG_BIT`" == "64" ];then
      _url=$WKHTMLTOX_X64
  else
      _url=$WKHTMLTOX_X32
  fi
  sudo wget $_url
  sudo gdebi --n `basename $_url`
  sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin
  sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin
fi

#--------------------------------------------------
# Create Odoo User
#--------------------------------------------------
echo -e "\n---- Create Odoo system user ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
sudo adduser $OE_USER sudo

#--------------------------------------------------
# Logs
#--------------------------------------------------
sudo mkdir /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Install Odoo
#--------------------------------------------------
echo -e "\n==== Installing Odoo 18 ===="
sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/

#--------------------------------------------------
# Enterprise (unchanged)
#--------------------------------------------------
if [ $IS_ENTERPRISE = "True" ]; then
    sudo -H pip3 install psycopg2-binary pdfminer.six
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    sudo su $OE_USER -c "mkdir -p $OE_HOME/enterprise/addons"
    sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons"
    sudo -H pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo npm install -g less less-plugin-clean-css
fi

#--------------------------------------------------
# Custom addons
#--------------------------------------------------
sudo su $OE_USER -c "mkdir -p $OE_HOME/custom/addons"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*

#--------------------------------------------------
# Config file
#--------------------------------------------------
sudo touch /etc/${OE_CONFIG}.conf

if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    OE_SUPERADMIN=$(openssl rand -hex 16)
fi

sudo tee /etc/${OE_CONFIG}.conf > /dev/null <<EOF
[options]
admin_passwd = $OE_SUPERADMIN
http_port = $OE_PORT
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
addons_path = $OE_HOME_EXT/addons,$OE_HOME/custom/addons
EOF

sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

#--------------------------------------------------
# Init.d service (unchanged)
#--------------------------------------------------
cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$network \$remote_fs
# Required-Stop: \$network \$remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
### END INIT INFO

DAEMON=$OE_HOME_EXT/odoo-bin
USER=$OE_USER
CONFIGFILE="/etc/${OE_CONFIG}.conf"
PIDFILE=/var/run/\${NAME}.pid

start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- -c \$CONFIGFILE
EOF

sudo mv ~/$OE_CONFIG /etc/init.d/$OE_CONFIG
sudo chmod 755 /etc/init.d/$OE_CONFIG
sudo update-rc.d $OE_CONFIG defaults

#--------------------------------------------------
# Nginx (UNCHANGED – kept exactly)
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ]; then
  sudo apt install nginx -y
  sudo service nginx reload
  sudo tee -a /etc/${OE_CONFIG}.conf <<< "proxy_mode = True"
fi

#--------------------------------------------------
# Start Odoo
#--------------------------------------------------
sudo service $OE_CONFIG start

echo "-----------------------------------------------------------"
echo "Odoo 18 is running"
echo "Port: $OE_PORT"
echo "Config: /etc/${OE_CONFIG}.conf"
echo "Admin password: $OE_SUPERADMIN"
echo "-----------------------------------------------------------"
