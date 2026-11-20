///|
test "audit accounts for both sides and never pairs across the anchor limits" {
  let model = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n100\t100\n200\t200")[:],
  )
  let a = parse_records(
    "id\tt_ms\nleft-out\t99\nmatched\t100\nleft-gap\t125\nleft-out-2\t201",
  )
  let b = parse_records(
    "id\tt_ms\nright-out\t99\nmatched\t102\nright-gap\t145\nright-out-2\t201",
  )
  let result = audit(model, a[:], b[:], tolerance_ms=3L)
  assert_true(!result.passed())
  assert_eq(result.pairs().length(), 1)
  assert_eq(result.pairs()[0].device_line, 3)
  assert_eq(result.pairs()[0].reference_line, 3)
  assert_eq(
    result
    .issues()
    .map(issue => (issue.side.tag(), issue.line, issue.kind.tag())),
    [
      ("device", 2, "OUTSIDE_CALIBRATION"),
      ("device", 4, "NO_CANDIDATE"),
      ("device", 5, "OUTSIDE_CALIBRATION"),
      ("reference", 2, "OUTSIDE_CALIBRATION"),
      ("reference", 4, "NO_CANDIDATE"),
      ("reference", 5, "OUTSIDE_CALIBRATION"),
    ],
  )
  assert_eq(
    result.pairs().length() * 2 + result.issues().length(),
    result.device_count() + result.reference_count(),
  )
}

///|
test "a failed independent checkpoint blocks the pass verdict with otherwise valid pairs" {
  let model = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t100\n1000000\t1000300")[:],
  )
  let a = parse_records("id\tt_ms\nsource\t500000")
  let b = parse_records("id\tt_ms\nref\t500200")
  let accepted = audit(model, a[:], b[:], tolerance_ms=0L)
  assert_true(accepted.passed())
  assert_eq(accepted.checks().length(), 0)
  let checks = parse_clock_points("device_ms\treference_ms\n750000\t750256")
  let rejected = audit(
    model,
    a[:],
    b[:],
    tolerance_ms=0L,
    checkpoints=checks[:],
    checkpoint_tolerance_ms=5L,
  )
  assert_eq(rejected.pairs().length(), 1)
  assert_eq(rejected.issues().length(), 0)
  assert_true(!rejected.passed())
  assert_eq(rejected.checks()[0].status, ResidualTooHigh)
  rejected.pairs().clear()
  assert_eq(rejected.pairs().length(), 1)
}

///|
test "empty logs cannot silently pass and a single empty side reports missing rows" {
  let model = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t0\n10\t10")[:],
  )
  let both_empty = try {
    ignore(audit(model, [], [], tolerance_ms=0L))
    false
  } catch {
    InvalidInput(NoRecords, 0) => true
    _ => false
  }
  assert_true(both_empty)
  let reference = parse_records("id\tt_ms\npresent\t3")
  let result = audit(model, [], reference[:], tolerance_ms=0L)
  assert_true(!result.passed())
  assert_eq(result.issues()[0].line, 2)
  assert_eq(result.issues()[0].kind.tag(), "NO_CANDIDATE")
}
