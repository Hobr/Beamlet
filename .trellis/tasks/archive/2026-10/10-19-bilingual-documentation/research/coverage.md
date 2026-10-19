# 文档与注释覆盖清单

## 清点边界与状态含义

本清单由中文阶段集成审阅在 2026-10-19 用源码、编译后 ExDoc 文档块（`Code.fetch_docs/1`）与 `git diff` 实测更新；不再保留“待审阅/待处理”占位。

- 生产范围：13 个应用的 `apps/*/lib/**/*.ex` 共 **148 个文件**，全部出现在本次差异中（`git status` 实测 148 行），无未触及文件。
- 源文件含 **163 个模块**：111 个可见模块有中文 `@moduledoc`，52 个保持 `@moduledoc false`；`@doc false`/`@moduledoc false` 数量与 `git HEAD` 逐文件一致（无可见性变化）。
- 编译后文档块统计：中文函数/宏/回调/类型说明 **554** 条；保留的英文说明 **86** 条（均为框架生成或既有英文，英文阶段已由用户撤销）；`@doc false`/`:hidden` **260** 条；未加注 **449** 条 = 框架/宏生成 194 条（Ecto Repo、Endpoint、Router、Gettext、模板） + 隐藏模块内部形状 255 条。
- 状态：`中文已检查` = 已读正文并核对调用方/测试后补中文说明；`隐藏边界` = 保持 `@moduledoc false`/`@doc false`，只加普通中文注释；`框架生成` = `use`/宏/模板生成的函数，不手写文档；`不实施（英文已取消）` = 有效英文保留、新英文翻译留不实施（英文已取消）阶段。
- 行为不变证据：173 个被改动的 Elixir 文件（148 源文件 + 14 个 `mix.exs` + 5 个 `config/*.exs` + 6 个 `scripts/**/*.exs`）与 `HEAD` 的 AST 在移除 `@doc/@moduledoc/@typedoc` 与位置元数据后完全相同；197 条被改写为 heredoc 的单行英文文档属性文本逐条子串比对仍在结果中。

## 文档语言映射（实测存在性）

