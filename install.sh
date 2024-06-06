#!/bin/bash
echo -e '\033[34m#################################################
#\033[33m                                               \033[34m#
#\033[33m    Установка Asterisk & FreePBX на Ubuntu     \033[34m#
#\033[33m                                               \033[34m#
#\033[33m      Запускайте скрипт только от root!!       \033[34m#
#################################################\033[0m'

# set -e
SCRIPTVER="0.4.4"
# Changelog:
# Поправки ошибок + фаерволл + изменен webroot
# добавил неинтерактивный режим
# автостоп rinetd
# CDR Viewer MOD + ошибки
export DEBIAN_FRONTEND=noninteractive
ASTVERSION=18
PHPVERSION="7.4"
LOG_FOLDER="/var/log/pbx"
LOG_FILE="${LOG_FOLDER}/freepbx16-install-$(date '+%Y.%m.%d-%H.%M.%S').log"
DISTRIBUTION="$(lsb_release -is)"
log=$LOG_FILE
# Переменные
namepbx=newpbx3
codename=noble
WEBROOT="/var/www/html/pbx"
WORK_DIR=$(pwd)
IP_ADDR=$(hostname -I)
color="\033[0;33m"
nocolor="\033[0m"

echo -e "\033[0;31mЖелаешь сам поправить MenuSelect? [Y/n]${nocolor}"
read MENUSELECT_EDIT

echo -e "${color}Проверяем root"
echo "User is ${USER}"

echo -e "${color}Меняем хостнейм на ${namepbx}"
sudo hostname ${namepbx}
echo -e "${color}Обновляем систему${nocolor}"
sudo apt-get update && apt-get upgrade -y

echo -e "${color}Устанавливаем сетевые утилиты"
sudo apt install iputils-ping nmap net-tools tcpdump sngrep rinetd -y
echo -e "${color}Дополнительные утилиты:${nocolor}"
sudo apt install sox mpg123 cron mc openvpn fail2ban tftpd-hpa git htop iptables -y

echo -e "${color}Устанавливаем PHP7.4 + Apache2${nocolor}"
sudo apt install software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt install php7.4 php7.4-{cli,common,curl,zip,gd,mysql,xml,mbstring,json,intl} -y

echo -e "${color}Поправка конфига Апача${nocolor}"
useradd -m asterisk
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 120M/g' /etc/php/7.4/apache2/php.ini
cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf_orig 
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf 
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf 
a2enmod rewrite 
echo -e "${color}В /etc/apache2/envvars исправляем пользователя на asterisk:${nocolor}"
sed -i 's/^\(export APACHE_RUN_USER=\|export APACHE_RUN_GROUP=\).*/\1 asterisk/' /etc/apache2/envvars 
systemctl restart apache2
echo -e "${color} > Установка Asterisk${nocolor}"
echo -e "\033[0;34m------------------------------${nocolor}"
cd /usr/src/
wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTVERSION}-current.tar.gz
tar xzf asterisk*
cd asterisk-18.*
echo -e "${color}Установка зависимостей Asterisk${nocolor}"
contrib/scripts/install_prereq install
./configure --with-pjproject-bundled --with-jansson-bundled
echo -e "${color}Подменяем menuselect своим${nocolor}"
cp ${WORK_DIR}/usr/src/asterisk/menuselect.makedeps /usr/src/asterisk-*
cp ${WORK_DIR}/usr/src/asterisk/menuselect.makeopts /usr/src/asterisk-*

if [[ "${MENUSELECT_EDIT}" == "Y" ]]; then
    echo -e "${color}И проверяем${nocolor}"
    make menuselect
    echo -e "${color}Не забыл включить app_macro и языковые файлы?"
    echo -e "${color}И отключить лишнее!${nocolor}"
fi

echo -e "${color} > Приступаю к сборке Asterisk${nocolor}"
echo -e "\033[0;34m------------------------------${nocolor}"
make
make install
make config
ldconfig

echo -e "${color}Выставляем права на каталоги Asterisk${nocolor}"
chown -R asterisk: /var/run/asterisk 
chown -R asterisk: /etc/asterisk 
chown -R asterisk: /var/{lib,log,spool}/asterisk 
chown -R asterisk: /usr/lib/asterisk

