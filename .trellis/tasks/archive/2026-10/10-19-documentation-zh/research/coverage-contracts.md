# contracts 中文组件交接

状态：中文组件完成，等待父会话集成验收；不启动英文阶段。范围为 Actions 3、Harness 9、Core 4，共 16 个生产文件；已逐个全文阅读。只改文档属性、解释性注释和三个新中文 README，保留原有有效英文与 `Core.Data` 的 `@moduledoc false`；没有新增英文翻译。无宏需补充。

## 逐文件覆盖

以下路径均相对仓库根目录，中文模块说明、公开函数/行为回调与公开类型说明已补齐；没有用文件编辑计数代替 API 审阅。

| 源路径 | 实际模块与已审阅/说明的 API 组 | 关键约束与内部说明决定 |
| --- | --- | --- |
| `apps/beamlet_actions/lib/beamlet/actions.ex` | `Beamlet.Actions`：bounded?/2、credentials?/1；data/json_value/json_object | 普通项 Erlang 序列化大小、深度24、敏感键与凭据 JSON 分离；递归函数为校验细节，不逐条复述分支 |
| `apps/beamlet_actions/lib/beamlet/actions/operation.ex` | `Beamlet.Actions.Operation`：new/1、validate/1、t | 版本、预算、claims、placement 与含凭据整个 262144 字节 envelope；私有 header/placement/nodes/claims 由公开校验说明覆盖 |
| `apps/beamlet_actions/lib/beamlet/actions/contracts.ex` | OperationRef、ExecutionHandle、Execution、Result（各 t）；Result.valid?/1；Handler.context、run/2 回调 | 瞬时身份不可持久化、准入前 handle=nil、uncertain 不证明终止、Result 1 MiB、执行来源必需执行 ID；简单结构以模块/类型说明覆盖，不增加无操作的构造 API |
| `apps/beamlet_harness/lib/beamlet/harness.ex` | Harness、Tool（settings/output、descriptor/0、invoke/3 回调）、Environment.t | 无兄弟依赖/无自动进程；目录无本地设置，环境仅便携 ID；结构不自动验证环境存在 |
| `apps/beamlet_harness/lib/beamlet/harness/arguments.ex` | Arguments：schema?/1、validate/2、schema | 浅层 object 子集、默认拒绝额外属性、Unicode 码点；明确不能声称检查所有不可满足约束组合；私有属性/原始值检查不逐分支注释 |
| `apps/beamlet_harness/lib/beamlet/harness/catalogue.ex` | Catalogue：new/1、validate/1、name?/1、batch/2、descriptor/t | 64描述、16 KiB/描述、1..8调用、唯一ID与原顺序、完整批次先验，永不派发；内部 reduce 是公开整批失败规则的实现，无需重复 doc |
| `apps/beamlet_harness/lib/beamlet/harness/context.ex` | Context：cancelled?/1、emit/2、append/2、t | 128消息/1 MiB JSON、不驱逐；进度8192字节、无钩子快捷返回、钩子原值/异常由本地调用者承担 |
| `apps/beamlet_harness/lib/beamlet/harness/model.ex` | Model：validate_invocation/1 与 complete/3 行为；default_providers/0、provider_id?/1、validate_registry/1、json?/2（含默认包装）、validate_invocation/1、validate_request/1、validate_history/2、validate_reply/2、canonical_call/1、assistant_message/1；json_value/json_object/invocation/request/call/reply/registry/validation | config/credentials分离、精确字段、递归 JSON、固定本地注册、完整历史配对、完整回复大小；补充原子键拒绝及编码异常边界原因，私有 history/next 等由公开顺序契约覆盖 |
| `apps/beamlet_harness/lib/beamlet/harness/models/deterministic.ex` | Models.Deterministic：validate_invocation/1、complete/3（含默认 /2） | 无网络、显式 JSON reply fixture、空凭据、同样的请求/回复校验；私有 fixture 类型/转换细节不扩成公共契约 |
| `apps/beamlet_harness/lib/beamlet/harness/models/open_ai_compatible.ex` | Models.OpenAICompatible：complete/3（默认 /2）、validate_invocation/1、normalize/2 | 单次非流式请求、无重试/重定向、显式认证、TLS；README详列 config/协议限制；新增全新 Req 隔离、溢出标记先于解码、直接非法项编码边界注释；profile/transport/decode 等私有函数不公开化 |
| `apps/beamlet_harness/lib/beamlet/harness/tools/deterministic.ex` | Tools.Deterministic：descriptor/0、invoke/3（默认 /2） | echo 1024码点、本地进度/取消、忽略settings；静态描述中的产品字符串原样保留 |
| `apps/beamlet_harness/lib/beamlet/harness/tools/workspace_read.ex` | Tools.WorkspaceRead：descriptor/0、validate_root/1、invoke/3（默认 /2） | root/settings仅本地、4096字节/32段、max+1哨兵、UTF-8截断、始终关闭FD；普通注释解释资源释放和哨兵校验，README保留TOCTOU/FIFO/硬链接/挂载/阻塞与非沙箱限制；私有walk/read/text不增加公开doc |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/context.ex` | Core.Context：start/1、append/2、messages/1、finish/2、build/3、materialize/2、complete_boundary/1、observation/2、reply/1；accumulator/built/decoded_reply | 精确下一来源、增量转换/先错先停、JSON括号逗号计数、历史/当前目录区分、明确resolution、不读存储/不验证摘要；保留原两条有效英文函数说明；私有转换/配对由公开约束覆盖 |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/data.ex` | Core.Data（保持隐藏）：uuid?/1、digest?/1、plain?/1、proper_list?/1、fields?/1、control?/1；value/object | 隐藏内部校验器不添加函数文档以免暗示公开稳定接口；新增普通注释解释规范UUID与容器深度预算，补公开类型中文；private递归细节不复述 |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/decision.ex` | Core.Decision：reply_position/1、resumable?/1、resume/1、safe_fork?/1 | 分类不是派发/恢复，blocked可识别但不可直接resume，safe_fork不证明环境停止 |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/reducer.ex` | Core.Reducer：version/0、new/1、reduce/2、replay/2、decode/1、decisions/1；state/event/error | 版本1、同scope连续序号、首条创建、turn/step/ordinal、暂停、引用控制、不计算摘要、payload根深度32；复杂转换由公开规则和现有英语typedoc覆盖，未给每个私有事件分支重复加doc |

