#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: onionrings29
# License: MIT | https://github.com/onionrings29/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rommapp/romm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  make \
  gcc \
  g++ \
  mariadb-server \
  libmariadb3 \
  libmariadb-dev \
  libpq-dev \
  libffi-dev \
  musl-dev \
  curl \
  ca-certificates \
  libmagic-dev \
  p7zip-full \
  tzdata \
  libbz2-dev \
  libssl-dev \
  libreadline-dev \
  libsqlite3-dev \
  zlib1g-dev \
  liblzma-dev \
  libncurses5-dev \
  libncursesw5-dev
msg_ok "Installed Dependencies"

msg_info "Setting up MariaDB Database"
DB_NAME=romm
DB_USER=romm_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mysql -u root -e "CREATE DATABASE $DB_NAME;"
$STD mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
$STD mysql -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "ROMM Database Credentials"
  echo "Database: $DB_NAME"
  echo "Username: $DB_USER"
  echo "Password: $DB_PASS"
} >>~/romm.creds
msg_ok "Set up MariaDB Database"

NODE_VERSION="18" setup_nodejs
setup_uv

msg_info "Building RAHasher (for RetroAchievements)"
cd /tmp
git clone --recursive --branch 1.8.1 --depth 1 https://github.com/RetroAchievements/RALibretro.git
cd RALibretro
sed -i '22a #include <ctime>' ./src/Util.h
sed -i '6a #include <unistd.h>' \
  ./src/libchdr/deps/zlib-1.3.1/gzlib.c \
  ./src/libchdr/deps/zlib-1.3.1/gzread.c \
  ./src/libchdr/deps/zlib-1.3.1/gzwrite.c
$STD make HAVE_CHD=1 -f ./Makefile.RAHasher
cp ./bin64/RAHasher /usr/bin/RAHasher
chmod +x /usr/bin/RAHasher
cd /tmp
rm -rf RALibretro
msg_ok "Built RAHasher"

msg_info "Cloning ROMM Repository"
cd /opt
git clone https://github.com/rommapp/romm.git
cd romm
msg_ok "Cloned ROMM Repository"

msg_info "Installing Python Dependencies"
/usr/local/bin/uv python install 3.13
/usr/local/bin/uv sync --all-extras
msg_ok "Installed Python Dependencies"

msg_info "Installing Frontend Dependencies"
cd /opt/romm/frontend
$STD npm install
msg_ok "Installed Frontend Dependencies"

msg_info "Creating Environment Configuration"
mkdir -p /opt/romm_storage/library
mkdir -p /opt/romm_storage/resources
mkdir -p /opt/romm_storage/redis-data

cat <<EOF >/opt/romm/.env
# Database Configuration
DB_HOST=localhost
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWD=$DB_PASS

# ROMM Configuration
ROMM_AUTH_SECRET_KEY=$(openssl rand -base64 32)
ROMM_BASE_PATH=/romm

# Optional Configuration
DISABLE_CSRF_PROTECTION=false
EOF

chmod 600 /opt/romm/.env
msg_ok "Created Environment Configuration"

msg_info "Creating Systemd Service"
cat <<EOF >/etc/systemd/system/romm.service
[Unit]
Description=ROMM ROM Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/romm/backend
EnvironmentFile=/opt/romm/.env
Environment="DEV_HOST=0.0.0.0"
Environment="DEV_PORT=8080"
ExecStart=/opt/romm/.venv/bin/python main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now romm
msg_ok "Created Systemd Service"

motd_ssh
customize
cleanup_lxc
