# Web 宿主与可调整 Preset

## Goal and Source

提供 opt-in Web 宿主和可信创建配置，让用户通过可调整 preset 使用实际部署能力，而不接触内部模型绑定和模块。来源：[父任务 PRD](../10-17-beamlet-web/prd.md) R2/R3/R4/R10。

## Requirements

- P1：普通应用加载/测试无角色、网络和 provider 副作用；显式启用可组合 interaction 与本地 authority/executor，并支持 interaction-only 访问远程实例。
- P2：preset 是创建起点；可在部署开放的模型/工具/环境范围内调整，重置只影响草稿，既有实例不追随 preset 变化。
- P3：公共选择与私有凭据分离；未知/伪造配置不能扩大环境/工具能力或执行任意模块。只在所选工具需要时要求环境。
- P4：创建与首次输入分开反馈，已创建实例不会因输入失败被丢弃；确认不明时不自动重试业务动作。
- P5：提供安全临时实例导航，生命周期不控制 Agent；没有 preset 在线保存、持久缓存或数据库。

## Acceptance Criteria

- [x] PA1/P1：disabled load 不启动 Node、不连网；显式本地三角色及 interaction-only 命名远程组合可用且不启动 CLI/daemon。
- [x] PA2/P2,P3：选择/调整/reset 解析为有效一致的模型+工具 route/catalogue；无工具场景不要求环境；原配置和既有实例未修改。
- [x] PA3/P3：未知/重复/超量/畸形 option IDs、原始 bindings、任意节点和模块参数被拒绝，测试密钥/根设置不出现在公共投影及静态错误中。
- [x] PA4/P4：已创建/输入拒绝、创建未知、输入确认未知可区分，没有重复创建或重发。
- [x] PA5/P5：handle 过期、Web 重启或 stale descriptor 不重绑新实例；临时导航丢失可重新发现，无文件/浏览器 transcript 或存储依赖。

## Dependencies and Scope

在 observation metadata/安全读契约验收后实施；workbench 与管理页依赖本配置和适配层。无完整工作台 UI、新工具、系统提示词 API、在线 preset 编辑、账号或 Web release 打包。