## 阅读依据与文档路径

读取了当前子任务和父任务 PRD/design/implement、implement.jsonl全部条目、共享 coverage、lanes；读取 before-dev 技能、backend index/directory/quality/typespec/harness-providers/agent-orchestration/agent-durable 与 thinking guides index。读取三个 mix.exs；原文档只有 Core README.md，本组件原来没有 Actions/Harness README 和三个中文入口。

全文核对的关联源码：`apps/beamlet_agent/lib/beamlet/agent/reducer.ex`、`context_builder.ex`、`integration/handler.ex`。全文核对的测试：Actions actions_test、Core core_test、Harness model/harness/http/workspace_test、Agent beamlet/core_adapter_test 与 beamlet/context_read_order_test。未声称审阅这些范围以外的生产调用方。

文档交付：

- `apps/beamlet_actions/README_zh.md`
- `apps/beamlet_harness/README_zh.md`
- `apps/beamlet_agent_core/README_zh.md`
- 本交接 `research/coverage-contracts.md`

README 含职责/实际依赖、无自动启动与调用前提、源码校验的可执行纯数据示例、根目录验证命令和已知边界；只链接现存 Core 英文 README，未制造另外两个尚不存在的英文目标链接。三个 README 的 Elixir 代码块已合并到临时文件实际执行成功，无网络/文件写入副作用。

## 聚焦验证

全部从仓库根目录执行，使用已有 nix-store Elixir 1.20.4，未获取依赖。

- `mix format <16个本组件修改的源文件>`；后续两次只格式化刚修订的 Core 文件。`mix format --check-formatted <16源文件>`：通过；未运行全项目格式化。
- `git diff --check`：通过。
- `mix test --no-start apps/beamlet_actions/test apps/beamlet_agent_core/test apps/beamlet_harness/test/beamlet/model_test.exs apps/beamlet_harness/test/beamlet/harness_test.exs --seed 631927`：Actions 28、Core 10、Harness 16 全通过。
- `mix test --no-start apps/beamlet_agent/test/beamlet/core_adapter_test.exs apps/beamlet_agent/test/beamlet/context_read_order_test.exs --seed 631927`：5项通过。
- `mix test apps/beamlet_harness/test --seed 631927`：35项通过，包含实际本地 HTTP/TLS/工作区；selfsigned_peer是预期负例。os_mon报告/mnt/windows磁盘接近满，未造成测试失败；不推断外部服务或付费模型验收。
- `mix run --no-start /tmp/contracts_examples.exs`：三个 README 全部 Elixir 示例执行通过。Python 路径检查确认 README 相对链接及测试路径存在。最初查找适配测试时用了错误路径 `test/core_adapter_test.exs`，随后按实际 `test/beamlet/` 修正 README并执行正确命令，未将错误路径记作通过。
- `elixir scripts/quality/check-contracts.exs`：148 files、1345 functions、missing 0、errors 0；只是既有契约门禁，不声称是全项目语义审阅。
- `elixir /tmp/contracts_ast.exs`：16个源文件与 HEAD 的 AST 去除 doc/moduledoc/typedoc 及位置元数据后相同；包括 types/specs/signatures/可执行字符串。没有修改测试、依赖、配置或UI/Gettext。
- `git diff --cached --name-only`：空，无暂存文件、无提交或分支操作。

## 剩余边界与集成事项

本组件无未完成交付或工具阻塞。全项目 warning-fatal compile、契约扫描器自身回归、全量format检查、全量测试、Credo/Dialyzer/Sobelow/Gettext与中文总验收由父会话集成执行；以上聚焦测试会编译依赖，但不能替代独立 warning-fatal compile。未修改共享 coverage.md；父会话据此逐行汇入。英文新增内容仍等待中文阶段验收。AST临时工具及示例临时文件仅在 /tmp，不作为仓库交付。
