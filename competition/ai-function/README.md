# 赛题一：AI 函数增强（60 分）

本目录记录 2026 seekdb 大赛「AI 函数增强」赛题的实现与验证。

## 一、目标与范围

赛题要求在 seekdb 已有的 `AI_PROMPT`、`AI_COMPLETE`、`AI_EMBED`、`AI_RERANK` 与
AI Model Endpoint 管理之上，补齐六项能力：

| 子题 | 要求 |
| --- | --- |
| AI_PROMPT 类型与模板增强 | TEXT/LONGTEXT、JSON、嵌套 Prompt、重复与非法占位符、Unicode 与转义 |
| AI_EMBED 单行语义 | 单行/多行、正整数 dimension、向量维度与元素合法性 |
| AI_COMPLETE 请求与响应 | 普通 Prompt、AI_PROMPT、JSON config、长文本与异常响应 |
| Ollama Provider | Endpoint 增删改查、免 API Key、大小写兼容、非流式生成与 Embedding |
| AI_RERANK 结果正确性 | 字符串/对象数组、分批、全局 index 映射、稳定排序与返回校验 |
| AI_EMBED 跨行批量 | 一次请求多输入、乱序响应、NULL、过滤、LIMIT、多批次 |

比赛不考察模型效果，模型请求由本地 Mock AI Service 响应。

## 二、行为变化（修复前 → 修复后）

1. `ai_prompt` 的 JSON 参数
   - 前：`select ai_prompt('{0}/{0}/{1}', json_array(1,true), json_object('k',2));`
     → `ERROR 1235 json type is not supported`。
   - 后：`{"args": [[1, true], {"k": 2}], "template": "{0}/{0}/{1}"}`，JSON 结构原样保留。
2. `ai_prompt` 的 LOB 模板
   - 前：模板列类型为 `text/blob/mediumtext/longtext/tinyblob` 时 → `ERROR 5083`。
   - 后：`create table t(t longtext, a text); select ai_prompt(t,a)` → `{"args": ["lob"], "template": "{0}-ok"}`。
3. `ai_prompt` 的非法占位符
   - 前：越界占位符不做校验；非法类型直接 5083。
   - 后：占位符下标越界报 `OB_INVALID_ARGUMENT`；模板或参数类型非法仍为 5083；
     `ai_prompt('')` 为 1210；`ai_prompt()` 为 1582。
4. AI Model Endpoint 的 `max_concurrency`
   - 前：JSON 中出现该键 → `ERROR 11115`（未知参数）。
   - 后：`1..1024` 合法，`DBA_OB_AI_MODEL_ENDPOINTS` 新增 `MAX_CONCURRENCY` 列；
     `0`、`1025`、字符串 `"8"` 均报
     `ERROR HY000: The value of param 'max_concurrency' is invalid`（11116）。
5. Ollama Provider
   - 前：`provider: "ollama"` 报 11116（不在合法 provider 列表）。
   - 后：`ollama`/`Ollama`/`OLLAMA` 均可创建，`access_key` 允许为空串，
     `/api/generate` 与 `/api/embed` 走原生 Ollama 协议；provider 大小写按输入原样保留。
6. NULL 参数语义
   - `ai_complete(..., NULL)`：第三参为 SQL NULL 时按"无 config"处理（原来会 3141）。
   - `ai_embed(model, NULL)`：结果为 NULL，批量扫描时按行对齐（原来 1210）。
   - `ai_embed(model, text, NULL)`：视为未指定 dimension（原来 1210）。
   - `ai_rerank(..., NULL)`：第四参为 NULL 时按"未指定 doc_key"处理（原来 1210）。

## 三、改动清单

