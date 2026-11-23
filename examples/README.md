# 合成样例

三个目录中的时间由测试设计给定，便于手算。记录 ID 是合成值。

| 目录 | 操作 | 预期 |
| --- | --- | --- |
| `inspection` | 用三锚点校准告警和候选帧。两条独立观测检查两段校准。 | 严格模式下配成 3 对，退出 0。省略校验点文件则仍有 3 对，缺覆盖并退出 1。换成 `reference-missing.tsv` 后，告警表第 3 行无候选，退出 1。 |
| `production` | 在 3 ms 容差下合并扫码和称重。 | 3 对，退出 0。换成 `reference-conflict.tsv` 后，两个扫码争用同一称重记录，仅第 3 个扫码配对，退出 1。 |
| `bench` | 用 2 ms 容差检查两路台架记录及独立校验点。 | 正常校验点偏差正好为 2 ms，退出 0。换成 `checkpoints-off.tsv` 后偏差变成 3 ms，退出 1。换成 `anchors-reversed.tsv` 后锚点无效，退出 2。 |

从仓库根目录运行对应命令，命令之间独立执行。

```powershell
moon run --target js cmd/main -- audit examples/inspection/device.tsv examples/inspection/reference.tsv examples/inspection/anchors.tsv --tolerance-ms 5 --checkpoints examples/inspection/checkpoints.tsv --strict
moon run --target js cmd/main -- audit examples/production/device.tsv examples/production/reference-conflict.tsv examples/production/anchors.tsv --tolerance-ms 3 --format json
moon run --target js cmd/main -- audit examples/bench/device.tsv examples/bench/reference.tsv examples/bench/anchors.tsv --tolerance-ms 2 --checkpoints examples/bench/checkpoints-off.tsv
```
