///|
fn main raise {
  let anchors = @sync.parse_clock_points(
    "device_ms\treference_ms\n0\t100\n1000000\t1000300",
  )
  let device = @sync.parse_records("id\tt_ms\nalarm\t500000")
  let reference = @sync.parse_records("id\tt_ms\nframe\t500200")
  let checks = @sync.parse_clock_points(
    "device_ms\treference_ms\n750000\t750250",
  )
  let clock = @sync.ClockModel::new(anchors[:])
  let report = @sync.audit(
    clock,
    device[:],
    reference[:],
    tolerance_ms=0L,
    checkpoints=checks[:],
    checkpoint_tolerance_ms=0L,
    strict=true,
  )
  guard report.passed() else { abort(report.to_text()) }
  let segment = report.segments()[0]
  guard segment.checkpoint_count == 1 && segment.max_abs_residual_ms == Some(0L) else {
    abort("Expected one independent checkpoint with zero residual")
  }
  println(report.to_text())
}