# Вставить в 
echo -e "${color}Поправка конфига asterisk.conf${nocolor}"
cat << EOF >> /etc/asterisk/asterisk.conf
[directories]
astetcdir => /etc/asterisk
astmoddir => /usr/lib/asterisk/modules
astvarlibdir => /var/lib/asterisk
astagidir => /var/lib/asterisk/agi-bin
astspooldir => /var/spool/asterisk
astrundir => /var/run/asterisk
astlogdir => /var/log/asterisk
[options]
verbose = 2
runuser = asterisk              ; The user to run as. The default is root.
rungroup = asterisk             ; The group to run as. The default is root
defaultlanguage = ru
EOF

echo -e "${color}Install MariaDB Connector${nocolor}"
cd /usr/src/
wget https://dlm.mariadb.com/3680402/Connectors/odbc/connector-odbc-3.1.20/mariadb-connector-odbc-3.1.20-ubuntu-jammy-amd64.deb
dpkg -i mariadb-connector-odbc*
sleep 10
apt install mariadb-server mariadb-client galera-4 -y
apt install unixodbc-dev unixodbc -y

echo -e "${color}Поправка конфигов ODBC${nocolor}"
cat << EOF >> /etc/odbcinst.ini
[MariaDB]
Description = ODBC for MariaDB
Driver = /usr/lib/x86_64-linux-gnu/libmaodbc.so
Setup = /usr/lib/x86_64-linux-gnu/libmaodbc.so
FileUsage = 1
[MariaDB Unicode]
Driver=libmaodbc.so
Description=MariaDB Connector/ODBC(Unicode)
Threading=0
UsageCount=1
EOF

cat << EOF >> /etc/odbc.ini 
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
driver=MariaDB
server=localhost
database=asteriskcdrdb
Port=3306
Socket=/var/run/mysqld/mysqld.sock
option=3
Charset=utf8
EOF

# Для нормальной работы БД добавляем в файл 
echo -e "${color}Поправка конфига mariadb${nocolor}"
cat << EOF >> /etc/mysql/conf.d/mysql.cnf
[mysqld]
sql_mode=NO_ENGINE_SUBSTITUTION
EOF

echo -e "${color}Установка nodeJS${nocolor}"

curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash - 
apt-get install -y nodejs
apt install npm -y
echo -e "${color} > Установка FreePBX${nocolor}"
echo -e "\033[0;34m----------------------${nocolor}"
cd /usr/src 
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-16.0-latest.tgz 
tar xfz freepbx-16.0-latest.tgz
touch /etc/asterisk/{modules,cdr}.conf 
cd freepbx 
./start_asterisk start 
./install -n --webroot=${WEBROOT}
chown -R asterisk: ${WEBROOT}
fwconsole ma install pm2
echo -e "${color}Установка модулей FreePBX${nocolor}"
fwconsole ma downloadinstall userman bulkhandler blacklist calendar cel cdr
fwconsole ma downloadinstall timeconditions findmefollow backup featurecodeadmin announcement ringgroups customcontexts iaxsettings
fwconsole reload --verbose

