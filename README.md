# pbx-3

Файлы для установки Asterisk

Просто файлы для настройки АТС.

## Установка:

* Загрузить каталог pbx-3 на сервер
* переместить в каталог root
* запустить файл `install.sh` от root

## Краткое описание установленной АТС:
* Устанавливает последние версии Asterisk 18, FreePBX 16 и CDR Viewer MOD
* Устанавливает нужные утилиты: sngrep, ping, fail2ban, tftp, nmap, iptables, ntpd, mc, sox, openvpn, htop,
PHP7.4
и необходимые зависимости для сборки Asterisk
* Запрашивает хостнейм и пароль для админа CDR Viewer MOD
* Содержит преднастроенный менюселект с включенным app_macro (см [скриншоты](SCREENS.md))
* Устанавливает mariadb-connector + ODBC и настраивает их
* Устанавливает nodeJS 18 (требуется для FreePBX)
* Устанавливаемые модули FreePBX: userman, bulkhandler, blacklist, calendar, cel, cdr, timeconditions, findmefollow, backup, featurecodeadmin, announcement, ringgroups, customcontexts, iaxsettings
* Делает преднастройки фаерволла в файл /root/iptables-firewall.sh
* Преднастраивает TFTP
* Добавляет скрипты для автоудаления старых записей вызовов и голосовой почты
* Добавляет преднастройки logrotate
* Преднастраивается русская локаль в FreePBX и часовой пояс Asia/Yekaterinburg (можно переопределить в переменных скрипта)
* Каталог установки FreePBX (веб-директория) выбирается /var/www/html/pbx/admin/
* Добавляется индексация таблицы cdr
* Поправка локализации FreePBX до актуальной