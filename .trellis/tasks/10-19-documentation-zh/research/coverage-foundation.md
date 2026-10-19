# foundation 中文实施交接

状态：COMPLETE（仅 foundation 组件；不代表中文阶段集成验收完成）。

## 范围与依据

已完整阅读 `apps/beamlet_storage/lib` 下 15 个生产文件、既有 README.md 与 mix.exs；编辑只涉及同组件源码文档/注释、新中文 README 和本交接。保留有效英文，未启动英文翻译，未改 executable AST、类型/spec/签名、配置、测试或依赖。未修改共同 coverage.md、父任务或其他组件文件；未提交、暂存、切分支或激活/归档任务。

读取中文任务及父任务 PRD/design/implement、implement.jsonl 的五项上下文、lanes.md、before-dev 技能、backend index/directory/quality/typespec/database/error 规范及 guides index。相邻证据：完整阅读 foundation_test.exs、foundation_postgres_test.exs、codec_test.exs、no_load_side_effects_test.exs、Node Storage.Operator；查看 Node Storage.open 的 Host/Admission 组合、Actions OperationRecords.prepare_in_transaction 的参与者调用及 Agent Inheritance.input_artifact 的按摘要复用。未将这些调用方局部阅读记为其他组件全文件覆盖。

## 逐文件审阅与说明决策

下列路径均以 `apps/beamlet_storage/lib/beamlet/storage/` 为前缀。

| 文件 | 实际模块、公共 API/类型与关键约束 | 内部说明边界 |
| --- | --- | --- |
| admission.ex | `Beamlet.Storage.Admission`；start_link/1、status/1、admitted?/1、consult/1、failure/2、probe/2；status 类型；init/1、handle_call/3、handle_cast/2 回调已补中文。明确主资源+resources、初始 reason、未配置门放行、同步记录拒绝、status 才能清除已记录失败。 | probe/write_probe/rollback_probe、checks 等私有函数依模块及关键注释解释。回滚探针不提交、不证明 fsync；不逐行复述 GenServer 状态分支。 |
| artifact_changeset.ex | 隐藏 `Beamlet.Storage.ArtifactChangeset`；build/3 及所有校验分支已读。拒绝未知字段、结构体及混合键，检查 UUID/非负 size/摘要/字符串约束。 | 保留 moduledoc false，增加内部边界注释；不把 schema helper 发布为用户 API。homogeneous?/invalid/validate_* 简单辅助不重复加 doc。 |
| artifacts.ex | `Beamlet.Storage.Artifacts`；changeset/1、put/2、fetch/2、verify_references/2、error 类型已补说明。事务要求、16MiB、UUID/摘要/字节一致性、重复 ID/摘要 conflict、读失败与缺失分开。 | insert/validation_error/do_fetch/validate_stored/verify_reference 由对应公共函数说明覆盖；put 本身不做摘要复用，驱动异常交外层事务。 |
| codec.ex | `Beamlet.Storage.Codec`；limit/1、encode/2、decode/2、digest/2、hash/1、uuid?/1；value/object/error 类型均说明。默认 4MiB/正整数预算、深度32/节点100000、键排序、整数/浮点差异、重复键及凭据字段拒绝。 | walk/spend/canonical/plain_objects/scan_depth 逐一读过。解析前限深增加中文注释，原有凭据分段/预算说明保留；不为每个递归分支增加同义注释。普通文本不扫描秘密。 |
| connections.ex | 隐藏 `Beamlet.Storage.Connections`；sqlite/1、postgres/1、verify_sqlite/1、verify_postgres/1 全读。固定 pool、timeout、WAL/FULL/FK、after_connect、PG fsync/synchronous_commit。 | 保留 moduledoc false，中文注释说明每条物理连接/重连验证、Exqlite busy handler 与 PRAGMA=0；不改变配置，也不公开隐藏 helper。 |
| dataset.ex | `Beamlet.Storage.Dataset`；initialize/open/verify 各 /2，error/options 类型已补说明。明确成功链接 PID 的停止责任、已注册 Repo conflict、绝对无符号链接/无别名 SQLite 双路径、PG 空库前提、拒绝旧格式/不完整安装。 | 全读 validate/path/prepare/preflight/read/metadata/migration/safely 辅助；只读格式预检加中文说明。不将每个资源释放 try/after 写成逐行注释。失败可留不完整目标，不自动删除/重试。 |
| host.ex | `Beamlet.Storage.Host`；start_link/1、handles/1、status/1、resource 类型；init/handle_call/handle_info/terminate 回调已补中文。key/Repo 唯一，单项打开失败保留原因，只关成功取得的 Repo，不自动重开。 | valid?/call 简单配置与调用包装由公共说明覆盖；handles 是已打开句柄，非当前准入证据。 |
| installation.ex | `Beamlet.Storage.Installation`；foundation_component/0、foundation_migration/0、validate/1、manifest/1；component/migration/t 类型已补中文。精确字段、每组件迁移、ID递增、编译模块、身份持久化与不可变要求。 | valid_*、exact?/unique?/ordered_ids? 等谓词完整阅读，模块与 validate 契约已集中说明；不增加机械同义注释。清单不校验源码哈希。 |
| json.ex | 隐藏 `Beamlet.Storage.JSON`；init/type/max_bytes/cast/dump/load 的全部分支已读。显式 max_bytes，cast/dump/load 严格走 Codec，nil 按 Ecto 约定保留。 | 保留 moduledoc false，增加类型内部边界注释；不公开 Ecto 参数化类型回调，不重复解释每个转接分支。 |
| migrations.ex | `Beamlet.Storage.Migrations` 的 install_metadata/3、install/2；`Beamlet.Storage.Migrations.FoundationV1` 的 up/down 各 /0 已补模块与函数中文。先 installed=false、完整迁移后 true，仅共享表及摘要索引，down 抛出只向前错误。 | 无更改 SQL、迁移实现/ID。说明这些是 Dataset 初始化内部入口，open/verify 不调用；不引入升级工具承诺。 |
| references.ex | `Beamlet.Storage.References`；ids/1、verify/2、verify_read/2 已补中文。仅识别 artifact_id/artifact_ids/artifact_refs 字符串键，后两者要求列表，verify 去重后在事务内校验。 | collect/field/verify_read_ids 全读。明确遍历依赖调用方有界信封；ids 不校验 UUID、不去重，verify_read 不要求写事务，也没有事务内1024数量上限。 |
| repo.ex | `Beamlet.Storage.Repo`；__using__/1 宏已补中文，只支持 sqlite/postgres，其他 adapter 抛 ArgumentError，生成模块名注册实例。 | 生成 Repo.init/2 保持 impl/spec，仅增加内部注释；框架生成 Repo API 不逐一重写文档，不把 start_link 等同数据集验证。 |
| repos.ex | `Beamlet.Storage.SQLiteRepo`、`Beamlet.Storage.PostgresRepo` 模块说明已补中文。 | 两个 use 声明无额外手写 API；沿用 Repo 宏及 Ecto 契约，不添加空泛函数说明。 |
| schema/artifact.ex | 隐藏 `Beamlet.Storage.Schema.Artifact`；t 类型保留既有英文并加中文，changeset/2 及全部分支已读；未插入结构允许 nil，内容最多16MiB、摘要/size 一致。 | 保留 moduledoc false，增加内部注释，不公开 schema 生命周期/框架生成函数；不改字段或验证表达式。 |
| transaction.ex | `Beamlet.Storage.Transaction`；participate/2、write/2（函数及 Multi）、read/1、write_error 类型均补中文。无嵌套提交、调用方显式 rollback；函数仅返回 error 不自动回滚；SQLite immediate，结果未知无自动重试。 | 全读 SQLite/PG 约束分类和严格 JSON load 分类；新增确定拒绝 vs 断连未知注释，保留原异常/堆栈边界，不把无关 ArgumentError/RuntimeError 归为安全错误。 |

