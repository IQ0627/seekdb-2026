create database if not exists t1db;
use t1db;

-- ============ A. ai_prompt LOB 表（官方 ai_function_enhancement 第 8-13 行）============
drop table if exists ai_enhance_prompt;
create table ai_enhance_prompt(t longtext, a text);
insert into ai_enhance_prompt values('{0}-ok', 'lob');
select ai_prompt(t, a) from ai_enhance_prompt;
drop table ai_enhance_prompt;

-- ============ B. endpoint max_concurrency（官方 ai_model_endpoint_ddl）============
call DBMS_AI_SERVICE.DROP_AI_MODEL('my_model1');
call DBMS_AI_SERVICE.DROP_AI_MODEL_ENDPOINT('my_model_endpoint1');
call DBMS_AI_SERVICE.CREATE_AI_MODEL('my_model1', '{"type":"completion","model_name":"my_model1"}');
call DBMS_AI_SERVICE.CREATE_AI_MODEL_ENDPOINT(
  'my_model_endpoint1',
  '{"ai_model_name":"my_model1","scope":"all","url":"https://www.baidu.com/","access_key":"sk-xxxxxxxxxxxx","provider":"openai","max_concurrency": 3}');
select ENDPOINT_NAME, AI_MODEL_NAME, PROVIDER, MAX_CONCURRENCY from oceanbase.DBA_OB_AI_MODEL_ENDPOINTS
  where ENDPOINT_NAME = 'my_model_endpoint1';

call DBMS_AI_SERVICE.ALTER_AI_MODEL_ENDPOINT('my_model_endpoint1', '{"provider":"aliyun-openai","max_concurrency":7}');
select ENDPOINT_NAME, PROVIDER, MAX_CONCURRENCY from oceanbase.DBA_OB_AI_MODEL_ENDPOINTS
  where ENDPOINT_NAME = 'my_model_endpoint1';

-- 非法值：0 / 1025 / 字符串 "8" 均应报 11116
call DBMS_AI_SERVICE.ALTER_AI_MODEL_ENDPOINT('my_model_endpoint1', '{"max_concurrency":0}');
call DBMS_AI_SERVICE.ALTER_AI_MODEL_ENDPOINT('my_model_endpoint1', '{"max_concurrency":1025}');
call DBMS_AI_SERVICE.ALTER_AI_MODEL_ENDPOINT('my_model_endpoint1', '{"max_concurrency":"8"}');

-- ============ C. OpenAI completion + config（走 mock）============
call DBMS_AI_SERVICE.DROP_AI_MODEL('enhance_complete');
call DBMS_AI_SERVICE.DROP_AI_MODEL_ENDPOINT('enhance_complete_ep');
call DBMS_AI_SERVICE.CREATE_AI_MODEL('enhance_complete', '{"type":"completion","model_name":"qwen3-32b"}');
call DBMS_AI_SERVICE.CREATE_AI_MODEL_ENDPOINT(
  'enhance_complete_ep',
  '{"ai_model_name":"enhance_complete","scope":"all","url":"http://0.0.0.0:8000/compatible-mode/v1/chat/completions","access_key":"mock-key","provider":"openai"}');
select length(ai_complete('enhance_complete', 'hello', null)) > 0 as complete_ok;
select length(ai_complete('enhance_complete', ai_prompt('describe {0}', json_object('text','你好')), '{"temperature":0.2,"max_tokens":16}')) > 0 as complete_config_ok;

-- ============ D. OpenAI embedding + dimension + batch ============
call DBMS_AI_SERVICE.DROP_AI_MODEL('enhance_embed');
call DBMS_AI_SERVICE.DROP_AI_MODEL_ENDPOINT('enhance_embed_ep');
call DBMS_AI_SERVICE.CREATE_AI_MODEL('enhance_embed', '{"type":"dense_embedding","model_name":"text-embedding-v1"}');
call DBMS_AI_SERVICE.CREATE_AI_MODEL_ENDPOINT(
  'enhance_embed_ep',
  '{"ai_model_name":"enhance_embed","scope":"all","url":"http://0.0.0.0:8000/compatible-mode/v1/embeddings","access_key":"mock-key","provider":"openai"}');
