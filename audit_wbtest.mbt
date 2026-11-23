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

///|
test "strict audit requires a measured checkpoint in every interval" {
  let clock = ClockModel::new(
    parse_clock_points(
      "device_ms\treference_ms\n0\t0\n100\t100\n200\t200\n300\t300",
    )[:],
  )
  let rows = parse_records("id\tt_ms\na\t50\nb\t150\nc\t250")
  let partial = parse_clock_points("device_ms\treference_ms\n50\t50\n250\t251")
  let regular = audit(
    clock,
    rows[:],
    rows[:],
    tolerance_ms=0L,
    checkpoints=partial[:],
    checkpoint_tolerance_ms=1L,
  )
  assert_true(regular.passed())
  let strict = audit(
    clock,
    rows[:],
    rows[:],
    tolerance_ms=0L,
    checkpoints=partial[:],
    checkpoint_tolerance_ms=1L,
    strict=true,
  )
  assert_true(!strict.passed())
  assert_eq(strict.pairs().length(), 3)
  assert_eq(strict.issues().length(), 0)
  assert_eq(
    strict
    .segments()
    .map(segment => {
      (
        segment.start_anchor_line,
        segment.end_anchor_line,
        segment.checkpoint_count,
        segment.max_abs_residual_ms,
      )
    }),
    [(2, 3, 1, Some(0L)), (3, 4, 0, None), (4, 5, 1, Some(1L))],
  )
  strict.segments().clear()
  assert_eq(strict.segments().length(), 3)
  let complete = parse_clock_points(
    "device_ms\treference_ms\n50\t50\n150\t149\n250\t251",
  )
  let pass = audit(
    clock,
    rows[:],
    rows[:],
    tolerance_ms=0L,
    checkpoints=complete[:],
    checkpoint_tolerance_ms=1L,
    strict=true,
  )
  assert_true(pass.passed())
}

///|
test "no points and out-of-range observations never provide strict coverage" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n100\t100\n200\t200")[:],
  )
  let rows = parse_records("id\tt_ms\nx\t150")
  let absent = audit(clock, rows[:], rows[:], tolerance_ms=0L, strict=true)
  assert_true(!absent.passed())
  assert_eq(absent.pairs().length(), 1)
  assert_eq(absent.segments()[0].max_abs_residual_ms, None)
  let outside = parse_clock_points("device_ms\treference_ms\n90\t101\n190\t201")
  let report = audit(
    clock,
    rows[:],
    rows[:],
    tolerance_ms=0L,
    checkpoints=outside[:],
    strict=true,
  )
  assert_true(!report.passed())
  assert_eq(report.segments()[0].checkpoint_count, 0)
  assert_eq(report.segments()[0].max_abs_residual_ms, None)
  assert_true(report.checks().all(row => row.status == OutsideAnchors))
}

///|
test "strict audit reports the worst absolute residual even when all rows pair" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t0\n100\t100")[:],
  )
  let rows = parse_records("id\tt_ms\nx\t50")
  let points = parse_clock_points(
    "device_ms\treference_ms\n20\t14\n40\t44\n70\t70",
  )
  let report = audit(
    clock,
    rows[:],
    rows[:],
    tolerance_ms=0L,
    checkpoints=points[:],
    checkpoint_tolerance_ms=5L,
    strict=true,
  )
  assert_true(!report.passed())
  assert_eq(report.pairs().length(), 1)
  assert_eq(report.checks()[0].residual_ms, Some(-6L))
  assert_eq(report.segments()[0].checkpoint_count, 3)
  assert_eq(report.segments()[0].max_abs_residual_ms, Some(6L))
}

///|
test "unspecified checkpoint tolerance follows the pairing tolerance" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t40\n10000\t10040")[:],
  )
  let device = parse_records("id\tt_ms\na\t2000\nb\t8000")
  let reference = parse_records("id\tt_ms\na\t2041\nb\t8040")
  let points = parse_clock_points("device_ms\treference_ms\n5000\t5043")
  let report = audit(
    clock,
    device[:],
    reference[:],
    tolerance_ms=2L,
    checkpoints=points[:],
    strict=true,
  )
  assert_eq(report.pairs().length(), 2)
  assert_eq(report.pairs()[0].delta_ms, 1L)
  assert_eq(report.checks()[0].residual_ms, Some(3L))
  assert_eq(report.checks()[0].status, ResidualTooHigh)
  assert_true(!report.passed())
  let overridden = audit(
    clock,
    device[:],
    reference[:],
    tolerance_ms=2L,
    checkpoints=points[:],
    checkpoint_tolerance_ms=3L,
    strict=true,
  )
  assert_true(overridden.passed())
}

///|
test "a header-only checkpoint table is equivalent to omitting checkpoints" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t40\n10000\t10040")[:],
  )
  let device = parse_records("id\tt_ms\na\t2000")
  let reference = parse_records("id\tt_ms\na\t2041")
  let points = parse_clock_points("device_ms\treference_ms\n")
  assert_true(clock.check_points(points[:], tolerance_ms=2L).is_empty())
  for strict in [false, true] {
    let absent = audit(clock, device[:], reference[:], tolerance_ms=2L, strict~)
    let empty = audit(
      clock,
      device[:],
      reference[:],
      tolerance_ms=2L,
      checkpoints=points[:],
      strict~,
    )
    assert_eq(empty.to_json().stringify(), absent.to_json().stringify())
    assert_eq(empty.pairs().length(), 1)
    assert_eq(empty.passed(), !strict)
  }
}
