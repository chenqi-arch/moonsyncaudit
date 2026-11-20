///|
test "the exact tolerance is included and the next millisecond is excluded" {
  let matched = pair_timestamps([100L][:], [103L][:], tolerance_ms=3L)
  assert_eq(matched.pairs().length(), 1)
  assert_eq(matched.pairs()[0].delta_ms, 3L)
  assert_eq(
    pair_timestamps([100L][:], [104L][:], tolerance_ms=3L).pairs().length(),
    0,
  )
  assert_eq(
    pair_timestamps([100L][:], [97L][:], tolerance_ms=3L).pairs()[0].delta_ms,
    -3L,
  )
}

///|
test "both candidate directions must be unique, including tied timestamps" {
  let many_to_one = pair_timestamps([100L, 104L][:], [102L][:], tolerance_ms=3L)
  assert_eq(many_to_one.pairs().length(), 0)
  assert_eq(many_to_one.device_candidate_counts(), [1, 1])
  assert_eq(many_to_one.reference_candidate_counts(), [2])
  let one_to_many = pair_timestamps([100L][:], [100L, 100L][:], tolerance_ms=0L)
  assert_eq(one_to_many.pairs().length(), 0)
  assert_eq(one_to_many.device_candidate_counts(), [2])
  assert_eq(one_to_many.reference_candidate_counts(), [1, 1])
}

///|
test "timestamp candidate windows saturate safely at both Int64 bounds" {
  let a = pair_timestamps(
    [MAX_TIME_MS - 1L][:],
    [MAX_TIME_MS][:],
    tolerance_ms=10L,
  )
  assert_eq(a.pairs().length(), 1)
  assert_eq(a.pairs()[0].delta_ms, 1L)
  let b = pair_timestamps([0L][:], [MAX_TIME_MS][:], tolerance_ms=MAX_TIME_MS)
  assert_eq(b.pairs()[0].delta_ms, MAX_TIME_MS)
  let c = pair_timestamps([MAX_TIME_MS][:], [0L][:], tolerance_ms=MAX_TIME_MS)
  assert_eq(c.pairs()[0].delta_ms, -MAX_TIME_MS)
}

///|
test "calibrated timestamp inputs reject reversal and negative tolerance" {
  let reversed = try {
    ignore(pair_timestamps([10L, 9L][:], [10L][:], tolerance_ms=1L))
    false
  } catch {
    InvalidInput(TimeReversed, _) => true
    _ => false
  }
  assert_true(reversed)
  let invalid_tolerance = try {
    ignore(pair_timestamps([10L][:], [10L][:], tolerance_ms=-1L))
    false
  } catch {
    InvalidInput(NegativeTolerance, _) => true
    _ => false
  }
  assert_true(invalid_tolerance)
}
