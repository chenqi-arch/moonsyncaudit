# MoonSyncAudit 可靠性测试与验收

`moon test --target wasm --deny-warn` 和 `moon test --target js --deny-warn` 分别运行同一组核心用例。`node scripts/verify-cli.mjs` 调用 `moon build --target js --deny-warn` 生成的命令行程序，校验文件输入、实际输出和退出码。样例均为合成数据。

| 重点 | 输入和应观察到的结果 | 对应证据 |
| --- | --- | --- |
| 时钟偏移和漂移 | 锚点 0→100、1,000,000→1,000,300 ms。500,000 ms 映射为 500,200 ms。接入第三锚点后，检查跨段和共用端点。 | `clock_wbtest.mbt` 和巡检场景 |
| 校准覆盖和整数精度 | 对锚点区间外的两侧数据报告覆盖外。接近 Int64 上界的时间值保持精确。溢出、倒序和超大间隔返回输入错误。 | `time_wbtest.mbt`、`clock_wbtest.mbt`、`audit_wbtest.mbt` |
| 含等值的容差 | 100 和 103 ms 在 3 ms 容差时可配对。100 和 104 ms 无候选。 | `pairing_wbtest.mbt` |
| 重复配对和得出相同结果 | 两条扫码围绕一条称重记录，三条均报冲突。逐对枚举生成独立参考，4,900 组输入的候选数和配对逐项一致。10 万对 10 万条同一毫秒时，所有窗口存在冲突，配对数为 0。 | `pairing_oracle_wbtest.mbt` 和产线场景 |
| 独立校验影响验收 | 台架校验点 2 ms 合格，3 ms 超差时退出 1，即使记录都已配对。用拟合锚点充当独立证据会被拒绝。 | `checkpoints_wbtest.mbt` 和台架场景 |
| 严格校验覆盖 | 任何校准段缺独立观测时退出 1，保留配对。覆盖齐全且残差全部达标时通过。对校验点统计绝对值最大的残差。校准区间外的观测点不会计入覆盖。 | `audit_wbtest.mbt` 和巡检命令行用例 |
| 合表行号 | TSV 与 JSON 的配对行号及有符号时间差逐行相同。空匹配输出表头，含歧义的轮次只输出已经唯一确定的配对，退出码继续提示复核。 | `report_wbtest.mbt` 和 `scripts/verify-cli.mjs` |
| 两侧各一万条 | 两段漂移方向不同。逐行比较预设的 2,500 对配对和 15,000 条异常，其中有缺项、重复时间及多对一冲突。重复运行的 JSON 字节一致，TSV 索引与预设配对一致。 | `scripts/verify-cli.mjs` 生成的固定合成数据 |
| 文件边界 | 短读后仍只打开一次。8 MiB 文件进入解析，超过上限的文件最多读取 8,388,609 字节，并在 UTF-8 解码前拒绝。非法 UTF-8、列数和重复 ID 均有失败用例。 | `scripts/verify-cli.mjs`、`tests/observe-file-read.cjs` 和 `tables_wbtest.mbt` |
| 报告可复现 | 相同输入生成相同报告。配对两端和问题行之和等于输入记录数。报告与诊断省去合成私密 ID。 | `report_wbtest.mbt` 与 CLI 测试 |

## 复现和验收入口

1. 从[公开仓库](https://github.com/chenqi-arch/moonsyncaudit)检出待验收提交。检查编译器版本至少是 `moonc 0.10.14`，按 [README](../README.md#复现测试)运行 Wasm 与 JavaScript 的检查、构建和测试。CI 执行同样的流程。
2. 从[三个样例目录](../examples/README.md)跑通命令行。现有台架样例先把设备时间 2000 ms 校准为 2040 ms，再与参考 2041 ms 配对。把独立校验文件换成超差版本后，仍有两对匹配，校验点残差为 3 ms 并退出 1。
3. 在独立 MoonBit 项目执行 `moon add chenqi-arch/moonsyncaudit@0.1.0`，复制[示例](../cmd/library-example/main.mbt)及[配置](../cmd/library-example/moon.pkg)到可执行包中。运行 Wasm 示例，预期 `status=PASS`，并报告一对配对、一个零残差校验点和完整区间覆盖。项目许可证见 [LICENSE](../LICENSE)。
