#!/bin/bash
##############################################################################
# * Copyright 2024 by Atsip.ru (Intelcom LLC)                                #
# This program is free software; you can redistribute it and/or              #
# modify it under the terms of the GNU General Public License                #
# as published by the Free Software Foundation; either version 3.0           #
# of the License, or (at your option) any later version.                     #
#                                                                            #
# This program is distributed in the hope that it will be useful,            #
# but WITHOUT ANY WARRANTY; without even the implied warranty of             #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              #
# GNU General Public License for more details.                               #
#                                                                            #
# @author atsip-help@yandex.com                                              #
#                                                                            #
# This FreePBX install script are property of Intelcom LLC.                  #
# FreePBX is a product developed and supported by Sangoma Technologies.      #
# This install script is free to use for installing FreePBX                  #
# along with dependent packages only but carries no guarnatee on performance #
# and is used at your own risk. This script carries NO WARRANTY.             #
##############################################################################
#                                FreePBX 16                                  #
##############################################################################


echo -e '\033[34m#################################################
#\033[33m                                               \033[34m#
#\033[33m    Установка Asterisk & FreePBX на Ubuntu     \033[34m#
#\033[33m                                               \033[34m#
#\033[33m      Запускайте скрипт только от root!!       \033[34m#
#################################################\033[0m'

# set -e
SCRIPTVER="0.5.7"
# Changelog:
# Поправки ошибок + фаерволл + изменен webroot
# добавил неинтерактивный режим
# автостоп rinetd
# CDR Viewer MOD + ошибки
# Разбиение на функции
# Вынос вывода подсказок в отдельную функцию
# Мелкие доработки в кастомизации - правка через БД
export DEBIAN_FRONTEND=noninteractive
ASTVERSION=20
PHPVERSION="7.4"
LOG_FOLDER="/var/log"
LOG_FILE="${LOG_FOLDER}/freepbx16-install-$(date '+%Y.%m.%d-%H.%M.%S').log"
touch ${LOG_FILE}
log=$LOG_FILE
exec 2>>${LOG_FILE}
CDRV_PASS="GhjcvjnhPdjyrjd"
# DISTRIBUTION="$(lsb_release -is)"
# Переменные
timezone="Asia/Yekaterinburg"
start=$(date +%s.%N)
NAMEPBX=atsip-newpbx3
codename=noble
WEBROOT="/var/www/html/pbx"
WORK_DIR=$(pwd)
IP_ADDR=$(hostname -I)

function msg() {
    color="\033[0;33m"
    nocolor="\033[0m"
    echo -e "${color}$1${nocolor}"
    if [[ "$2" != "" ]]; then
        color="\033[0;34m"
        echo -e "${color}$2${nocolor}"
    fi
}

log() {
    echo "$(date +"%Y-%m-%d %T") - $*" >> "$LOG_FILE"
}

msg "Желаешь сам поправить MenuSelect? [Y/n]"
read MENUSELECT_EDIT

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

msg "Введи желаемый Hostname"
read NAMEPBX

msg "Меняем хостнейм на ${NAMEPBX}"
hostnamectl set-hostname ${NAMEPBX}

msg "Задайте пароль для CDR Viewer MOD пользователю admin"
read CDRV_PASS

function preinstall() {
    msg "Обновляем систему"
    apt-get update && apt-get upgrade -y
    msg "Устанавливаем сетевые утилиты:"
    apt install iputils-ping nmap net-tools tcpdump sngrep rinetd dnsutils -y
    msg "Дополнительные утилиты:"
    apt install sox mpg123 cron mc openvpn fail2ban tftpd-hpa git htop iptables ntp logrotate bc -y
}