echo -e "${color}Установка русскоязычного расширенного языкового пакета${nocolor}"
cd /usr/src/
wget https://github.com/pbxware/asterisk-sounds-additional/archive/refs/heads/master.zip -O asterisk-sounds-additional.zip
unzip -q asterisk-sounds-additional.zip
mv -f asterisk-sounds-additional-master/* /var/lib/asterisk/sounds/ru/
chown -R asterisk: /var/lib/asterisk/sounds

echo -e "${color} > Установка CDR Viewer MOD${nocolor}"
echo -e "\033[0;34m-----------------------------${nocolor}"
cd /usr/src/
git clone https://github.com/atsip-ru/Asterisk-CDR-Viewer-Mod.git
mv Asterisk-CDR-Viewer-Mod/ ${WEBROOT}/cdr
cp ${WEBROOT}/cdr/inc/config/config.php.sample ${WEBROOT}/cdr/inc/config/config.php

# db_user -> $amp_conf['AMPDBUSER'] = 'freepbxuser';

DBUSER=`cat /etc/freepbx.conf | sed 's/ //g' | grep AMPDBUSER | tail -n 1 | cut -d= -f2 `
DBUSER=${DBUSER:1}
DBUSER=${DBUSER%??}
sed -i "s/db_user/${DBUSER}/"  ${WEBROOT}/cdr/inc/config/config.php

# db_name -> asteriskcdrdb
sed -i "s/db_name/asteriskcdrdb/"  ${WEBROOT}/cdr/inc/config/config.php
# db_password -> $amp_conf['AMPDBPASS'] = 'c92b9be40d29bbef491ee08057fe889a';

DBPASS=`cat /etc/freepbx.conf | sed 's/ //g' | grep AMPDBPASS | tail -n 1 | cut -d= -f2- `
DBPASS=${DBPASS:1}
DBPASS=${DBPASS%??}
sed -i "s/db_password/${DBPASS}/"  ${WEBROOT}/cdr/inc/config/config.php

echo -e "${color}Задайте пароль для CDR Viewer MOD пользователю admin"
htpasswd -c ${WEBROOT}/cdr/.htpasswd admin

cat << EOF >> /etc/apache2/apache2.conf
<Location "${WEBROOT}/cdr">
	AuthName "CDR Viewer Mod"
	AuthType Basic
	AuthUserFile ${WEBROOT}/cdr/.htpasswd
	require valid-user
</Location>
EOF

echo -e "${color}Установка настроек фаерволла${nocolor}"
cp ${WORK_DIR}/root/iptables-firewall.sh /root/iptables-firewall.sh
chmod +x /root/iptables-firewall.sh
ln -s /root/iptables-firewall.sh /sbin/iptables-firewall.sh

cat << EOF >> /etc/systemd/system/iptables-firewall.service
[Unit]
Description=iptables firewall service
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-firewall.sh start
RemainAfterExit=true
ExecStop=/sbin/iptables-firewall.sh stop
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now iptables-firewall

echo -e "${color}Ограничение времени работы rinetd${nocolor}"
mkdir -p /etc/systemd/system/rinetd.service.d/
echo << EOF >> /etc/systemd/system/rinetd.service.d/override.conf
[Service]
RuntimeMaxSec=1800
EOF

echo -e "${color}Преднастройка TFTP${nocolor}"
sudo sed -i 's/^TFTP_DIRECTORY=.*/TFTP_DIRECTORY="\/tftpboot"/'  /etc/default/tftpd-hpa
mkdir /tftpboot
cd /tftpboot
ln -s y000000000053.cfg y000000000127.cfg
chown -R nobody:nogroup /tftpboot

cp ${WORK_DIR}/etc/update-motd.d/99-intelcom /etc/update-motd.d/
mv ${WORK_DIR}/var/www/html/index.html ${WEBROOT}
mv ${WORK_DIR}/var/www/html/mainstyle.css ${WEBROOT}
mv ${WORK_DIR}/var/www/html/admin/images/atsip.ru.png ${WEBROOT}/admin/images/
mv ${WORK_DIR}/etc/cron.daily/rmwav.sh /etc/cron.daily/
mv ${WORK_DIR}/etc/cron.daily/vm-auto-delete.sh /etc/cron.daily/

#find /var/lib/asterisk/sounds/ -type f -name "*.g722" -delete

chown -R asterisk: ${WEBROOT}

echo -e "\033[34m########################################################
#\033[33m                                                      \033[34m#
#\033[33m Поздравляем с успешной установкой Asterisk и FreePBX \033[34m#
#\033[33m Не забудь сменить пароль root для mariadb            \033[34m#
#\033[33m Донастрой АТС по адресу http://${IP_ADDR}/pbx/admin/\033[34m#
########################################################\033[0m"

{
echo "              _       _                   "
echo "         __ _| |_ ___(_)_ __   _ __ _   _ "
echo "        / _\` | __/ __| | '_ \ | '__| | | |"
echo "       | (_| | |_\__ \ | |_) || |  | |_| |"
echo "        \__,_|\__|___/_| .__(_)_|   \__,_|"
echo "                       |_|                "
}
