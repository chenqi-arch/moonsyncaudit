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
moon run --target js cmd/main -- audit examples/inspection/device.tsv examples/inspection/reference.tsv examples/inspection/anchors.tsv --tolerance-ms 5 --checkpoints examples/inspection/checkpoints.tsv --strict
```

成功时摘要为：

```text
status=PASS device=3 reference=3 pairs=3 issues=0 checkpoints=PASS strict=true
```

[样例说明](examples/README.md)给出另外两种场景和对应的预期退出码。`--strict` 要求每个相邻锚点区间都至少有一个可核验的独立观测点。所有提供的校验点均须在容差内。`--checkpoint-tolerance-ms` 可单独指定校验点容差，缺省时沿用配对容差。

| 退出码 | 含义 |
| --- | --- |
| 0 | 配对完整，且已提供的独立校验点均在容差内。严格模式还要求所有校准区间都有独立观测。 |
| 1 | 有缺项、候选冲突、覆盖区间外的记录或校验点问题。有校验点缺失的区间也会阻止严格模式通过。报告中保留已找到的配对供复核。 |
| 2 | 参数、表格、校准锚点或文件读取无效。错误输出使用输入类别、错误码和行号。 |

用 PowerShell 的 `$LASTEXITCODE` 查看退出码。普通模式省略校验点时报告 `NOT_PROVIDED`。严格模式省略校验点时标记为 `REVIEW` 并返回 1。

## 将配对用于合表

`--format pairs-tsv` 输出三列，分别是设备表行号、参考表行号和带符号的毫秒差。按前两列分别读取原表对应行，就能用这些配对关系合并原有列。行号从 1 开始并包含表头，索引应配合同一次审计读取的文件使用。

```powershell
moon run --target js cmd/main -- audit examples/inspection/device.tsv examples/inspection/reference.tsv examples/inspection/anchors.tsv --tolerance-ms 5 --checkpoints examples/inspection/checkpoints.tsv --strict --format pairs-tsv
```

```text
device_line	reference_line	delta_ms
2	2	1
3	3	0
4	4	0
```

可用 PowerShell 的 `| Set-Content -Encoding utf8 pairs.tsv` 保存索引。自动合表前检查退出码是否为 0。退出 1 时索引中的现有配对供人工复核，同样参数使用 `--format json` 可查看原因。

文本报告逐段以 `SEGMENT` 标出两条锚点所在行、可核验点数及最大绝对偏差。JSON 的 `checkpoints.segments` 提供对应字段。点数为 0 时 `max_abs_residual_ms` 为 `null`，表示该区间没有测得残差。独立校验使用调用方提供的观测点，结论针对这些取样位置。

## 输入格式

- `DEVICE.tsv`、`REFERENCE.tsv` 的首行为 `id<TAB>t_ms`。每表 ID 唯一、区分大小写，最多 128 个 UTF-16 代码单元。时间非递减。并列毫秒保留各自记录，仍参与冲突判断。
- `ANCHORS.tsv`、可选的 `POINTS.tsv` 首行为 `device_ms<TAB>reference_ms`。时间是 1 至 19 位非负整数毫秒，范围到 Int64 最大值。两个时钟应分别使用各自一致的毫秒单位和起点。
- 文件为 UTF-8，可带开头 BOM，支持 LF 或 CRLF，最后一行允许没有换行。单文件上限 8 MiB，每路最多 100,000 条，每份锚点或校验点表最多 10,000 行数据。
- 锚点至少两个，两侧都严格递增，相邻锚点在任一侧相距最多 24 小时。校验点使用未拟合的设备时间，按两侧递增输入。文件中的行号从 1 开始并包含表头。

校准在两端锚点之间做整数线性插值，结果向下取整。覆盖范围外输出待复核。容差包含边界，每侧都只有一个候选时形成一对。冲突保留供人工判断。两边时间戳必须来自同一采集流程，锚点质量由提供者负责。本工具处理两路时间表，现场时钟同步、媒体解码和时区解析由上游负责。

## 在 MoonBit 中使用

在自己的 MoonBit 项目中安装 [Mooncakes 包](https://mooncakes.io/docs/chenqi-arch/moonsyncaudit@0.1.0)。

```text
moon add chenqi-arch/moonsyncaudit@0.1.0
```

把[示例源码](cmd/library-example/main.mbt)和[包配置](cmd/library-example/moon.pkg)放入调用方的可执行包即可运行。仓库内可直接执行 `moon run --target wasm cmd/library-example`，查看分段校准、独立复核和配对结果。

根包提供 `parse_records`、`parse_clock_points`、`ClockModel::new`、`ClockModel::project` 和 `audit`。调用 `audit` 时可传 `strict=true`。用 `AuditReport::segments` 读取各段覆盖，用 `AuditReport::to_pairs_tsv` 导出合表行号。库输入为已解码的 TSV 文本，可独立于 Node.js 使用。

JSON 中的时间差和最大绝对偏差使用十进制字符串，保留 64 位整数精度。`delta_ms` 与 `residual_ms` 的符号表示参考时间减去校准后的设备时间。记录 ID 和原始输入行保留在用户的源文件。

## 复现测试

```powershell
moon fmt --check
moon check --target wasm --deny-warn
moon build --target wasm --deny-warn
moon test --target wasm --deny-warn
moon check --target js --deny-warn
moon build --target js --deny-warn
moon test --target js --deny-warn
moon run --target wasm cmd/library-example
node scripts/verify-cli.mjs
moon package --list --frozen
```

[可靠性测试与验收](docs/acceptance.md)列出输入、预期结果和对应入口。GitHub Actions 执行相同的检查。

## 开源说明

采用 [Apache-2.0](LICENSE)。本项目为原创 MoonBit 实现。对照 [moonbit-robot-vision-formats](https://mooncakes.io/docs/ppyj663/moonbit-robot-vision-formats) 的容差匹配功能，设计了锚点校准、校验点核验和双向唯一配对。核心只依赖 MoonBit 标准库，运行文件命令使用 Node.js 内置 API。