function inst_apache_php(){
    msg "Устанавливаем PHP7.4 + Apache2"
    sudo apt install software-properties-common
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt install php7.4 php7.4-{cli,common,curl,zip,gd,mysql,xml,mbstring,json,intl} -y
    msg "Поправка конфига Апача"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 120M/g' /etc/php/7.4/apache2/php.ini
    cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf_orig 
    sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf 
    sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf 
    a2enmod rewrite 
    msg "В /etc/apache2/envvars исправляем пользователя на asterisk:"
    sed -i 's/^\(export APACHE_RUN_USER=\|export APACHE_RUN_GROUP=\).*/\1 asterisk/' /etc/apache2/envvars
    msg "И перезагружаем apache"
    systemctl restart apache2
}

function install_asterisk(){
    msg " > Установка Asterisk" "------------------------------"
    useradd -m asterisk
    cd /usr/src/
    # Скачивание файла только при его отсутствии
    if [ ! -e /usr/src/asterisk-18-current.tar.gz ]
    then
        wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTVERSION}-current.tar.gz
        tar xzf asterisk*
    fi
    cd asterisk-18.*
    msg "Установка зависимостей Asterisk"
    contrib/scripts/install_prereq install
    ./configure --with-pjproject-bundled --with-jansson-bundled
    msg "Подменяем menuselect своим"
    cp ${WORK_DIR}/usr/src/asterisk/menuselect.makedeps /usr/src/asterisk-*
    cp ${WORK_DIR}/usr/src/asterisk/menuselect.makeopts /usr/src/asterisk-*

    if [[ "${MENUSELECT_EDIT}" == "Y" ]]; then
        msg "И проверяем"
        make menuselect
        msg "Не забыл включить app_macro и языковые файлы? \nИ отключить лишнее!"
    fi

    msg " > Приступаю к сборке Asterisk" "------------------------------"
    # сборка в несколько потоков
    make -j $(nproc)
    make install
    make config
    ldconfig

    msg "Выставляем права на каталоги Asterisk:"
    chown -R asterisk: /var/run/asterisk 
    chown -R asterisk: /etc/asterisk 
    chown -R asterisk: /var/{lib,log,spool}/asterisk 
    chown -R asterisk: /usr/lib/asterisk

msg "Поправка конфига asterisk.conf"
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
autosystemname = yes
EOF
}

function inst_mariadb_con(){
    msg "Install MariaDB Connector"
    cd /usr/src/
    # Скачивание файла только при его отсутствии
    if [ ! -e /usr/src/mariadb-connector-odbc-*.deb ]
    then
        wget https://dlm.mariadb.com/3680402/Connectors/odbc/connector-odbc-3.1.20/mariadb-connector-odbc-3.1.20-ubuntu-jammy-amd64.deb
        dpkg -i mariadb-connector-odbc*
    fi
    sleep 10
    msg "Install MariaDB Server and Client"
    apt install mariadb-server mariadb-client galera-4 -y
    msg "Install UnixODBC"
    apt install unixodbc-dev unixodbc -y

msg "Поправка конфигов ODBC"
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
msg "Поправка конфига mariadb"
cat << EOF >> /etc/mysql/conf.d/mysql.cnf
[mysqld]
sql_mode=NO_ENGINE_SUBSTITUTION
EOF
}

function inst_nodejs(){
    msg "Установка nodeJS"

    curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash - 
    apt-get install -y nodejs
    apt install npm -y
}

