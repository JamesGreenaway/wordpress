# A fully extensible development environment for running multiple sites with Wordpress
**Warning:** This project is still being developed! Please keep referring to this README for up-to-date instructions.

## Description

### What is this?

At its core, this is a custom Docker image that is built with all the necessary resources to install and run [Wordpress](https://wordpress.org). Included, is a selection of tips that will help the user to run multiple websites at the same time with as minimal fuss as possible.    

### Why should I use it?

Setting up a development workflow can be timely. This project intends to remove this overhead and give you peace of mind that, no matter the circumstances, you can get back to work as quickly as possible. 

Spinning up a new instance of Wordpress is easy and each site can have its own secure domain name.

Projects can be run at the same time without worrying about port selection and at every step the user has the option to customise it to suit their needs. 

### How does it work?

This image is primarily based on "Docker Official Images", a regularly maintained and curated set of Docker repositories hosted on [Docker Hub](https://hub.docker.com/):

- [PHP v7.3](https://hub.docker.com/_/php)
- [Wordpress v5.2.2](https://hub.docker.com/_/wordpress)
- [MySQL v8.0](https://hub.docker.com/_/mysql)
- [Traefik v2.0-rc2](https://hub.docker.com/_/traefik)

It will install Wordpress inside a volume whereby the user has access to all its files locally and in their entirety. Wordpress will link up to MySQL and all database entries will persist locally on the host machine ensuring that no data is lost when containers are stopped. 

All external network data is routed to our containers via Traefik. When used in tandem with [dnsmaq](http://www.thekelleys.org.uk/dnsmasq/doc.html) our containers can respond to requests using a custom domain name of our choosing and can run at the same time and on the same ports.

---

## Quick Start: Running this image on localhost.

```
version: "3.7"
services:
  mysql: 
    image: mysql:8.0
    restart: always
    volumes:
      - mysql:/var/lib/mysql
    environment:
      MYSQL_ALLOW_EMPTY_PASSWORD: "yes"
    command: --default-authentication-plugin=mysql_native_password
  wordpress:
    image: jamesgreenaway/wordpress:latest
    restart: unless-stopped
    environment: 
      WORDPRESS_DB_USER: root
      WORDPRESS_DB_PASSWORD: ""
      WORDPRESS_DB_NAME: ${COMPOSE_PROJECT_NAME}
      SITE_URL: http://${COMPOSE_PROJECT_NAME}
    volumes:
      - ./wordpress:/var/www/html/
    depends_on:
      - mysql
    ports: 
     - 80:5000
volumes: 
  mysql: {}
``` 

### How to:

1. Create a `docker-compose.yml` file using the above configuration. 
1. Run `echo "COMPOSE_PROJECT_NAME=localhost" > .env`.
1. Run `docker-compose up -d`. 
1. Run `docker-compose logs -f wordpress` to view the Wordpress installation process. 
1. Once the installation is complete you can visit: `http://localhost:80` to see your new instance of Wordpress running. 
1. Stop your container by running `docker-compose down`.

**Important**: We are using `COMPOSE_PROJECT_NAME` as a variable inside our `docker-compose.yml` file to prevent us from needing to update the name of the project for every option. For this example, we have simply created a file called `.env`, however, there are several ways to include this variable. Please see "[Environment variables in Compose](https://docs.docker.com/compose/environment-variables/)" for more information.

---

## How to run multiple sites at the same time without having to change ports. 

One frustrating thing about Docker is that, once your container is running, its respective port is unavailable for other containers to use. This means that, for every new site we create, we usually have to bind to a different port. Keeping track of all these ports can be unnecessarily complicated, so we need a solution that will allow us to run our containers on the same port without having to dance around trying to find a new one each time we create a site. 

### Traefik to the rescue.

Traefik describes itself is an open-source reverse proxy/load balancer. We can employ it as a kind of gatekeeper to all of our services. All our requests for data will go through Traefik first and Traefik will decide where to route them for us. We can give each container its own domain name and Traefik will arrange the networking for us.

``` 
...
  traefik:
    restart: always
    image: traefik:v2.0.0-rc2
    ports:
      - 80:5000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: 
      --entrypoints.web.address=:5000
      --providers.docker=true 
      --providers.docker.network=traefik
    networks:
      - traefik
...
```

### How to:

1. For now, add the above configuration as another service to our `docker-compose.yml` file. Later we will split these in to separate containers so that we can run multiple sites using one Traefik instance.   
1. Run `docker network create traefik` to create an external network. 
1. Add the network to the bottom of the `docker-compose.yml` file: 

    ```
    networks:
      traefik:
        external: true
    ```

1. Edit the `wordpress` service so that it matches the following configuration:

    ```
    wordpress:
      image: jamesgreenaway/wordpress:latest
      restart: unless-stopped
      environment: 
        WORDPRESS_DB_USER: root
        WORDPRESS_DB_PASSWORD: ""
        WORDPRESS_DB_NAME: ${COMPOSE_PROJECT_NAME}
        SITE_URL: http://${COMPOSE_PROJECT_NAME}
      volumes:
        - ./wordpress:/var/www/html/
      labels:
        - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1.entrypoints=web
        - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1.rule=Host(
          `${COMPOSE_PROJECT_NAME}`)
        - traefik.http.services.${COMPOSE_PROJECT_NAME}-wordpress1.loadbalancer.server.port=5000
      depends_on:
        - mysql
        - traefik
      networks:
        - default 
        - traefik
    ``` 

1. Run `docker-compose up -d` to start our containers. 
1. Now you can visit `http://localhost:80` to see your instance of Wordpress running. The container is still running on `localhost:80`, however, Traefik is now intercepting all requests to this port and sending them to our container.

>  Remember to stop all containers before continuing. 

---

## Giving each site its own domain name.

Currently we have one site running on localhost via Traefik, however, to have multiple sites running alongside each other we need to give each site its own domain name first. [dnsmasq](https://wiki.debian.org/HowTo/dnsmasq) can help us to redirect all domains that end in a specific top-level domain (i.e. `.test`) back to our local machine. Traefik can then decide which container to send it to based on its subdomain.

### How to:

1. Run `brew install dnsmasq` (macOS) to install dnsmaq. 
1. Tell dnsmaq to look out for any domains that end in `.test`: 

    ```
    mkdir -p /etc/resolver
    echo "nameserver 127.0.0.1" | sudo tee -a /etc/resolver/test > /dev/null
    echo 'address=/.test/127.0.0.1' >> $(brew — prefix)/etc/dnsmasq.conf
    ```

1. Start dnsmasq as a service so it automatically starts at login `sudo brew services start dnsmasq` (macOS).

    > #### **Note**:
    > For Liunx (Debian/Ubuntu) users, you can install dnsmaq using `apt-get install dnsmasq`. 
    >
    > You can then edit dnsmasq config file `echo 'address=/.test/127.0.0.1' >> /etc/dnsmasq.conf`. 
    >
    > Linux, however, does not offer the option to add resolvers to `/etc/resolver`. Instead you must uncomment `prepend domain-name-servers 127.0.0.1;` from `/etc/dhcp/dhclient.conf` to ensure that the dhclient overrides `resolv.conf` with our localhost's IP address. In some cases (i.e. ChromeOS' Crostini) you may also need to feed the `dhclient.conf` file with Google's public DNS servers like so: `prepend domain-name-servers 127.0.0.1,8.8.8.8,8.8.4.4;`. 
    >
    > You will also need to restart your local machine to run the dhclient script which will then subseqently override the `resolv.conf` file with our nameservers.

Now we need to update our `wordpress` service to include its own custom domain name. 

1. Edit the Host rule label inside the `docker-compose.yml` file so that it matches the following configuration:

    ```
    - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1.rule=Host(
      `${COMPOSE_PROJECT_NAME}.test`, `www.${COMPOSE_PROJECT_NAME}.test`)
    ```

    > **Note**: If you would like to have different services running on other subdomains it is recommended that you add a separate service to your compose file (see the section called "Adding Wordpress to a subdomain" below for more information on how to achieve this).

1. Change the value of `SITE URL` to include `.test`: 

    ```
    SITE_URL: http://${COMPOSE_PROJECT_NAME}.test
    ```

1. Next, we need to remove the Wordpress project and its respective mysql volume so that we can re-install a new Wordpress project using the new domain names. 
    > You could manually change the settings inside the Wordpress dashboard but, for now, let's just create a new project.

    ```
    rm -rf ./wordpress
    docker volume rm <project_directory_name>_mysql
    ```

1. Update the `COMPOSE_PROJECT_NAME` environment variable inside our `.env` file: 

    `COMPOSE_PROJECT_NAME=example`
  
1. Run `docker-compose up -d` to start our container. 
1. Once installed you can visit `http://example.test` to see your instance of Wordpress running.
>  Remember to stop all containers before continuing.

---

## Let's add HTTPS.

To mimic a secure HTTPS-enabled site locally, we can use [mkcert](https://github.com/FiloSottile/mkcert). mkcert can fabricate self-signed SSL certificates super-quick and with zero configuration. 

Please consult the [mkcert](https://github.com/FiloSottile/mkcert) Github repository for full installation instructions. 

**Important**: Once you have installed mkcert you will likely need to restart your local machine. 

### How to:

To create a certificate, create a folder called `certificates/` and run the following command:

```
echo "example" > /dev/null && mkcert -cert-file certificates/$_-cert.pem -key-file certificates/$_-key.pem "$_.test" "*.$_.test"
```
> For any future projects please replace `example` with the same value as `COMPOSE_PROJECT_NAME`.

Once you have created your certificates you will need to inform Traefik of where it can locate them. Please add a file called `dynamic_conf.toml` and include the following text for each project you create certificates for:

```
[tls]
  [[tls.certificates]]
    certFile = "/certificates/example-cert.pem"
    keyFile = "/certificates/example-key.pem"
```

**Important**: Make sure that, for every project, you edit the word `example` to match the value given to the `COMPOSE_PROJECT_NAME` environment variable. You *must* hard code the value for `COMPOSE_PROJECT_NAME`.

> Hopefully this step will not be necessary in the future when Traefik v2.0 is complete. [3#card-24640764](https://github.com/containous/traefik/projects/3#card-24640764)

Now we need to update our containers to include this feature. Let's start by editing our `traefik` service.

1. Expose port 443 by adding the following value to the `ports` option:

    `- 443:443`

1. Add two more volumes to the `volumes` configuration option: 

    ```
    - ./dynamic_conf.toml:/config/dynamic_conf.toml:ro
    - ./certificates:/certificates:ro
    ```

1. Add the following `command` flags: 

    ```
    --entrypoints.web-secure.address=:443
    --providers.file.filename=/config/dynamic_conf.toml
    --providers.file.watch=true
    ```
    > **Important**: You **must** run `docker-compose restart traefik` to update Traefik with new certificates. 

1. Now, we need to edit our `wordpress` service.  Add the following flags to the `labels` configuration option: 

    ```
    - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1-secure.tls=true
    - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1-secure.entrypoints=web-secure
    - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1-secure.rule=Host(
      `${COMPOSE_PROJECT_NAME}.test`, `www.${COMPOSE_PROJECT_NAME}.test`)
    ```

1. Finally, update the `$SITE_URL` environment variable from `http://` to `https://`.

1. Run `docker-compose up -d`.

1. You can now visit `https://example.test` to see your instance of Wordpress running using the HTTPS protocol.

**Note**: If you intend on using this docker project in production, please consult Traefik's [documentation](https://docs.traefik.io/v2.0/https/acme/) to help you to create real SSL certificates using Let's Encrypt.

---

## Running multiple Wordpress sites.

So now the stage is set to run multiple Wordpress sites alongside each other. To create a new project all we need to do is copy the example `docker-compose.yml` file inside a new directory and update it with the details of our new site. 

### How to: 
Change the value for `COMPOSE_PROJECT_NAME` inside our `.env` file to the name of our new project.

**Note**: For the sake of this tutorial, Traefik has been included inside the first `docker-compose.yml` file. It is recommended that the user separate `traefik` and all its ancillary files to their own directory. Please see the bottom of this README for an example of how to layout your project.

The last step is to create a new certificate for your project. Follow the steps in the "Let's add HTTPS" section and make sure that you update: 

- the mkcert command with the new project name.
- the `dynamic_conf.toml` with the location of our new certificates.

**Important**: You **must** run `docker-compose restart traefik` to update Traefik with new certificates. 

---

## Other Features

### Redirect to HTTPS.

If you would like your site to always redirect to HTTPS you can add the following middleware to the `wordpress` services labels: 

```
- traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1.middlewares=https
- traefik.http.middlewares.https.redirectscheme.scheme=https
```

Now our domain will always redirect back to the HTTPS protocol.

---

### Adding Wordpress to a subdomain. 

You may wish to have Wordpress isolated to its own subdomain. For example, you may have an application running at `www.example.test`, however, you would also like an instance of Wordpress running at `blog.example.test`. Simply follow the same steps above to add a new Wordpress project to your compose file and update Traefik's host rule label with the subdomain you wish to use.

There may be a scenario where you would like to have multiple instances of the same service running i.e. MySQL. To avoid any overlaps you must ensure that:

  * service names do not match.
  * volume names do not match.
  * that you add a new "named volume" to the bottom of your compose file to match any new services created with MySQL.
  * you update the name of any services the container `depends_on` to match the new service name(s).
  * the `$  WORDPRESS_DB_HOST` environment variable is present and matches the new service name(s).

Furthermore, just like when creating a new project, you must ensure that the following values are also updated so that they are unique: 

- Environment variables: 
  * `$SITE_URL`

- Labels: 
  * Router/service name(s)
  * Host rule domain name(s)

---

### Exporting and importing databases.

* `docker exec <container-name> sh -c 'exec mysqldump <database> -uroot' > mysqldump.sql`
> This will take an existing database and dump the contents of the database in a file named mysqldump.sql

* `docker exec <container-name> sh -c 'exec mysql <database> -uroot' < mysqldump.sql`
> This will take an existing mysqldump.sql and dump its contents in to a database of your choosing.

* `docker exec <container-name> sh -c 'exec mysqldump <database> -uroot' | ssh <remote_server> mysql -uroot <database>`
> This will take an existing database and dump the contents of the database in to a named database on a remote server

* `ssh <remote_server> mysqldump <database> | docker exec <container-name> sh -c 'exec mysql <database> -uroot'`
> This will take a existing database on a remote server and dump the contents inside named local database. 

---

### Building the image with alternative arguments.

It is also possible to build this image with a different UID and GID. You'll need to reference the Github repository as a context and add the arguments to the `docker-compose.yml` file. For example: 

```
services:
  wordpress:
    image: jamesgreenaway/wordpress:latest
    build:
      context: https://github.com/JamesGreenaway/wordpress.git
      args:
        LOCAL_UID: 1001 
... 
```

> This is useful to modify if you are using a Linux device to run this image and your UID is not 1000. Editing this argument will edit the UID and GID for the user inside your container to match the UID of your local machine.

You can then run `docker-compose up -d --build` to build your container with the new argument values. 

--- 

## Reference

### Environment Variables 

#### For mysql service:
* `MYSQL_ALLOW_EMPTY_PASSWORD: "yes"`
> Run MySQL without the need for a password.
* `MYSQL_ROOT_PASSWORD: password`
> Run MySQL with a password.
*Important*: You must choose either one or the other.

#### For wordpress service:  
* `WORDPRESS_DB_USER: root`
> *Mandatory*: Needed so that the Wordpress instance can create database entries. 
* `WORDPRESS_DB_PASSWORD: password`
> *Mandatory*: Needed so that the Wordpress instance can create database entries. Must match `MYSQL_ROOT_PASSWORD` (if used). If `MYSQL_ALLOW_EMPTY_PASSWORD` is used please input: `WORDPRESS_DB_PASSWORD: ""`
* `WORDPRESS_DB_NAME: example`
> *Mandatory*: Creates a database using this name.
* `SITE_URL: https://example.test`
> *Mandatory*: Sets the website name inside Wordpress and is also used as a basis to set the `ServerName` for Apache's Virtual Hosts.
* `WORDPRESS_DB_HOST: mysql`
> *Optional*: The name of our mysql service acts as its hostname. Change this if you have named your service differently or you are running multiple mysql services. Defaults to `mysql`.

## Example Project 

`./traefik/docker-compose.yml`

```
version: "3.7"
services:
  traefik:
    restart: always
    image: traefik:v2.0.0-rc2
    ports:
      - 80:5000
      - 443:443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./dynamic_conf.toml:/config/dynamic_conf.toml:ro
      - ./certificates:/certificates:ro
    command: 
      --entrypoints.web.address=:5000
      --providers.docker=true 
      --providers.docker.network=traefik
      --entrypoints.web-secure.address=:443
      --providers.file.filename=/config/dynamic_conf.toml
      --providers.file.watch=true
    networks:
      - traefik
networks:
  traefik:
    external: true
```

`./traefik/dynamic_conf.toml`

```
[tls]
  [[tls.certificates]]
    certFile = "/certificates/example-cert.pem"
    keyFile = "/certificates/example-key.pem"
```

`./traefik/certificates/`

```
./example-cert.pem
./example-key.pem
```

`./example/docker-compose.yml`

```
version: "3.7"
services:
  mysql:
    image: mysql:8.0
    restart: always
    volumes:
      - mysql:/var/lib/mysql
    environment:
      MYSQL_ALLOW_EMPTY_PASSWORD: "yes"
    command: --default-authentication-plugin=mysql_native_password
  wordpress:
    image: jamesgreenaway/wordpress:latest 
    restart: unless-stopped
    environment:
      WORDPRESS_DB_USER: root
      WORDPRESS_DB_PASSWORD: ""
      WORDPRESS_DB_NAME: ${COMPOSE_PROJECT_NAME}
      SITE_URL: https://${COMPOSE_PROJECT_NAME}.test
    volumes:
      - ./wordpress:/var/www/html
    labels:
      - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1.entrypoints=web
      - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1.rule=Host(
        `${COMPOSE_PROJECT_NAME}.test`, `www.${COMPOSE_PROJECT_NAME}.test`)
      - traefik.http.services.${COMPOSE_PROJECT_NAME}-wordpress1.loadbalancer.server.port=5000
      - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1-secure.tls=true
      - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1-secure.entrypoints=web-secure
      - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1-secure.rule=Host(
        `${COMPOSE_PROJECT_NAME}.test`, `www.${COMPOSE_PROJECT_NAME}.test`)
      - traefik.http.routers.${COMPOSE_PROJECT_NAME}-wordpress1.middlewares=https
      - traefik.http.middlewares.https.redirectscheme.scheme=https
    depends_on: 
      - mysql
    networks:
      - default
      - traefik
volumes: 
  mysql: {}
networks:
  traefik:
    external: true
```