| 文件 | 改动要点 |
| --- | --- |
| `src/sql/engine/expr/ob_expr_ai/ob_expr_ai_prompt.cpp` | 模板判定改用 `ob_is_string_type` 放行 LOB；JSON 参数走 `ObJsonExprHelper::get_json_doc` 并作为 JSON 节点 append；LOB 字符串用 `ObTextStringHelper::read_real_string_data` 读取 |
| `src/sql/engine/expr/ob_expr_ai/ob_ai_func_utils.cpp` | `get_complete_provider`/`get_embed_provider` 增加 OLLAMA 分支；`is_valid_prompt_object` 放开 args 元素类型限制；`replace_all_str_args_in_template` 支持对象/数组参数并按 `{N}` 重复替换；`ObOllamaUtils::get_header` 补 `Content-Type` |
| `src/sql/engine/expr/ob_expr_ai/ob_expr_ai_complete.cpp` | 允许对象/数组参数进入 prompt；config 为 SQL NULL 时不再解析 JSON |
| `src/sql/engine/expr/ob_expr_ai/ob_expr_ai_embed.cpp` | content 为 NULL 返回 NULL；dimension 为 NULL 视为未指定 |
| `src/sql/engine/expr/ob_expr_ai/ob_expr_ai_rerank.cpp` | 第四参为 NULL 时按未指定 doc_key 处理 |
| `src/share/ai_service/ob_ai_service_struct.h/.cpp` | 新增 `max_concurrency_` 与 getter；`INVALID_MAX_CONCURRENCY=-1`、`MAX_CONCURRENCY_UPPER=1024`；`VALID_PROVIDERS` 增加 `OLLAMA`；`EXTRACT_JSON_ELEM_INT` 宏；ollama 允许空 access_key；范围校验报 11116 |
| `src/observer/ai_service/ob_ai_service_proxy.cpp` | insert/update 写入 `max_concurrency`；读回时 `access_key` 容忍 NULL（原来 4152） |
| `src/observer/ai_service/ob_ai_service_executor.cpp` | 版本哨兵行补 `max_concurrency = 0` |
| `src/share/inner_table/ob_inner_table_schema_def.py` | `__all_ai_model_endpoint` 增加 `max_concurrency` 列；`DBA_OB_AI_MODEL_ENDPOINTS` 视图增加 `MAX_CONCURRENCY` |

## 四、验证

环境：Ubuntu 24.04（WSL2），`./build.py build seekdb` 构建，
新二进制以 `--base-dir=/home/seekdb-run --port=2882` 启动；
本地 Mock AI Service 监听 `0.0.0.0:8000`，实现
`/compatible-mode/v1/chat/completions`、`/compatible-mode/v1/embeddings`、
`/v1/rerank`、`/api/generate`、`/api/embed`。

执行 `verify.sql` 得到的实际输出见 `verify-output.txt`，关键断言：

| 断言 | 结果 |
| --- | --- |
| `ai_prompt(t,a)`（LOB 模板 + text 参数） | `{"args": ["lob"], "template": "{0}-ok"}` |
| `ai_prompt('{0}/{0}/{1}', json_array(1,true), json_object('k',2))` | `{"args": [[1, true], {"k": 2}], "template": "{0}/{0}/{1}"}` |
| CREATE 端点带 `"max_concurrency": 3` | 视图 `MAX_CONCURRENCY = 3` |
| ALTER 端点带 `"max_concurrency": 7` | 视图 `MAX_CONCURRENCY = 7` |
| ALTER 端点 `0` / `1025` / `"8"` | `ERROR 11116 ... The value of param 'max_concurrency' is invalid` |
| `ai_complete('enhance_complete','hello',NULL)` | 1 |
| `ai_complete(..., ai_prompt('describe {0}', json_object('text','你好')), '{"temperature":0.2,"max_tokens":16}')` | 1 |
| `json_length(ai_embed('enhance_embed','single-row'))` | 768 |
| `ai_embed('enhance_embed','dimension-row',768)` | 768 |
| 批量表三行含 NULL | `768 / NULL / 768` |
| `json_length(ai_rerank('enhance_rerank','apple','["apple","banana","fruit","vegetable"]',NULL))` | 4 |
| 对象数组 + `'text'` 选择 | `first_id = a`，`rerank_count = 2` |
| Ollama completion / embedding | 均返回 1（`/api/generate`、`/api/embed`） |
| `provider` 大小写 | `ollama` → `Ollama` → `OLLAMA` 原样保留 |

另对官方 `ai_prompt.test` 的 32 条断言（含 `1582`、`5083`、`1210`、二进制模板尾随 NUL、
group by/having/join/WITH/order by/where/parallel hint）逐条比对，结果一致。

## 五、复现步骤

```bash
# 1. 构建
./build.py build seekdb

# 2. 启动实例（全新目录）
rm -rf /home/seekdb-run && mkdir -p /home/seekdb-run
nohup build/bin/src/observer/seekdb --nodaemon \
  --base-dir=/home/seekdb-run --data-dir=/home/seekdb-run/store \
  --redo-dir=/home/seekdb-run/redo --port=2882 > /home/seekdb-run/stdout.log 2>&1 &

# 3. 启动 Mock AI Service（8000 端口，响应格式见 verify.sql 注释）

# 4. 灌入用例
mysql -h127.0.0.1 -P2882 -uroot --default-character-set=utf8mb4 --force < verify.sql
```