| 英文路径 | 中文路径 | 英文现状 | 中文状态 | 说明 |
| --- | --- | --- | --- | --- |
| `README.md` | `README_zh.md` | 存在（构建命令） | 新建并已检查 | 中文含 13 应用导航、构建/运行/发布入口；英文为既有内容 |
| `GLOSSARY.md` | `GLOSSARY_zh.md` | 存在（早期中文词表） | 新建并已检查 | `GLOSSARY.md` 无语言后缀但为中文原文，未被当作英文目标 |
| `architecture.md` | `architecture_zh.md` | 存在 | 修订并已检查 | 目标架构定位保留；补 format3/现名/未验证边界 |
| `docs/architecture/agent-operation-persistence.md` | `docs/architecture/agent-operation-persistence_zh.md` | 存在（中文原文） | 新建并已检查 | 表/视图/事件版本按源码核对 |
| `docs/architecture/persistence-delivery.md` | `docs/architecture/persistence-delivery_zh.md` | 存在（中文原文） | 新建并已检查 | 范围改为统一 format3，历史证据标明未重跑 |
| `scripts/deployment/README.md` | `scripts/deployment/README_zh.md` | 存在 | 新建并已检查 | 英文部署说明的中文版本，加同主机证据边界 |
| `apps/beamlet_actions/README.md` | `apps/beamlet_actions/README_zh.md` | **缺失** | 新建并已检查 | 中文首页不链接不存在的英文文件 |
| `apps/beamlet_actions_storage/README.md` | `apps/beamlet_actions_storage/README_zh.md` | **缺失** | 新建并已检查 | 同上 |
| `apps/beamlet_harness/README.md` | `apps/beamlet_harness/README_zh.md` | **缺失** | 新建并已检查 | 同上 |
| `apps/beamlet_storage/README.md` | `apps/beamlet_storage/README_zh.md` | 存在 | 新建并已检查 | 中文在前，链接既有英文 README |
| `apps/beamlet_agent_storage/README.md` | `apps/beamlet_agent_storage/README_zh.md` | 存在 | 新建并已检查 | 中文在前，链接既有英文 README |
| `apps/beamlet_agent_core/README.md` | `apps/beamlet_agent_core/README_zh.md` | 存在 | 新建并已检查 | 中文在前，链接既有英文 README |
| `apps/beamlet_agent/README.md` | `apps/beamlet_agent/README_zh.md` | 存在 | 新建并已检查 | 中文在前，链接既有英文 README |
| `apps/beamlet_runtime/README.md` | `apps/beamlet_runtime/README_zh.md` | 存在 | 新建并已检查 | 中文在前，链接既有英文 README |
| `apps/beamlet_node/README.md` | `apps/beamlet_node/README_zh.md` | 存在 | 新建并已检查 | 中文在前，链接既有英文 README |
| `apps/beamlet_cli/README.md` | `apps/beamlet_cli/README_zh.md` | **缺失** | 新建并已检查 | 用语言状态说明代替英文链接（原 `[English](README.md)` 为断链，已修正） |
| `apps/beamlet_app_server/README.md` | `apps/beamlet_app_server/README_zh.md` | **缺失** | 新建并已检查 | 同上 |
| `apps/beamlet_app_web/README.md` | `apps/beamlet_app_web/README_zh.md` | **缺失** | 新建并已检查 | 同上 |
| `apps/beamlet_app_web/HOST.md` | `apps/beamlet_app_web/HOST_zh.md` | 存在 | 新建并已检查 | 宿主任职/目录/公开草稿/创建不确定结果 |
| `apps/beamlet_app_web/WORKBENCH.md` | `apps/beamlet_app_web/WORKBENCH_zh.md` | 存在 | 新建并已检查 | 诊断页链接边界已按源码修正 |
| `apps/beamlet_i18n/README.md` | `apps/beamlet_i18n/README_zh.md` | **缺失** | 新建并已检查 | 用语言状态说明代替英文链接（断链已修正） |

七个应用的英文 README 仍缺失：`beamlet_actions`、`beamlet_actions_storage`、`beamlet_harness`、`beamlet_app_server`、`beamlet_app_web`、`beamlet_cli`、`beamlet_i18n`。父任务 AC2 原要求的英文 README 入口已随用户“放弃英文”决定撤销；最终验收只要求中文入口，且不为缺失的英文文件制造链接。

`docs/architecture/research/` 的历史研究材料只作为参考链接保留，不翻译、不改写结论。`architecture_zh.md` 保持“目标架构”定位：目标能力未被改写为已实现清单，只补充与当前实现的关系、现名导航与未验证边界。

## 生产源码逐文件覆盖

“中文说明”列给出编译后可见文档块计数：`moduledoc`=中文模块说明数，`API`=中文函数/宏/回调/类型说明数；隐藏模块的公开形状计入“边界”。“依据”指向组件的逐文件 API 组交接。

### beamlet_actions（3 个文件）