function inst_freepbx(){
    msg " > Установка FreePBX" "----------------------"
    cd /usr/src
    # Скачивание файла только при его отсутствии
    if [ ! -e /usr/src/freepbx-16.0-latest.tgz ]
    then
        wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-16.0-latest.tgz
        tar xfz freepbx-16.0-latest.tgz
    fi
    touch /etc/asterisk/{modules,cdr}.conf 
    cd freepbx 
    ./start_asterisk start 
    ./install -n --webroot=${WEBROOT}
    chown -R asterisk: ${WEBROOT}
    fwconsole ma install pm2
    msg "Установка модулей FreePBX"
    fwconsole ma downloadinstall userman bulkhandler blacklist calendar cel cdr
    fwconsole ma downloadinstall timeconditions findmefollow backup featurecodeadmin announcement ringgroups customcontexts iaxsettings
    fwconsole reload --verbose

    msg "Установка русскоязычного расширенного языкового пакета"
    cd /usr/src/
    wget https://github.com/pbxware/asterisk-sounds-additional/archive/refs/heads/master.zip -O asterisk-sounds-additional.zip
    unzip -q asterisk-sounds-additional.zip
    cp -r asterisk-sounds-additional-master/* /var/lib/asterisk/sounds/ru/
    chown -R asterisk: /var/lib/asterisk/sounds
}

function install_cdr(){

    msg " > Установка CDR Viewer MOD" "-----------------------------"
    cd /usr/src/
    git clone https://github.com/atsip-ru/Asterisk-CDR-Viewer-Mod.git
    mv Asterisk-CDR-Viewer-Mod/ ${WEBROOT}/cdr
    cp ${WEBROOT}/cdr/inc/config/config.php.sample ${WEBROOT}/cdr/inc/config/config.php

    DBUSER=$(cat /etc/freepbx.conf | sed 's/ //g' | grep AMPDBUSER | tail -n 1 | cut -d= -f2)
    DBUSER=${DBUSER:1}
    DBUSER=${DBUSER%??}
    sed -i "s/db_user/${DBUSER}/"  ${WEBROOT}/cdr/inc/config/config.php
    sed -i "s/db_name/asteriskcdrdb/"  ${WEBROOT}/cdr/inc/config/config.php

    DBPASS=$(cat /etc/freepbx.conf | sed 's/ //g' | grep AMPDBPASS | tail -n 1 | cut -d= -f2)
    DBPASS=${DBPASS:1}
    DBPASS=${DBPASS%??}
    sed -i "s/db_password/${DBPASS}/"  ${WEBROOT}/cdr/inc/config/config.php
    sed -i "96 s/^/\t\t\t'admin',/" ${WEBROOT}/cdr/inc/config/config.php

    msg "Задаем пароль для CDR Viewer MOD пользователю admin"
    htpasswd -bc ${WEBROOT}/cdr/.htpasswd admin $CDRV_PASS
    msg "Для включения парольного доступа - добавьте пользователя (-ей) в config.php \nсогласно инструкции https://github.com/atsip-ru/Asterisk-CDR-Viewer-Mod/blob/master/docs/Readme.md#добавить-пользователя"

cat << EOF >> /etc/apache2/apache2.conf
<Directory "${WEBROOT}/cdr">
    Options Indexes FollowSymLinks
    AllowOverride None
    AuthName "CDR Viewer Mod"
    AuthType Basic
    AuthUserFile ${WEBROOT}/cdr/.htpasswd
    Require valid-user
</Directory>
EOF

    systemctl restart apache2
}

function set_firewall(){
    msg "Установка настроек фаерволла"
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
}

function set_rinetd(){
    msg "Ограничение времени работы rinetd" "Не факт что работает"
    mkdir -p /etc/systemd/system/rinetd.service.d/
cat << EOF >> /etc/systemd/system/rinetd.service.d/override.conf
[Service]
RuntimeMaxSec=1800
EOF
}

function set_tftp(){
    msg "Преднастройка TFTP"
    sudo sed -i 's/^TFTP_DIRECTORY=.*/TFTP_DIRECTORY="\/tftpboot"/'  /etc/default/tftpd-hpa
    mkdir /tftpboot
    cp ${WORK_DIR}/tftpboot/y000000000053.cfg /tftpboot
    cd /tftpboot
    ln -s y000000000053.cfg y000000000127.cfg
    chown -R nobody:nogroup /tftpboot
}

function inst_scripts(){
    # Создаем свой motd
    cp ${WORK_DIR}/etc/update-motd.d/99-intelcom /etc/update-motd.d/
    msg "Добавляем скрипты автоудаления старых записей и голосовой почты + настройки logrotate"
    mv ${WORK_DIR}/etc/cron.daily/rmwav.sh /etc/cron.daily/
    mv ${WORK_DIR}/etc/cron.daily/vm-auto-delete.sh /etc/cron.daily/
    mv ${WORK_DIR}/etc/logrotate.d/asterisk /etc/logrotate.d/
    systemctl daemon-reload
    msg "Устранение ошибки fail2ban" "Потребуется ввод пароля"
    apt install python3-pip -y
    python3 -m pip install pyasynchat --break-system-packages
    systemctl restart fail2ban
}

