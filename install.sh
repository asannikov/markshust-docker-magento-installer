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
curl -s https://raw.githubusercontent.com/markshust/docker-magento/master/lib/template | bash

# Download custom xdebug profile management
cd bin && { curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/bin/xdebug-profile ; cd -; }
cd bin && { curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/bin/start ; cd -; }

curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/docker-compose.dev.yml ;
curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/docker-compose.yml ;
curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/nginx.conf;

sed -i -e "s/example.domain/$1/g" ./docker-compose.dev.yml

rm docker-compose.dev.yml-e

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

echo "Create a DNS host entry for the site:"
echo "127.0.0.1 ::1 $1" | sudo tee -a /etc/hosts

# Start some containers, copy files to them and then restart the containers:
docker-compose -f docker-compose.yml up -d
bin/copytocontainer --all ## Initial copy will take a few minutes...

echo "Import existing database:"
bin/mysql < "$3"

# Update database connection details to use the above Docker MySQL credentials:
# Also note: creds for the MySQL server are defined at startup from env/db.env
# vi src/app/etc/env.php

bin/restart

bin/composer install -v

# Import app-specific environment settings:
bin/magento app:config:import

# Set base URLs to local environment URL (if not defined in env.php file):
bin/magento config:set web/secure/base_url https://"$1"/
bin/magento config:set web/unsecure/base_url https://"$1"/
bin/magento config:set catalog/search/elasticsearch7_server_hostname elasticsearch
bin/magento config:set catalog/search/elasticsearch7_server_port 9200
bin/magento cache:c

bin/magento indexer:reindex
bin/magento setup:upgrade

# waiting until elasticseatch run
sleep 90

open https://"$1"
