include docker/docker.mk
EXTENSION = mysql_migrator
DATA = mysql_migrator--*.sql
REGRESS = install migrate check_results migrate_finish partitioning

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all:
	@echo 'Nothing to be built. Run "make install".'