## 文档交付

- 新建 `apps/beamlet_storage/README_zh.md`：职责/依赖边界、工具链及根目录启动入口、显式 foundation 安装/打开例子、单事务制品+引用示例、Codec 示例、Host/Admission 所有权示例、真实错误表和根目录验证命令。
- 既有 `apps/beamlet_storage/README.md` 原样保留；中文只链接确已存在的 English README 和部署说明，未创建英文新翻译。
- 以上15源文件为源码文档交付；本文件为唯一组件覆盖交接。

## 实际验证

均从仓库根目录执行：

| 检查 | 实际结果 |
| --- | --- |
| `mix format <15个owned .ex路径>` | 通过，仅格式化 owned Elixir 文件；最后单独格式化 admission.ex。 |
| `mix format --check-formatted <15个owned .ex路径>` | 通过。 |
| `mix compile --warnings-as-errors` | 通过，无 warning；只做文档/注释，无依赖更新。 |
| `mix test apps/beamlet_storage/test --seed 631927` | 15 passed、2 excluded（postgres_db）；含10 SQLite foundation、4 Codec、1 fresh-VM 无副作用测试。锁竞争测试出现预期 database locked 驱动日志，但套件通过。 |
| `elixir scripts/quality/check-contracts-test.exs` | 40 passed。 |
| `elixir scripts/quality/check-contracts.exs` | 148 files / 1345 functions，missing0/errors0；foundation public55、template1、macro1、private61 全覆盖。此检查是 spec 存在性，不替代语义阅读。 |
| 编辑前快照与结果 AST 对比 | `/tmp/foundation_ast.exs` 解析15文件，递归清除位置元数据及 doc/moduledoc/typedoc 属性后完全相同。快照 `/tmp/beamlet-foundation-before` 在首次编辑前从 owned lib 拷贝；当时本组件 git status 干净。 |
| 既有文档保留检查 | 原源码每个 doc/moduledoc/typedoc 字符串均作为完整子串存在于结果，已验证。 |
| README 相对链接/示例核对 | 两个相对链接均存在；示例逐个与源码及测试匹配，未实际运行写库示例。 |
| `git diff --check` | 通过；最终交接写入后再次检查。 |

## 剩余验证与风险

- PostgreSQL 2 个测试因未配置 `BEAMLET_PG_SOCKET_DIR`/服务被排除，未执行，不算通过；没有新增物理主机、断电、付费模型或部署验证声明。
- 完整项目 format、全量 tests、Credo strict、Dialyzer、Sobelow、Gettext 门由 integration 执行；本组件没有运行或推断这些门已通过。
- README 中安装与宿主例子会写库，只做源码/测试核对，没有另行执行示例；现有测试实际验证对应 SQLite 调用和无副作用启动。
- 临时 AST 工具/快照位于 /tmp，未纳入源码交付。集成可再次以 git 基线去除文档属性复核。
- 未发现需要产品授权的新行为缺口；无源码文档剩余项。保留隐藏模块和简单私有辅助属于有理由的覆盖决定，不扩展公共可见性。
