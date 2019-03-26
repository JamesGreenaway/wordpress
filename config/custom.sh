#!/bin/bash

user_exists=$(id -u wordpress > /dev/null 2>&1; echo $?)
if [ ${user_exists} -eq 1 ]; then
    export LOCAL_UID="${LOCAL_UID:-1000}"
    useradd -m -s $(which bash) -u ${LOCAL_UID} wordpress
else
    echo '- User already created'
fi

export SSL_SITE_NAME="${SSL_SITE_NAME:-Testing}"
html=( `find /var/www/html -maxdepth 1 -name "ssl"`)
if [ ${#html[@]} -gt 0 ]; then
    echo "- SSL already generated"
    cp /var/www/html/ssl/localdomain.crt /var/www/html/ssl/localdomain.insecure.key /etc/apache2/
else
	openssl genrsa -des3 -passout pass:password -out /etc/apache2/localdomain.secure.key 2048  && \
	echo "password" |openssl rsa -in localdomain.secure.key -out /etc/apache2/localdomain.insecure.key -passin stdin  && \
	openssl req -new -sha256 -nodes -out /etc/apache2/localdomain.csr -key localdomain.insecure.key -config localdomain.csr.cnf && \
	openssl genrsa -des3 -passout pass:password -out /etc/apache2/rootca.secure.key 2048  && \
	echo "password" | openssl rsa -in rootca.secure.key -out /etc/apache2/rootca.insecure.key -passin stdin  && \
	openssl req -new -x509 -nodes -key rootca.insecure.key -sha256 -out /etc/apache2/cacert.pem -days 3650 -subj "/C=GB/ST=London/L=London/O=localhost/OU=IT Department/CN=${SSL_SITE_NAME}"  && \
	openssl x509 -req -in localdomain.csr -CA cacert.pem -CAkey rootca.insecure.key -CAcreateserial -out /etc/apache2/localdomain.crt -days 500 -sha256 -extfile /etc/apache2/localdomain.v3.ext
	mkdir /var/www/html/ssl
	chown wordpress:wordpress -R /var/www/html/ssl
	mv /etc/apache2/cacert.pem /var/www/html/ssl
	cp /etc/apache2/localdomain.crt /etc/apache2/localdomain.insecure.key /var/www/html/ssl
	chown wordpress:wordpress -R /var/www/html/ssl
fi
