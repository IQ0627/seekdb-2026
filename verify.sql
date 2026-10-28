-- 赛题一：连接性与基本 SQL 验证（DDL/DML 用完后整库删除，不留残留数据）
select 1 as ok;
select version() as version;
show databases;
create database if not exists seekdb_demo;
use seekdb_demo;
create table t_demo (id int primary key, name varchar(32));
insert into t_demo values (1, 'seekdb');
select * from t_demo;
select count(*) as cnt from t_demo;
drop database seekdb_demo;
show databases;