function customize(){
    # Уменьшаем генерирование пароля до 8 символов
    mysql -u root -D asterisk -e "UPDATE freepbx_settings SET value = '8' WHERE keyword = 'SIPSECRETSIZE';"
    # Отображение хостнейма в строке браузера
    mysql -u root -D asterisk -e "UPDATE freepbx_settings SET value = '1' WHERE keyword = 'SERVERINTITLE';"
    # Задание тоновых сигналов и установка имени атски
    mysql -u root -D asterisk -e "UPDATE freepbx_settings SET value = 'ru' WHERE keyword = 'TONEZONE';"
    mysql -u root -D asterisk -e "UPDATE freepbx_settings SET value = ${NAMEPBX} WHERE keyword = 'FREEPBX_SYSTEM_IDENT';"
    # подчищаем от аудиофайлов для кодека g722
    find /var/lib/asterisk/sounds/ -type f -name "*.g722" -delete
    # часовой пояс
    timedatectl set-timezone ${timezone}
    mysql -u root -D asterisk -e "UPDATE freepbx_settings SET value = ${timezone} WHERE keyword = 'PHPTIMEZONE';"
    # Заглушка для корня веба
    mv ${WORK_DIR}/var/www/html/index.html ${WEBROOT}
    mv ${WORK_DIR}/var/www/html/mainstyle.css ${WEBROOT}
    mv ${WORK_DIR}/var/www/html/admin/images/atsip.ru.png ${WEBROOT}/admin/images/
    # Актуализация локализации веб-интерфейса
    mv ${WORK_DIR}/var/www/html/freepbx-framework-ru.po ${WEBROOT}/admin/i18n/ru_RU/LC_MESSAGES/amp.po
    mv ${WORK_DIR}/var/www/html/freepbx-framework-ru.mo ${WEBROOT}/admin/i18n/ru_RU/LC_MESSAGES/amp.mo
    # Добавляем индексацию таблице cdr
    mysql -u root -D asterisk -e "ALTER TABLE asteriskcdrdb.cdr ADD id BIGINT NOT NULL AUTO_INCREMENT FIRST, ADD PRIMARY KEY (id);"
}

# Вызов функций
preinstall
install_asterisk
inst_apache_php
inst_mariadb_con
inst_nodejs
inst_freepbx
install_cdr
set_firewall
set_rinetd
set_tftp
inst_scripts
customize

chown -R asterisk: ${WEBROOT}
chown -R asterisk: /etc/asterisk
fwconsole restart
systemctl daemon-reload
#systemctl enable freepbx

echo -e "\033[34m############################################################
#\033[33m                                                          \033[34m#
#\033[33m Поздравляем с успешной установкой Asterisk и FreePBX     \033[34m#
#\033[33m Не забудь сменить пароль root для mariadb                \033[34m#
#\033[33m Донастрой АТС по адресу http://${IP_ADDR}/pbx/admin/ \033[34m#
#\033[33m                                                          \033[34m#
############################################################\033[0m"

{
echo "              _       _                   "
echo "         __ _| |_ ___(_)_ __   _ __ _   _ "
echo "        / _\` | __/ __| | '_ \ | '__| | | |"
echo "       | (_| | |_\__ \ | |_) || |  | |_| |"
echo "        \__,_|\__|___/_| .__(_)_|   \__,_|"
echo "                       |_|                "
}

# Время выполнения скрипта
duration=$(echo "$(date +%s.%N) - $start" | bc)
execution_time=`printf "%.2f seconds" $duration`
msg "Время полного выполнения скрипта: $execution_time" "Процесс установки FreePBX 16 успешно завершен!"