select json_length(ai_embed('enhance_embed', 'single-row')) as embed_dimension;
select json_length(ai_embed('enhance_embed', 'dimension-row', 768)) as requested_dimension;

drop table if exists ai_enhance_batch;
create table ai_enhance_batch(id int primary key, content text);
insert into ai_enhance_batch values(1,'first'),(2,null),(3,'third');
select id, json_length(ai_embed('enhance_embed', content)) as dimension
  from ai_enhance_batch order by id;
drop table ai_enhance_batch;

-- ============ E. rerank ============
call DBMS_AI_SERVICE.DROP_AI_MODEL('enhance_rerank');
call DBMS_AI_SERVICE.DROP_AI_MODEL_ENDPOINT('enhance_rerank_ep');
call DBMS_AI_SERVICE.CREATE_AI_MODEL('enhance_rerank', '{"type":"rerank","model_name":"BAAI/bge-reranker-v2-m3"}');
call DBMS_AI_SERVICE.CREATE_AI_MODEL_ENDPOINT(
  'enhance_rerank_ep',
  '{"ai_model_name":"enhance_rerank","scope":"all","url":"http://0.0.0.0:8000/v1/rerank","access_key":"mock-key","provider":"siliconflow"}');
select json_length(ai_rerank('enhance_rerank','apple','["apple","banana","fruit","vegetable"]', null)) as rerank_count;
select json_unquote(json_extract(r, '$[0].id')) as first_id, json_length(r) as rerank_count
  from (select ai_rerank('enhance_rerank','apple','[{"id":"a","text":"apple"},{"id":"b","text":"banana"}]','text') as r) x;

-- ============ F. Ollama provider（access_key 可为空）============
call DBMS_AI_SERVICE.DROP_AI_MODEL('enhance_ollama_complete');
call DBMS_AI_SERVICE.DROP_AI_MODEL_ENDPOINT('enhance_ollama_complete_ep');
call DBMS_AI_SERVICE.CREATE_AI_MODEL('enhance_ollama_complete', '{"type":"completion","model_name":"qwen2.5"}');
call DBMS_AI_SERVICE.CREATE_AI_MODEL_ENDPOINT(
  'enhance_ollama_complete_ep',
  '{"ai_model_name":"enhance_ollama_complete","scope":"all","url":"http://0.0.0.0:8000/api/generate","access_key":"","provider":"ollama"}');
select PROVIDER from oceanbase.DBA_OB_AI_MODEL_ENDPOINTS where ENDPOINT_NAME='enhance_ollama_complete_ep';
select length(ai_complete('enhance_ollama_complete','hello',null)) > 0 as ollama_complete_ok;

call DBMS_AI_SERVICE.ALTER_AI_MODEL_ENDPOINT('enhance_ollama_complete_ep', '{"provider":"Ollama"}');
select PROVIDER from oceanbase.DBA_OB_AI_MODEL_ENDPOINTS where ENDPOINT_NAME='enhance_ollama_complete_ep';

call DBMS_AI_SERVICE.DROP_AI_MODEL('enhance_ollama_embed');
call DBMS_AI_SERVICE.DROP_AI_MODEL_ENDPOINT('enhance_ollama_embed_ep');
call DBMS_AI_SERVICE.CREATE_AI_MODEL('enhance_ollama_embed', '{"type":"dense_embedding","model_name":"nomic-embed-text"}');
call DBMS_AI_SERVICE.CREATE_AI_MODEL_ENDPOINT(
  'enhance_ollama_embed_ep',
  '{"ai_model_name":"enhance_ollama_embed","scope":"all","url":"http://0.0.0.0:8000/api/embed","access_key":"","provider":"OLLAMA"}');
select PROVIDER from oceanbase.DBA_OB_AI_MODEL_ENDPOINTS where ENDPOINT_NAME='enhance_ollama_embed_ep';
select json_valid(ai_embed('enhance_ollama_embed','ollama-embed')) as ollama_embed_ok;

-- ============ G. 清理 ============
call DBMS_AI_SERVICE.DROP_AI_MODEL('my_model1');
call DBMS_AI_SERVICE.DROP_AI_MODEL_ENDPOINT('my_model_endpoint1');