依据：[coverage-contracts.md](../../10-19-documentation-zh/research/coverage-contracts.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_actions/lib/beamlet/actions.ex` | moduledoc 1；API 5 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions/lib/beamlet/actions/contracts.ex` | moduledoc 5；API 7 | @doc false 8 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions/lib/beamlet/actions/operation.ex` | moduledoc 1；API 3 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |

### beamlet_harness（9 个文件）

依据：[coverage-contracts.md](../../10-19-documentation-zh/research/coverage-contracts.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_harness/lib/beamlet/harness.ex` | moduledoc 3；API 5 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/arguments.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/catalogue.ex` | moduledoc 1；API 6 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/context.ex` | moduledoc 1；API 4 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/model.ex` | moduledoc 1；API 20 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/models/deterministic.ex` | moduledoc 1；API 2 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/models/open_ai_compatible.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/tools/deterministic.ex` | moduledoc 1；API 2 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_harness/lib/beamlet/harness/tools/workspace_read.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |

### beamlet_agent_core（4 个文件）

依据：[coverage-contracts.md](../../10-19-documentation-zh/research/coverage-contracts.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/context.ex` | moduledoc 1；API 12 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/data.ex` | moduledoc 0；API 2 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/decision.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_core/lib/beamlet/agent/core/reducer.ex` | moduledoc 1；API 9 | — | 中文已检查 | 不实施（英文已取消） |

### beamlet_storage（15 个文件）

依据：[coverage-foundation.md](../../10-19-documentation-zh/research/coverage-foundation.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_storage/lib/beamlet/storage/admission.ex` | moduledoc 1；API 10；保留英文 1 | @doc false 3 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/artifact_changeset.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/artifacts.ex` | moduledoc 1；API 5 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/codec.ex` | moduledoc 1；API 9 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/connections.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/dataset.ex` | moduledoc 1；API 5 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/host.ex` | moduledoc 1；API 8；保留英文 1 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/installation.ex` | moduledoc 1；API 7 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/json.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 2；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/migrations.ex` | moduledoc 2；API 4 | @doc false 1 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/references.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/repo.ex` | moduledoc 1；API 1 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/repos.ex` | moduledoc 2；API 0；保留英文 14 | @doc false 4；同文件 Ecto Repo 宏生成函数不手写 @doc（42 项/模块） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/schema/artifact.ex` | moduledoc 0；API 1 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_storage/lib/beamlet/storage/transaction.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |

### beamlet_actions_storage（18 个文件）

依据：[coverage-domain-storage.md](../../10-19-documentation-zh/research/coverage-domain-storage.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/codec.ex` | moduledoc 1；API 7 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/dispatch_scopes.ex` | moduledoc 1；API 8 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/executor_journal.ex` | moduledoc 1；API 6 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/json.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 2；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/migrations/authority_v1.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/migrations/journal_v1.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/operation_records.ex` | moduledoc 1；API 8 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/profiles.ex` | moduledoc 1；API 6；保留英文 21 | 隐藏模块 3；@doc false 6；同文件 Ecto Repo 宏生成函数不手写 @doc（42 项/模块） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/read.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/record_changeset.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/records.ex` | moduledoc 1；API 18 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/dispatch_scope.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/execution.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/execution_evidence.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/journal_attempt.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/operation.ex` | moduledoc 0；API 1 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/operation_event.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/terminal_artifacts.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |

### beamlet_agent_storage（18 个文件）

依据：[coverage-domain-storage.md](../../10-19-documentation-zh/research/coverage-domain-storage.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/agent_records.ex` | moduledoc 1；API 12 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/codec.ex` | moduledoc 1；API 7 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/events.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/history.ex` | moduledoc 1；API 9 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/inheritance.ex` | moduledoc 1；API 6 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/json.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 2；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/migrations/agent_v1.ex` | moduledoc 1；API 2 | @doc false 1 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/operation_records.ex` | moduledoc 1；API 3 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/profiles.ex` | moduledoc 3；API 1；保留英文 14 | @doc false 4；同文件 Ecto Repo 宏生成函数不手写 @doc（42 项/模块） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/read.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/record_changeset.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/records.ex` | moduledoc 1；API 24 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/agent.ex` | moduledoc 0；API 1 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/agent_operation.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/checkpoint.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/command.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/event.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/operation.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 5；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |

### beamlet_runtime（10 个文件）

依据：[coverage-orchestration.md](../../10-19-documentation-zh/research/coverage-orchestration.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_runtime/lib/beamlet/runtime.ex` | moduledoc 1；API 14 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/directory.ex` | moduledoc 0；API 0；保留英文 2 | 隐藏模块 2；@doc false 12；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/execution_supervisor.ex` | moduledoc 0；API 0；保留英文 1 | 隐藏模块 1；@doc false 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex` | moduledoc 0；API 0；保留英文 1 | 隐藏模块 1；@doc false 6；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/observation.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex` | moduledoc 0；API 0；保留英文 1 | 隐藏模块 1；@doc false 6；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex` | moduledoc 1；API 13 | @doc false 3 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/report.ex` | moduledoc 0；API 1 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/shared_supervisor.ex` | moduledoc 1；API 1；保留英文 1 | 隐藏模块 1；@doc false 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_runtime/lib/beamlet/runtime/worker.ex` | moduledoc 1；API 2 | — | 中文已检查 | 不实施（英文已取消） |

### beamlet_agent（21 个文件）

依据：[coverage-orchestration.md](../../10-19-documentation-zh/research/coverage-orchestration.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_agent/lib/beamlet/agent.ex` | moduledoc 1；API 33 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex` | moduledoc 1；API 1；保留英文 1 | @doc false 1 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/context_builder.ex` | moduledoc 1；API 5 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/delegation.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/discovery.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/display.ex` | moduledoc 1；API 5 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/durable.ex` | moduledoc 1；API 20 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/history.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/integration/caller.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/integration/handler.ex` | moduledoc 1；API 1 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/lifecycle.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/loader.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/model_binding.ex` | moduledoc 1；API 6 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/reducer.ex` | moduledoc 1；API 6 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/ref.ex` | moduledoc 1；API 1 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/resources.ex` | moduledoc 0；API 0；保留英文 1 | 隐藏模块 1；@doc false 6；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/server.ex` | moduledoc 0；API 1；保留英文 1 | 隐藏模块 1；@doc false 6；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/trace_export.ex` | moduledoc 1；API 5 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/trace_snapshot.ex` | moduledoc 0；API 1 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_agent/lib/beamlet/agent/trace_verifier.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |

### beamlet_node（10 个文件）

依据：[coverage-orchestration.md](../../10-19-documentation-zh/research/coverage-orchestration.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_node/lib/beamlet/node.ex` | moduledoc 1；API 10；保留英文 1 | @doc false 1 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/agents.ex` | moduledoc 1；API 2 | @doc false 1 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/cluster.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/observation.ex` | moduledoc 0；API 1 | 隐藏模块 1；@doc false 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/provider.ex` | moduledoc 1；API 1；保留英文 1 | @doc false 6 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/routes.ex` | moduledoc 1；API 1；保留英文 1 | @doc false 6 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/runtime.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/storage.ex` | moduledoc 1；API 8；保留英文 1 | @doc false 6 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/beamlet/node/storage/operator.ex` | moduledoc 1；API 1 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_node/lib/mix/tasks/beamlet.storage.migrate.ex` | moduledoc 1；API 1 | — | 中文已检查 | 不实施（英文已取消） |

### beamlet_cli（9 个文件）

依据：[coverage-hosts.md](../../10-19-documentation-zh/research/coverage-hosts.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_cli/lib/beamlet/cli.ex` | moduledoc 1；API 2 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/application.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/client.ex` | moduledoc 1；API 7 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/command.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/gettext.ex` | moduledoc 1；API 0 | @doc false 4；Gettext 后端生成回调（handle_missing_*） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/locale.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/renderer.ex` | moduledoc 1；API 1 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/runner.ex` | moduledoc 1；API 4 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_cli/lib/beamlet/cli/session.ex` | moduledoc 1；API 3 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |

### beamlet_app_server（3 个文件）

依据：[coverage-hosts.md](../../10-19-documentation-zh/research/coverage-hosts.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_app_server/lib/beamlet/server.ex` | moduledoc 1；API 2 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_server/lib/beamlet/server/application.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_server/lib/beamlet/server/bootstrap.ex` | moduledoc 0；API 0；保留英文 1 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |

### beamlet_app_web（24 个文件）

依据：[coverage-hosts.md](../../10-19-documentation-zh/research/coverage-hosts.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_app_web/lib/beamlet_web.ex` | moduledoc 1；API 9 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/agents.ex` | moduledoc 1；API 6 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/application.ex` | moduledoc 0；API 0 | 隐藏模块 1；@doc false 3 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/components/core_components.ex` | moduledoc 1；API 12 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/components/layouts.ex` | moduledoc 1；API 4 | @doc false 4；embed_templates 生成的布局函数 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/components/observation_components.ex` | moduledoc 1；API 3 | @doc false 3 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/controllers/error_html.ex` | moduledoc 1；API 1 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/controllers/error_json.ex` | moduledoc 1；API 1 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/controllers/page_controller.ex` | moduledoc 1；API 1 | @doc false 4 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/controllers/page_html.ex` | moduledoc 1；API 0 | @doc false 4；embed_templates 生成的组件函数 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/endpoint.ex` | moduledoc 1；API 0；保留英文 14 | @doc false 2；Phoenix.Endpoint/Plug 生成回调（broadcast/call/init 等） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/gettext.ex` | moduledoc 1；API 0 | @doc false 4；Gettext 后端生成回调（handle_missing_*） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/handles.ex` | moduledoc 1；API 4；保留英文 1 | @doc false 6 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/host.ex` | moduledoc 1；API 3；保留英文 1 | @doc false 1 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/host/bootstrap.ex` | moduledoc 0；API 0；保留英文 1 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/live/management_live.ex` | moduledoc 1；API 4 | @doc false 8 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/live/management_reads.ex` | moduledoc 1；API 2 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/live/owned_call.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/live/workbench_commands.ex` | moduledoc 0；API 0 | 隐藏模块 1；隐藏模块内公开形状（仅注释） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/live/workbench_live.ex` | moduledoc 1；API 0 | @doc false 8；模板生成的 render/1 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/locale.ex` | moduledoc 1；API 8 | @doc false 2 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/presets.ex` | moduledoc 1；API 20；保留英文 1 | @doc false 6 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/router.ex` | moduledoc 1；API 0；保留英文 2 | @doc false 7；Router 宏生成辅助函数 | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_app_web/lib/beamlet_web/telemetry.ex` | moduledoc 1；API 2；保留英文 1 | @doc false 1 | 中文已检查 | 不实施（英文已取消） |

### beamlet_i18n（4 个文件）

依据：[coverage-hosts.md](../../10-19-documentation-zh/research/coverage-hosts.md)（逐文件模块/API 组、隐藏边界与验证记录）。

| 路径 | 中文说明 | 边界（隐藏/生成/未加注） | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| `apps/beamlet_i18n/lib/beamlet/i18n.ex` | moduledoc 1；API 2 | @doc false 4；Gettext 后端生成回调（handle_missing_*） | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_i18n/lib/beamlet/i18n/catalogue.ex` | moduledoc 1；API 3 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_i18n/lib/beamlet/i18n/locale.ex` | moduledoc 1；API 8 | — | 中文已检查 | 不实施（英文已取消） |
| `apps/beamlet_i18n/lib/beamlet/i18n/vocabulary.ex` | moduledoc 1；API 2 | — | 中文已检查 | 不实施（英文已取消） |

### 其他说明入口

| 范围 | 文件数 | 实际审阅/补充 | 中文 | 英文 |
| --- | --- | --- | --- | --- |
| 根与应用 `mix.exs` | 14 | umbrella 构建路径/后端选择/发布闭包/别名范围及 13 个应用的依赖与宿主回调说明 | 已检查 | 不实施（英文已取消） |
| `config/*.exs` | 5 | 共享 umbrella 语义、dev/prod/runtime/test 的密钥、watcher、digest 与发布分支说明 | 已检查 | 不实施（英文已取消） |
| `scripts/quality/*.exs` | 3 | 契约扫描器入口、退出码、夹具用途与扫描器 `@moduledoc` 中文段 | 已检查 | 不实施（英文已取消） |
| `scripts/deployment/*.sh` | 3 | 门禁顺序、复制产物检查范围、durable 两进程阶段与不跨机声明 | 已检查 | 不实施（英文已取消） |
| `scripts/deployment/*.py` | 5 | docstring 中文说明（夹具不访问真实提供方、PTY 清理、清理组合语义） | 已检查 | 不实施（英文已取消） |
| `scripts/deployment/*.example.exs` | 3 | 示例不被自动加载、无需模型凭据、角色省略语义、`agent_options` 为可信代码 | 已检查 | 不实施（英文已取消） |
| `bench/enum.exs` | 0（未改） | 已有“不是性能基线”说明，本次不属改动范围 | 无需补充 | — |
| HEEx/前端资源 | 0（未改） | 无需要解释的关键约束；改界面文案被明确排除 | 无需补充 | — |

## 未加注决定与理由（汇总）

- **隐藏模块**（52 个 `@moduledoc false`）：schema、`JSON`/`Read`/`RecordChangeset`、内部监督/协调/网关、`Core.Data`、`WorkbenchCommands` 等保持隐藏，只补普通中文注释解释事务、资源释放、锁序、未知结果与不重试原因；不把内部函数变成公开 API。
- **框架/宏生成函数**（449 条未加注中除隐藏模块外全部）：Ecto Repo（4 个可见 Repo 模块 × 42）、Phoenix Endpoint/Plug 回调（10）、Router 辅助（4）、Gettext 后端回调（9）、`embed_templates` 组件（2）、模板生成 `render/1`（1）。它们由宏生成，手写 `@doc` 会与框架文档冲突。
- **简单内部谓词/私有辅助**：函数名与相邻公开契约已表达边界（如 `Presets.model?/2`、`Locale.persist_param/2`、`Session.dispatch/3`、`Codec.walk/*`），不逐条复述。
- **重复信息**：同一文件的公开门面 + 私有实现的规则只在门面说明一次，其余由模块说明覆盖。

## 中文基线与证据

- 基线提交：`HEAD = 87fd45781e783a36e7a1101a420b30813f9c02ab`（`dev` 分支，未提交本次改动）。
- 中文文档基线（21 份 Markdown 的逐文件 SHA-256 清单）：聚合摘要 `c25c26a594f03273696cbd6327808bf99100e96b289073a1623711090ba5bc7a`；明细见中文子任务 [verification.md](../../10-19-documentation-zh/verification.md)。
- 源码文档差异摘要：`apps/*/lib/**/*.ex` 差异 `ae31dff2f5986ac55f6d4fbdbe6cd5b1c4b0d09b09ad52cc5a225721a9687167`；`mix.exs`/`config`/`scripts` 差异 `f527a2d09e5262cc5898476d7083d5ef4c33482d2d6fc8128c866ef3fe56c3cb`；已跟踪 Markdown 差异 `9176b55fa995d956976c00d53eb33f026c0d2a36fd3cfebfa46610394b34a1f7`。
- 门禁与失败记录（通过/失败/未执行及原因）见中文子任务 [verification.md](../../10-19-documentation-zh/verification.md)；本表只记录覆盖状态。

## 集成阶段补充修正（本次核对）

- 宿主组件的 4 份中文 README 曾链接不存在的 `README.md`（`beamlet_app_server`、`beamlet_app_web`、`beamlet_cli`、`beamlet_i18n`），已改为语言状态说明；全部 34 份文档的 169 条相对链接/锚点检查为 0 断链。
- `Beamlet.Agent.Storage.History.checkpoint_at/3`、`checkpoint_page/3` 与 `Beamlet.Agent.Integration.Caller.operation/3` 原有英文说明或无说明，已补中文段落/说明；补后重新编译、格式化并通过 AST 等价对比。
- 宿主组件重复 `@doc`、私有 `@doc` 与模板化 `@typedoc` 的修正经静态复扫确认已无残留（173 个 Elixir 文件 0 处重复/私有文档属性）。
