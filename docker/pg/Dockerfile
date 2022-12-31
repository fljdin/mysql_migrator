FROM postgis/postgis:latest
RUN apt-get update && apt-get install -y \
    make \
    wget \
    postgresql-15-mysql-fdw

RUN mkdir -p /usr/local/src

# install db_migrator
ARG db_migrator_release="0.9.0"
ENV db_migrator_url="https://github.com/cybertec-postgresql/db_migrator/archive/refs/heads/master.tar.gz"
RUN wget ${db_migrator_url} -O - | tar -xzC /usr/local/src ; \
    make -C /usr/local/src/db_migrator-master install