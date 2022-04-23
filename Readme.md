# One click install markshust/docker-magento 


This is a simple bash script, which helps to install magento project in one click.

It works for existing project only. You have to set the git source to the project as a parameter.

Or you can modify install.sh script depending on your purpose.

## How to run

1. Put auth.json file into the root path where you are going to run install.sh.

2. (Optional) You can put your env.php file into the root folder either. Otherwise, default env.php will be used. Do not forget to copy the mysql data from default env.php.

3. Be sure that ~/.ssh/id_rsa exists

4. Download script into the root folder: `curl -O https://raw.githubusercontent.com/asannikov/markshust-docker-magento-installer/main/install.sh`

5. Find usage info by running `sh install.sh --help`.


Used parameters:
- `-d` sets domain name
- `-r` sets repository path
- `-db` sets path to db dump file
- `-c` sets composer version. 2 - by default
- `-p` sets php version. 8.1-fpm-0 - by default. (8.1-fpm-0 | 7.4-fpm-6 | 7.3-fpm-13 | 7.2-fpm-9 | 7.1-fpm-13)

## Extra features
- optimized for working on MacOS!

- it prepares elasticsearch and DB configuration

- you can use xdebug using cli out of box

- you can enable xdebug profile mode. Use bin/xdebug-profile status/profile/disable/toggle. 

NOTE: you have to disable it using bin/xdebug-profile, not by bin/xdebug! Otherwise you have to clean up php.ini file manually.

- fixed problem with id_rsa key on start.

- selenium works out of box

## How to use xdebug in CLI

`bin/bash` and then inside container run `export XDEBUG_CONFIG="remote_enable=1 remote_mode=req remote_host=your.domain remote_port=9000 remote_connect_back=0"`

do not forget to replace "your.domain"!

more info here: https://www.jetbrains.com/help/phpstorm/debugging-a-php-cli-script.html

## How to test selenium

Do every single step from Mark Shust's readme but run only `bin/mftf run:test AdminLoginSuccessfulTest` instead of `bin/mftf run:test AdminLoginTest`.

Use vnc://127.0.0.1:5900 in finder to connect to selenium. Password is `secret`.