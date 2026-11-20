///|
test "clock drift is corrected separately on both sides of a shared anchor" {
  let clock = ClockModel::new(
    [
      { device_ms: 0L, reference_ms: 100L, line: 2, },
      { device_ms: 1000000L, reference_ms: 1000300L, line: 3, },
      { device_ms: 2000000L, reference_ms: 2000700L, line: 4, },
    ][:],
  )
  assert_eq(clock.project(0L), Some(100L))
  assert_eq(clock.project(500000L), Some(500200L))
  assert_eq(clock.project(750000L), Some(750250L))
  assert_eq(clock.project(1000000L), Some(1000300L))
  assert_eq(clock.project(1500000L), Some(1500500L))
  assert_eq(clock.project(2000000L), Some(2000700L))
  assert_eq(clock.project(-1L), None)
  assert_eq(clock.project(2000001L), None)
  assert_true(clock.covers_reference(2000700L))
  assert_true(!clock.covers_reference(99L))
}

///|
test "floor rounding is explicit at fractional reference milliseconds" {
  let clock = ClockModel::new(
    [
      { device_ms: 0L, reference_ms: 1L, line: 2, },
      { device_ms: 3L, reference_ms: 3L, line: 3, },
    ][:],
  )
  assert_eq(clock.project(1L), Some(1L))
  assert_eq(clock.project(2L), Some(2L))
}

///|
test "maximum span stays exact near Int64 maximum and the model owns its anchors" {
  let anchors : Array[ClockPoint] = [
    {
      device_ms: MAX_TIME_MS - MAX_SEGMENT_MS,
      reference_ms: MAX_TIME_MS - MAX_SEGMENT_MS,
      line: 2,
    },
    { device_ms: MAX_TIME_MS, reference_ms: MAX_TIME_MS, line: 3, },
  ]
  let clock = ClockModel::new(anchors[:])
  anchors[1] = { device_ms: 1L, reference_ms: 1L, line: 3, }
  assert_eq(clock.project(MAX_TIME_MS - 1L), Some(MAX_TIME_MS - 1L))
  assert_eq(clock.project(MAX_TIME_MS), Some(MAX_TIME_MS))
}

///|
test "duplicate, reversed and giant anchor spans are rejected on either clock" {
  let first : ClockPoint = { device_ms: 100L, reference_ms: 100L, line: 2, }
  let cases : Array[(Int64, Int64, InputCode)] = [
    (100L, 200L, AnchorOrder),
    (200L, 99L, AnchorOrder),
    (99L, 200L, AnchorOrder),
    (200L, 100L, AnchorOrder),
    (101L, 100L + MAX_SEGMENT_MS + 1L, SegmentTooLong),
    (100L + MAX_SEGMENT_MS + 1L, 101L, SegmentTooLong),
    (-1L, 101L, BadTime),
  ]
  for (device_ms, reference_ms, expected) in cases {
    let rejected = try {
      ignore(ClockModel::new([first, { device_ms, reference_ms, line: 3, }][:]))
      false
    } catch {
      InvalidInput(code, 3) => code == expected
      _ => false
    }
    assert_true(rejected)
  }
  let too_few = try {
    ignore(ClockModel::new([first][:]))
    false
  } catch {
    InvalidInput(AnchorsMissing, 0) => true
    _ => false
  }
  assert_true(too_few)
}
