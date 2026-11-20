///|
test "held-out points accept the threshold and report signed residuals" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t100\n1000000\t1000300")[:],
  )
  let points : Array[ClockPoint] = [
    { device_ms: 100L, reference_ms: 195L, line: 2, },
    { device_ms: 750000L, reference_ms: 750256L, line: 3, },
  ]
  let results = clock.check_points(points[:], tolerance_ms=5L)
  assert_eq(results[0].status, WithinTolerance)
  assert_eq(results[0].residual_ms, Some(-5L))
  assert_eq(results[1].status, ResidualTooHigh)
  assert_eq(results[1].residual_ms, Some(6L))
}

///|
test "a held-out point on a fit anchor is rejected as dependent evidence" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n100\t100\n200\t200\n300\t300")[:],
  )
  for ms in [100L, 200L, 300L] {
    let rejected = try {
      ignore(
        clock.check_points(
          [{ device_ms: ms, reference_ms: ms, line: 2, }][:],
          tolerance_ms=1L,
        ),
      )
      false
    } catch {
      InvalidInput(CheckpointOnAnchor, 2) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "outside checkpoints are distinct from residual errors" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n100\t100\n200\t200")[:],
  )
  let points : Array[ClockPoint] = [
    { device_ms: 90L, reference_ms: 101L, line: 2, },
    { device_ms: 190L, reference_ms: 201L, line: 3, },
  ]
  let result = clock.check_points(points[:], tolerance_ms=MAX_TIME_MS)
  assert_eq(result[0].status, OutsideAnchors)
  assert_eq(result[1].status, OutsideAnchors)
  assert_eq(result[0].residual_ms, None)
  assert_eq(result[1].residual_ms, None)
}
