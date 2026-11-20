# MoonSyncAudit 可靠性测试与验收

`moon test --target wasm --deny-warn` 和 `moon test --target js --deny-warn` 分别运行同一组核心用例。`node scripts/verify-cli.mjs` 调用 `moon build --target js --deny-warn` 生成的命令行程序，校验文件输入、实际输出和退出码。样例均为合成数据。

| 重点 | 输入和应观察到的结果 | 对应证据 |
| --- | --- | --- |
| 时钟偏移和漂移 | 锚点 0→100、1,000,000→1,000,300 ms。500,000 ms 映射为 500,200 ms。接入第三锚点后，检查跨段和共用端点。 | `clock_wbtest.mbt` 和巡检场景 |
| 校准覆盖和整数精度 | 对锚点区间外的两侧数据报告覆盖外。接近 Int64 上界的时间值保持精确。溢出、倒序和超大间隔返回输入错误。 | `time_wbtest.mbt`、`clock_wbtest.mbt`、`audit_wbtest.mbt` |
| 含等值的容差 | 100 和 103 ms 在 3 ms 容差时可配对。100 和 104 ms 无候选。 | `pairing_wbtest.mbt` |
| 重复配对和得出相同结果 | 两条扫码围绕一条称重记录，三条均报冲突。逐对枚举生成独立参考，4,900 组输入的候选数和配对逐项一致。10 万对 10 万条同一毫秒时，所有窗口存在冲突，配对数为 0。 | `pairing_oracle_wbtest.mbt` 和产线场景 |
| 独立校验影响验收 | 台架校验点 2 ms 合格，3 ms 超差时退出 1，即使记录都已配对。用拟合锚点充当独立证据会被拒绝。 | `checkpoints_wbtest.mbt` 和台架场景 |
| 文件边界 | 短读后仍只打开一次。8 MiB 文件进入解析，超过上限的文件最多读取 8,388,609 字节，并在 UTF-8 解码前拒绝。非法 UTF-8、列数和重复 ID 均有失败用例。 | `scripts/verify-cli.mjs`、`tests/observe-file-read.cjs` 和 `tables_wbtest.mbt` |
| 报告可复现 | 相同输入生成相同报告。配对两端和问题行之和等于输入记录数。报告与诊断省去合成私密 ID。 | `report_wbtest.mbt` 与 CLI 测试 |

评审可从 [三个样例目录](../examples/README.md) 复现，或在 GitHub Actions 查看当前仓库提交的检查。通过条件由行覆盖和校验点状态决定，依赖调用者提供的锚点、校验点与时间容差。
