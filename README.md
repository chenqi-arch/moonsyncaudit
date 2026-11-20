# MoonSyncAudit

**MoonSyncAudit · MoonBit 双源采集时间校准与配对质检工具**

两台设备各自记录采集时间。只加一个固定偏移，时间误差可能随采集时长累积。MoonSyncAudit 用共同观察到的事件校准两侧时间，检查每条记录在另一侧是否有唯一候选。输出配对、缺项、冲突和覆盖范围外的原始行号，用于决定哪些数据可以合并。

## 快速开始

需要 Git、MoonBit（`moonc >= 0.10.14`）和 Node.js 22.3 或更高版本。首次安装工具链后，以下示例读取本地文件。核心统计与校准由 MoonBit 完成，命令行使用 Node.js 读取文件。

```powershell
git clone https://github.com/chenqi-arch/moonsyncaudit.git
cd moonsyncaudit
moon version --all
node --version
moon run --target js cmd/main -- audit examples/inspection/device.tsv examples/inspection/reference.tsv examples/inspection/anchors.tsv --tolerance-ms 5 --checkpoints examples/inspection/checkpoints.tsv
```

成功时摘要为：

```text
status=PASS device=3 reference=3 pairs=3 issues=0 checkpoints=PASS
```

[样例说明](examples/README.md)给出另外两种场景和对应的预期退出码。添加 `--format json` 可输出结构化报告。`--checkpoint-tolerance-ms` 用于单独指定校验点容差，缺省时沿用配对容差。

| 退出码 | 含义 |
| --- | --- |
| 0 | 配对完整，且已提供的独立校验点均在容差内。 |
| 1 | 有缺项、候选冲突、覆盖区间外的记录或校验点问题。报告中保留已找到的配对供复核。 |
| 2 | 参数、表格、校准锚点或文件读取无效。错误输出使用输入类别、错误码和行号。 |

用 PowerShell 的 `$LASTEXITCODE` 查看退出码。校验点缺省时报告 `NOT_PROVIDED`，表示本次只运行配对检查。若需要验证校准质量，应提供未用于拟合的同一事件观测点。

## 输入格式

- `DEVICE.tsv`、`REFERENCE.tsv` 的首行为 `id<TAB>t_ms`。每表 ID 唯一、区分大小写，最多 128 个 UTF-16 代码单元。时间非递减。并列毫秒保留各自记录，仍参与冲突判断。
- `ANCHORS.tsv`、可选的 `POINTS.tsv` 首行为 `device_ms<TAB>reference_ms`。时间是 1 至 19 位非负整数毫秒，范围到 Int64 最大值。两个时钟应分别使用各自一致的毫秒单位和起点。
- 文件为 UTF-8，可带开头 BOM，支持 LF 或 CRLF，最后一行允许没有换行。单文件上限 8 MiB，每路最多 100,000 条，每份锚点或校验点表最多 10,000 行数据。
- 锚点至少两个，两侧都严格递增，相邻锚点在任一侧相距最多 24 小时。校验点使用未拟合的设备时间，按两侧递增输入。文件中的行号从 1 开始并包含表头。

校准在两端锚点之间做整数线性插值，结果向下取整。覆盖范围外输出待复核。容差包含边界，每侧都只有一个候选时形成一对。冲突保留供人工判断。两边时间戳必须来自同一采集流程，锚点质量由提供者负责。本工具处理两路时间表，现场时钟同步、媒体解码和时区解析由上游负责。

## 在 MoonBit 中使用

根包提供 `parse_records`、`parse_clock_points`、`ClockModel::new`、`ClockModel::project` 和 `audit`。`AuditReport` 可读取配对、异常和独立校验点结果，也能输出文本或 JSON。核心支持将 TSV 文本作为入参，可嵌入脱离 Node.js 的 MoonBit 调用方。

运行 `moon run --target wasm cmd/library-example` 可复现纯 MoonBit 库调用，包含漂移校准、独立校验和配对结果。

JSON 报告的 `delta_ms` 与 `residual_ms` 为十进制字符串，保留 64 位整数精度。它们的符号表示参考时间减去校准后的设备时间。默认报告仅含行号、类别和时间差，记录 ID 和原始输入行保留在用户的源文件。

## 复现测试

```powershell
moon fmt --check
moon check --target wasm --deny-warn
moon build --target wasm --deny-warn
moon test --target wasm --deny-warn
moon check --target js --deny-warn
moon build --target js --deny-warn
moon test --target js --deny-warn
node scripts/verify-cli.mjs
```

[可靠性测试与验收](docs/acceptance.md)列出输入、预期结果和对应入口。GitHub Actions 执行相同的检查。

## 开源说明

采用 [Apache-2.0](LICENSE)。本项目为原创 MoonBit 实现。对照 [moonbit-robot-vision-formats](https://mooncakes.io/docs/ppyj663/moonbit-robot-vision-formats) 的容差匹配功能，设计了锚点校准、校验点核验和双向唯一配对。核心只依赖 MoonBit 标准库，运行文件命令使用 Node.js 内置 API。
