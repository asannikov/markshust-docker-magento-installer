#!/bin/bash

POSITIONAL_ARGS=()

COMPOSER=2
PHP="8.1-fpm-1"
while [[ $# -gt 0 ]]; do
  case $1 in
    -db|--dbdump)
      DBDUMP="$2"
      shift # past argument
      shift # past value
      ;;
    -r|--repository)
      REPOSITORY="$2"
      shift # past argument
      shift # past value
      ;;
    -b|--branch)
      BRANCH="$2"
      shift # past argument
      shift # past value
      ;;
    -d|--domain)
      DOMAIN="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--composer)
      COMPOSER="$2"
      shift # past argument
      shift # past value
      ;;
    -p|--php)
      PHP="$2"
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      HELP=YES
      shift # past argument
      ;;
    --default)
      DEFAULT=YES
      shift # past argument
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [[ "${HELP}" ]]; then
    echo "usage: install.sh [--domain <domain>| -d <domain>] [--repository <repository>| -r <repository>] [--dbdump <pathToDbFile.sql>| -db <pathToDbFile.sql>] [--composer <1|2>| -c <1|2>] [--php <8.1-fpm-0|7.4-fpm-6|7.3-fpm-13|7.2-fpm-9|7.1-fpm-13>| -p <version>] [--help]\n"
    echo "Default php: 8.1-fpm-1, default composer: 2"
    exit 1
fi

echo "DB Dump     = ${DBDUMP}"
echo "Repository  = ${REPOSITORY}"
echo "Branch      = ${BRANCH}"
echo "Domain      = ${DOMAIN}"
echo "Composer    = ${COMPOSER}"
echo "Php         = ${PHP}"
# echo "DEFAULT     = ${DEFAULT}"

if [ -z "${DOMAIN}" ]; then
    echo 'Define domain without http, ie. magento.dev'
    exit 1
fi

if [ -z "${REPOSITORY}" ]; then
    echo 'Define git url source, ie. https://github.com/asannikov/markshust-docker-magento-installer.git'
    exit 1
fi

if [ -z "${DBDUMP}" ]; then
    echo 'Define path to mysql DB dump, ie. backups/magento.sql'
    exit 1
fi

COMPOSER_VERSION=2
if (( ${COMPOSER} == 1 ||  ${COMPOSER} == 2 )); then
    COMPOSER_VERSION=${COMPOSER}
fi

# Download the Docker Compose template:
curl -s https://raw.githubusercontent.com/markshust/docker-magento/43.2.0/lib/template | bash

# Download custom xdebug profile management
cd bin && { curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/bin/xdebug-profile ; cd -; }
cd bin && { curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/bin/mysql_test ; cd -; }
curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/compose.yaml ;
curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/nginx.conf;

IP=$(docker run --rm alpine ip route | awk 'NR==1 {print $3}')

sed -i -e "s/magento.test/${DOMAIN}/g" ./compose.yaml
sed -i -e "s/8.1-fpm-1/${PHP}/g" ./compose.yaml

rm compose.yaml-e

sed -i -e "s/cached/delegated/g" ./compose.dev.yaml
sed -i -e "s/id_rsa:delegated/id_rsa:cached/g" ./compose.dev.yaml
sed -i -e "s/nginx.conf.sample/nginx.conf/g" ./compose.dev.yaml
sed -i -e "s/- .\/src\/grunt-config.json.sample/# - .\/src\/grunt-config.json.sample/g" ./compose.dev.yaml
sed -i -e "s/- .\/src\/Gruntfile.js.sample/# - .\/src\/Gruntfile.js.sample/g" ./compose.dev.yaml
sed -i -e "s/- .\/src\/package.json.sample/# - .\/src\/package.json.sample/g" ./compose.dev.yaml

rm compose.dev.yaml-e

sed -i -e "s/src\"/src ~\/.ssh\/id_rsa\"/g" ./bin/start

rm ./bin/start-e

# Replace with existing source code of your existing Magento instance:
mkdir tmp
if [ -z "${BRANCH}" ]; then
  git clone "${REPOSITORY}" ./tmp
else
  git clone --single-branch --branch "${BRANCH}" "${REPOSITORY}" ./tmp
fi
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
docker-compose -f compose.yaml up -d
bin/copytocontainer --all ## Initial copy will take a few minutes...

echo "Import existing database:"
bin/mysql < "${DBDUMP}"

bin/restart

bin/root mysql -hdb -uroot -pmagento -e 'CREATE DATABASE magento_test;'
bin/root mysql -hdb -uroot -pmagento -e 'GRANT ALL PRIVILEGES ON `magento_test`.* TO "magento"@"%";'
bin/root mysql -hdb -uroot -pmagento -e 'GRANT ALL ON `magento_test`.* TO "magento"@"%";'
bin/root mysql -hdb -uroot -pmagento -e 'GRANT SELECT ON `magento_test`.* TO "magento"@"%";'
bin/root mysql -hdb -uroot -pmagento -e 'FLUSH PRIVILEGES ;'

if [[ $COMPOSER_VERSION -eq 1 ]];then
    bin/root composer self-update --1
fi

bin/composer install -v

# Import app-specific environment settings:
bin/magento app:config:import

bin/setup-domain ${DOMAIN}

bin/magento config:set catalog/search/elasticsearch7_server_hostname elasticsearch
bin/magento config:set catalog/search/elasticsearch7_server_port 9200
bin/magento config:set smtp/general/enabled 1
bin/magento config:set smtp/module/active 1
bin/magento config:set smtp/configuration_option/password null
bin/magento config:set smtp/configuration_option/username null
bin/magento config:set smtp/configuration_option/authentication smtp
bin/magento config:set smtp/configuration_option/port 1025
bin/magento config:set smtp/configuration_option/host mailcatcher
bin/magento config:set web/cookie/cookie_domain ${DOMAIN}

bin/magento cache:c

bin/magento indexer:reindex
bin/magento setup:upgrade
bin/fixowns .
bin/cron stop
bin/magento cron:install

# echo 'Preparing test database'
# bin/n98-magerun2 db:dump --strip="@development" dump.sql
# bin/copyfromcontainer dump.sql
# bin/mysql_test < src/dump.sql
# bin/cli rm dump.sql

open https://"${DOMAIN}"
