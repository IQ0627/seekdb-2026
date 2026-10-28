# 第六届 OceanBase 数据库大赛 · seekdb 方向 · 赛题一：部署一个 seekdb

本仓库为赛题一的提交材料：在 Windows 11 + WSL2 环境部署并启动 seekdb 1.4.0，完成 SQL 连接验证，并给出实例 `run/telemetry.json` 中的 `content.id`。

## 提交物

| 项 | 值 |
| --- | --- |
| content.id | `7b7a5b83-584e-82df-a662-72541077f5e0` |
| 生成时间 | 2026-10-28 18:38:15 (UTC+8) |
| 实例版本 | 1.4.0.0（deb 包 `seekdb 1.4.0-100000212026082616`） |
| 监听端口 | 2881 |
| 原始文件 | [telemetry.json](./telemetry.json) |

## 环境

- Windows 11 / WSL2
- 发行版 `oceanbase-desktop`（Ubuntu 24.04.3 LTS，x86_64，systemd 已启用）
- seekdb 1.4.0.0，由 systemd 托管：`seekdb.service`
- 部署目录：`/var/lib/seekdb`（配置文件 `/etc/seekdb/seekdb.cnf`）

## 部署步骤

### 1. 安装（本机已完成，记录备查）

```bash
# 在 WSL 内执行
curl -fsSL https://obbusiness-private.oss-cn-shanghai.aliyuncs.com/download-center/opensource/seekdb/seekdb_install.sh | sudo bash
```

### 2. 启动

```powershell
wsl.exe -d oceanbase-desktop --exec sudo systemctl start seekdb
wsl.exe -d oceanbase-desktop --exec systemctl status seekdb --no-pager
```

预期状态：`Active: active (running)`，且 `Status: "seekdb is ready and running"`。

### 3. 连接并执行 SQL

```powershell
wsl.exe -d oceanbase-desktop --exec mysql -h 127.0.0.1 -P 2881 -uroot -Dtest
```

执行 [verify.sql](./verify.sql)，实际输出见 [verify-output.txt](./verify-output.txt)：

- `select 1` → `1`
- `version()` → `5.7.25-OceanBase seekdb-v1.4.0.0`
- 库列表：`information_schema` / `mysql` / `oceanbase` / `test`
- 建库建表 + 插入 + 查询 + 删库，全程通过

### 4. 读取 content.id

```powershell
wsl.exe -d oceanbase-desktop --exec python3 -c "import json;print(json.load(open('/var/lib/seekdb/run/telemetry.json'))['content']['id'])"
# → 7b7a5b83-584e-82df-a662-72541077f5e0
```

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `telemetry.json` | 实例运行目录 `run/telemetry.json` 的原样拷贝 |
| `verify.sql` | 连接性与基本 SQL 验证脚本（验证完自动删库，不留残留） |
| `verify-output.txt` | 上述脚本在实例上的实际输出 |

## 备注

- `telemetry.json` 由内核在**首次 bootstrap**（空数据目录初始化）后自动生成于 `<base-dir>/run/telemetry.json`；用已有数据目录重启不会重新生成。
- 默认 `root` 空密码，仅监听本机/内网，请勿暴露公网。
- 经 WSL 传参时要写成 `-h 127.0.0.1 -P 2881`（空格分隔），写成一体会被截断为 `127` 而连接失败。
- seekdb 不支持 `create temporary table`（报错 `ERROR 1235 ... MySQL compatible temporary table not supported`），演示用普通表 + 用完即删。
