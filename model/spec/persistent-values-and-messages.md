# 首版持久值与消息契约

状态: 首版实现契约草案, 补全已有 Q36-Q45 的受限值与身份语义. 本文给出可用于实现和后端符合性测试的最小选择;
不是 Runtime 实现, 不规定物理表名、HTTP 路由或最终 Elixir 类型. 本文的 v1 表示本文契约版本, 不改变既有 Operation Identity.
上位约束见 [Operation / Handler](operation-handler-contracts.md), 原子处理见 [存储命令](storage-command-contracts.md).

## 1. 逻辑值 v1

| 值 | 首版解释 |
| --- | --- |
| null、bool | null 是明确存在的空值, 不等于字段缺省; bool 不等于整数 |
| integer | 范围为 `[-(2^53-1), 2^53-1]`; 逻辑值不包含浮点数, 不截断、不溢出转换 |
| string | 合法 Unicode scalar 序列; 不自动 trim、大小写转换或 NFC/NFD 归一化 |
| array | 有序逻辑值序列; 顺序影响相等性 |
| object | 字符串键到逻辑值的映射; 键唯一, 顺序不影响相等性 |

首版 decimal、大整数、二进制和时间由具体 Operation 定义带版本的字符串/对象表示; 不添加会与普通对象碰撞的全局隐式 tagged 解码.
逻辑值 v1 不接受 float/NaN/Infinity、atom、tuple、PID、Reference、Function、Port 或任意 Elixir term.
外部 JSON 是一种可选 wire 格式; `1.0`/`1e0` 不能靠浮点解码静默成为 integer. 选择 codec 时须验证或明确拒绝其数值词法.
对象重复键、非法 UTF-8、未配对 surrogate 必须在解码时拒绝, 不能让后写键覆盖前键.

默认资源预算: 单个值的下述规范表示不超过 1 MiB, 容器嵌套深度不超过 32, 总节点不超过 10,000;
标量算一个节点, 容器自身算一个节点, object 的键计入字节预算但不另算节点. scalar 深度为 0, 每层容器 +1.
实现须在解析/遍历时有界检查, 不能先无限分配再检查. 配置只影响新入域请求; 缩小预算不使已提交数据无法读取或恢复.
超限是入域拒绝, 不产生 Failure Report 或 Failed Outcome. Operation 可以施加更小预算.

大型产物使用 Operation 定义的稳定引用, 必须说明存储定位、完整性摘要、读取授权、到期与保留责任;
首版核心不承诺产物搬移/垃圾回收, 无此契约的临时 URL 不应作为可恢复的唯一结果材料.

## 2. 相等与规范表示

相等按上述类型递归判断, integer 精确比较, string 按 Unicode scalar 序列比较; 不依赖 map 插入顺序或数据库 JSON 比较.
缺省字段与显式 null 不同. Operation 的业务默认值在初次提交前由版本化契约显式展开; 重投不能改用新默认值.

为身份比较与预算提供确定的规范表示 v1: 使用紧凑 UTF-8 JSON, object 按键的 UTF-8 字节序升序,
integer 用十进制最短形式, 零为 `0`; 不含空白、BOM 或尾换行. 字符串仅转义 quote、backslash 和 U+0000..U+001F,
控制字符统一使用小写四位 `\\u00xx`, 其余 scalar 直接编码为 UTF-8, 不转义 slash 或普通非 ASCII 字符.
这是比较/预算规则, 不要求 SQL 存储或网络传输采用相同字节. 数据库存储须连同 codec/version 标识保留足够的无损解释材料.
摘要可以加速比较, 首版仍须核对规范逻辑内容; 不以 hash 相等作为唯一的长期定义相等依据.

例子: `{"a":1,"b":null}` 与键顺序相反的对象相等; 与 `{"a":1}`、`{"a":"1","b":null}` 均不同.
`"é"` 与 `"é"` 不自动相等. 明确的小数串只有其 Operation 契约定义相等性时才具有数值语义.

## 3. 提交身份与不可变定义

- 身份为 `(authority_collection, namespace, submission_key)`. authority_collection 是部署中的权威数据集合身份,
  由可信路由确定; namespace/key 不证明读取或提交权限. 不允许同一集合同时由两份独立数据库写入.
