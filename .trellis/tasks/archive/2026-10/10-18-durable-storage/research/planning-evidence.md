# A 阶段开工前核对

日期：2026-10-18。代码基线：`a078aa3`。状态：只读核对及规划，未安装依赖、未连接数据库、未编译候选依赖，也未执行存储测试。

## 仓库证据

- 根 `mix.exs` 使用 umbrella；运行依赖必须声明在所属子应用，不能只加到根开发工具依赖。
- `BEAMLET_BACKEND_BUILD=1` 的应用白名单目前不包含 `beamlet_storage`；新增应用时必须同步该白名单，不能等 F 阶段才发现后端构建看不到应用。
- `apps/beamlet_runtime/mix.exs` 仅依赖 Actions；`apps/beamlet_agent/mix.exs` 依赖 Actions/Runtime/Harness，均无 Repo 或 Ecto。A 不修改其业务依赖/执行路径，B/C 再按使用位置接入 Storage。
- `apps/beamlet_node/lib/beamlet/node.ex` 的配置白名单无存储选项。A 提供可由测试/嵌入 supervisor 显式启动的 Repo，但不提前扩展 Node 配置或宿主环境变量；B/C 的测试组合可显式监督它们，F 再收敛产品启动配置。
- `apps/beamlet_actions/lib/beamlet/actions/operation.ex` 的 Operation 上限为 262144 Erlang 序列化字节，包含临时 credentials；`contracts.ex` 的 Result 上限为 1048576 Erlang 序列化字节。持久 JSON 编码后的字节数与 wire 字节数不同，不能直接复用后声称等价。
- `apps/beamlet_harness/lib/beamlet/harness/context.ex` 上下文上限为 128 条消息和 1048576 JSON 字节。展示裁剪与该完整上下文不是一回事。
- `mix.lock` 已有 Jason 1.4.5；新增 Storage 如直接调用 Jason，必须在自己的 manifest 声明，而非借用兄弟应用的传递依赖。
- `flake.nix` 选择 OTP 29 / Elixir 1.20。当前 PATH 能找到 Mix，未找到 psql、postgres、pg_isready 或 sqlite3。未找到 CLI 不证明数据库服务不存在；但当前没有已验证的 PostgreSQL 测试连接，也没有可宣称双库通过的证据。

## 候选依赖：仅元数据兼容，未实际解析/编译

核对官方 Hex release API，而非凭 latest_version 推断稳定版。Postgrex 包的 latest_version 指向历史 1.0 RC，须使用稳定 release。

| 包 | A 建议的直接版本 | 官方声明 | 判断 |
| --- | --- | --- | --- |
| Ecto | 3.14.0 | Elixir ~> 1.14，Decimal ~> 3.0 | 与本仓库 Elixir 声明无明显冲突 |
| ecto_sql | 3.14.0 | Ecto ~> 3.14.0，DBConnection ~> 2.9，Decimal ~> 3.0 | 与下列 adapters 的约束可相交 |
| ecto_sqlite3 | 0.25.0 | Elixir ~> 1.17，Ecto/ecto_sql ~> 3.14，Exqlite ~> 0.22 | 必须实际编译并核对所解析 Exqlite/SQLite 版本 |
| postgrex | 0.22.4 | Elixir ~> 1.15，DBConnection ~> 2.9，Decimal 支持 ~> 3.0 | 使用稳定版，不选历史 1.0 RC |
| Jason | 1.4.5 | 当前仓库已锁定；lock 中 Decimal 可选范围包含 ~> 3.0 | 保持现有版本，实际求解后核对锁文件差异 |

建议实现时先以这些直接版本精确固定、正常生成根 mix.lock，不使用 override 或忽略依赖冲突。若候选被撤回/安全要求变化/OTP 29 编译失败，暂停并修订版本评审，不强装；实际兼容性必须由 deps 解析、warning-fatal 编译及两库测试证明。此次核对没有锁定传递依赖或嵌入 SQLite 引擎，也没有跑安全扫描。

## SQLite 选项依据

固定版本 0.25.0 的 adapter 文档确认：journal_mode 默认 wal，synchronous 默认 normal，foreign_keys 默认 on，busy_timeout 默认 2000ms，pool_size 默认 5，事务默认 deferred；可按 transaction 的 mode 选 immediate。FULL 必须显式设置，不能把默认 NORMAL 当成耐久保证。A 的写事务采用 immediate，并实际核对提交、竞争和错误语义；不在事务中做网络 I/O。

## 官方来源

以下在本次规划中只做内容读取，没有执行外部项目：

- [Ecto 3.14.0 release metadata](https://hex.pm/api/packages/ecto/releases/3.14.0)
- [ecto_sql 3.14.0 release metadata](https://hex.pm/api/packages/ecto_sql/releases/3.14.0)
- [ecto_sqlite3 0.25.0 release metadata](https://hex.pm/api/packages/ecto_sqlite3/releases/0.25.0)
- [postgrex 0.22.4 release metadata](https://hex.pm/api/packages/postgrex/releases/0.22.4)
- [SQLite adapter 0.25.0 options](https://hexdocs.pm/ecto_sqlite3/0.25.0/Ecto.Adapters.SQLite3.html)

## 开工/验收门

- 用户尚未批准 A 激活实施；不能用此次资料读取替代 task.py start 前的评审。
- 获批后可添加候选依赖和测试设施，先证明兼容性再推进实现。
- PostgreSQL 测试实例须为显式指定的隔离库，不使用未知现有业务库；不可因本机工具缺失把双库验收降级成 SQLite-only。
- 未验证的具体 adapter 行为、测试服务和性能只记为待证，不写成已通过。
