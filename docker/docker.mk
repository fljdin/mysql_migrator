export COMPOSE_FILE=docker/docker-compose.yml
export COMPOSE_PROJECT_NAME=mysql_migrator

export PGHOST=172.19.0.3
export PGPORT=5432
export PGUSER=postgres

docker-up:
	docker-compose build
	docker-compose up --detach

docker-install:
	docker exec -it \
	  -w /usr/local/src/mysql_migrator \
	  $(COMPOSE_PROJECT_NAME)-postgresql_db-1 \
	  make install