- namespace/key 是非空 UTF-8 字符串, 各不超过 256 bytes; 按原文本精确比较, 无自动归一化.
  所选 SQL collation 必须符合此语义. 空字符串拒绝; 缺省 key 表示无 key, 每次成功处理创建新 Intent.
- 不可变定义逐字段比较 Operation Identity、逻辑输入、硬约束和初始策略快照, 不比较后来的控制状态、接收时间或 Handler 发布号.
  不允许未知定义字段被静默丢弃; 契约版本不支持时拒绝. 初始策略的默认值须在持久建立前展开并保存.
- 同身份同定义返回同一 Intent 及本次读取到的已提交事实; Closed 时包括既有 Outcome 原业务值.
  同身份不同定义返回 DefinitionConflict, 保留原定义. 与协调 Command ID 的“返回原处理结果”协议区分.
- 保存 Intent 期间持续保留身份和定义比较材料; Closed 不开始 TTL 倒计时. 首版不删除 Intent/身份,
  不定义归档后重新使用 key 的语义. 无 key 提交在确认丢失后重投可能创建第二个操作, 调用方须据此选用稳定 key.

## 4. Report Envelope v1

逻辑 envelope 至少关联 authority_collection、Intent、Execution、Operation Identity、source_scope、report_id、kind、body.
Worker 来源还关联完整授权 token; 回调来源关联持久 callback binding; query 来源关联实际查询契约及依据.
`report_id` 是 source_scope 内稳定且非空的 opaque string, 不超过 256 bytes; 不从接收时间重新生成.

去重身份为 `(collection, intent, execution, source_scope, report_id)`. source_scope 由已认证来源映射,
不能由正文任意冒充; Worker scope 包含 worker/incarnation/generation, callback scope 包含 provider/account/binding,
query scope 包含相应 Adapter 的稳定观察身份域. 业务 body 以及 kind/Operation/来源关联参与逻辑内容比较;
传输签名、尝试次数、接收时间与本地诊断信息不参与同报告内容相等.

| kind | body 要求与事实含义 |
| --- | --- |
| Pending | Operation 定义的可恢复等待材料; 不表示结果已知 |
| Success | Operation 合法结果; 审批拒绝等业务结果可以是正常 Success 数据 |
| Failure | 明确调用错误与契约分类; 可能已产生部分副作用 |
| NotFound | 查询未发现, 不证明永远未执行 |
| NotExecuted | 必须关联可排除既往及未来执行的受信协议依据 |

同身份同内容补发持久确认, 不重复 History. 同身份不同内容保存完整冲突材料和各自来源依据,
不得被唯一索引冲突路径静默丢弃. 不同身份的矛盾完成同样设置冲突; 既有 Outcome 不变.
不支持的 kind、错误类型、缺失关联或过大正文拒绝入域. 验签成功也不能免除 Operation/值域检查.

接收结果区分 `Stored`、`DuplicateStored`、`ConflictStored`, 以及本次读取的独立 Outcome/待协调事实;
Stored 不承诺已采用为 Outcome. 接收结论可按完整报告身份及内容查询, 查询使用当前读取权限.
Closed 的合法迟到报告可以保存; 不读取已有 Outcome 的调用者不因此获得结果正文.

## 5. 最低符合性用例

以下是实现验收要求, 当前仓库尚无真实 codec/数据库实现:

1. integer 两端往返, 溢出/float/指数数字拒绝; bool 与 integer 区分.
2. 重复键、非法 UTF-8/surrogate、嵌套运行时对象拒绝; 深度、节点与字节预算逐边界检查.
3. object 键乱序相等, 缺省/null 不同, Unicode 不自动归一化; 规范字节在两个 Adapter 一致.
4. SQLite/PostgreSQL round-trip 保留逻辑类型和值, 历史 codec 版本仍可读取; JSONB 不能改变长期身份比较.
5. 两个同 key 不同定义的并发请求各按实际首次提交顺序得到创建或冲突, 不覆盖原定义.
6. 同报告重投只保存一次; 同身份不同内容两份保留且标冲突; 迟到值不改写 Outcome.
7. 输入/结果/Envelope 超限不占用提交/报告身份, 也不伪装为领域失败; 未提交故障重投与明确冲突区分.
