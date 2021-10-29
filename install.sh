#!/bin/bash

if [ -z "$1" ]; then
    echo 'Define domain without http, ie. magento.dev'
    exit 1
fi

if [ -z "$2" ]; then
    echo 'Define git url source, ie. https://github.com/asannikov/markshust-docker-magento-installer.git'
    exit 1
fi

if [ -z "$3" ]; then
    echo 'Define path to mysql DB dump, ie. backups/magento.sql'
    exit 1
fi

# Download the Docker Compose template:
curl -s https://raw.githubusercontent.com/markshust/docker-magento/41.0.0/lib/template | bash

# Download custom xdebug profile management
cd bin && { curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/bin/xdebug-profile ; cd -; }
cd bin && { curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/bin/mysql_test ; cd -; }
curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/docker-compose.yml ;
curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/nginx.conf;

IP=$(docker run --rm alpine ip route | awk 'NR==1 {print $3}')
sed -i -e "s/example.domain:IP/example.domain:$IP/g" ./docker-compose.yml
sed -i -e "s/example.domain/$1/g" ./docker-compose.yml

rm docker-compose.yml-e

sed -i -e "s/cached/delegated/g" ./docker-compose.dev.yml
sed -i -e "s/id_rsa:delegated/id_rsa:cached/g" ./docker-compose.dev.yml
sed -i -e "s/nginx.conf.sample/nginx.conf/g" ./docker-compose.dev.yml

rm docker-compose.dev.yml-e

sed -i -e "s/src\"/src ~\/.ssh\/id_rsa\"/g" ./bin/start

rm ./bin/start-e

# Replace with existing source code of your existing Magento instance:
mkdir tmp
git clone "$2" ./tmp
mv ./tmp src
mv nginx.conf src


ENV_FILE=env.php

if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" src/app/etc/
else 
    curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/env.php;
    mv "$ENV_FILE" src/app/etc/
fi

AUTH_FILE=auth.json

if [[ -f "$AUTH_FILE" ]]; then
    cp "$AUTH_FILE" src/auth.json
fi

# Start some containers, copy files to them and then restart the containers:
docker-compose -f docker-compose.yml up -d
bin/copytocontainer --all ## Initial copy will take a few minutes...

echo "Import existing database:"
bin/mysql < "$3"

bin/restart

bin/root mysql -hdb -uroot -pmagento -e 'CREATE DATABASE magento_test;'
bin/root mysql -hdb -uroot -pmagento -e 'GRANT ALL PRIVILEGES ON `magento_test`.* TO "magento"@"%";'
bin/root mysql -hdb -uroot -pmagento -e 'GRANT ALL ON `magento_test`.* TO "magento"@"%";'
bin/root mysql -hdb -uroot -pmagento -e 'GRANT SELECT ON `magento_test`.* TO "magento"@"%";'
bin/root mysql -hdb -uroot -pmagento -e 'FLUSH PRIVILEGES ;'

bin/composer install -v

# Import app-specific environment settings:
bin/magento app:config:import

bin/setup-domain $1

bin/magento config:set catalog/search/elasticsearch7_server_hostname elasticsearch
bin/magento config:set catalog/search/elasticsearch7_server_port 9200
bin/magento cache:c

bin/magento indexer:reindex
bin/magento setup:upgrade
bin/fixowns .
bin/magento cron:install

# echo 'Preparing test database'
# bin/n98-magerun2 db:dump --strip="@development" dump.sql
# bin/copyfromcontainer dump.sql
# bin/mysql_test < src/dump.sql
# bin/cli rm dump.sql

open https://"$1"
