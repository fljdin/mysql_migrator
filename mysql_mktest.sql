CREATE SCHEMA partitions;

CREATE TABLE partitions.employees (
    id INT NOT NULL,
    fname VARCHAR(30),
    lname VARCHAR(30),
    hired DATE NOT NULL DEFAULT '1970-01-01',
    separated DATE NOT NULL DEFAULT '9999-12-31',
    job_code INT,
    store_id INT
)

CREATE TABLE partitions.employees_by_list (
    id INT NOT NULL,
    fname VARCHAR(30),
    lname VARCHAR(30),
    hired DATE NOT NULL DEFAULT '1970-01-01',
    separated DATE NOT NULL DEFAULT '9999-12-31',
    job_code INT,
    store_id INT
)
PARTITION BY LIST(store_id) (
    PARTITION pNorth VALUES IN (3,5,6,9,17),
    PARTITION pEast VALUES IN (1,2,10,11,19,20),
    PARTITION pWest VALUES IN (4,12,13,14,18),
    PARTITION pCentral VALUES IN (7,8,15,16)
);

CREATE TABLE partitions.employees_by_int_range (
    id INT NOT NULL,
    fname VARCHAR(30),
    lname VARCHAR(30),
    hired DATE NOT NULL DEFAULT '1970-01-01',
    separated DATE NOT NULL DEFAULT '9999-12-31',
    job_code INT NOT NULL,
    store_id INT NOT NULL
)
PARTITION BY RANGE (store_id) (
    PARTITION p_less_than_6 VALUES LESS THAN (6),
    PARTITION p_less_than_11 VALUES LESS THAN (11),
    PARTITION p_less_than_16 VALUES LESS THAN (16),
    PARTITION p_less_than_21 VALUES LESS THAN (21),
    PARTITION p_less_than_max VALUES LESS THAN MAXVALUE
);

CREATE TABLE partitions.employees_by_date_range (
    id INT NOT NULL,
    fname VARCHAR(30),
    lname VARCHAR(30),
    hired TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    separated TIMESTAMP NOT NULL,
    job_code INT NOT NULL,
    store_id INT NOT NULL
)
PARTITION BY RANGE (UNIX_TIMESTAMP(hired)) (
    PARTITION pre2000 VALUES LESS THAN (UNIX_TIMESTAMP('2000-01-01 00:00:00')),
    PARTITION post2000 VALUES LESS THAN MAXVALUE
);

CREATE TABLE partitions.employees_by_hash (
    id INT NOT NULL,
    fname VARCHAR(30),
    lname VARCHAR(30),
    hired DATE NOT NULL DEFAULT '1970-01-01',
    separated DATE NOT NULL DEFAULT '9999-12-31',
    job_code INT,
    store_id INT
)
PARTITION BY HASH(store_id) PARTITIONS 4;

CREATE TABLE partitions.subpart_by_range_hash (id INT, purchased DATE)
    PARTITION BY RANGE( YEAR(purchased) )
    SUBPARTITION BY HASH( TO_DAYS(purchased) )
    SUBPARTITIONS 2 (
        PARTITION subpart_less_than_1990 VALUES LESS THAN (1990),
        PARTITION subpart_less_than_2000 VALUES LESS THAN (2000),
        PARTITION subpart_less_than_max VALUES LESS THAN MAXVALUE
    );