///|
// Independent reference enumerates all candidate edges directly.
fn reference_pairs(
  a : ArrayView[Int64],
  b : ArrayView[Int64],
  tolerance_ms : Int64,
) -> (Array[Int], Array[Int], Array[(Int, Int, Int64)]) {
  let from_a = Array::make(a.length(), 0)
  let from_b = Array::make(b.length(), 0)
  for i, x in a {
    for j, y in b {
      if (y - x).abs() <= tolerance_ms {
        from_a[i] += 1
        from_b[j] += 1
      }
    }
  }
  let pairs = []
  for i, x in a {
    for j, y in b {
      if from_a[i] == 1 && from_b[j] == 1 && (y - x).abs() <= tolerance_ms {
        pairs.push((i, j, y - x))
      }
    }
  }
  (from_a, from_b, pairs)
}

///|
test "sliding windows agree with exhaustive edges on 4900 short inputs" {
  let rows : Array[Array[Int64]] = [[]]
  for a in 0..<4 {
    rows.push([a.to_int64()])
    for b in a..<4 {
      rows.push([a.to_int64(), b.to_int64()])
      for c in b..<4 {
        rows.push([a.to_int64(), b.to_int64(), c.to_int64()])
      }
    }
  }
  let mut cases = 0
  for a in rows {
    for b in rows {
      for tolerance in 0..<4 {
        let tolerance_ms = tolerance.to_int64()
        let found = pair_timestamps(a[:], b[:], tolerance_ms~)
        let (a_counts, b_counts, pairs) = reference_pairs(
          a[:],
          b[:],
          tolerance_ms,
        )
        assert_eq(found.device_candidate_counts(), a_counts)
        assert_eq(found.reference_candidate_counts(), b_counts)
        assert_eq(
          found
          .pairs()
          .map(p => (p.device_index, p.reference_index, p.delta_ms)),
          pairs,
        )
        cases += 1
      }
    }
  }
  assert_eq(cases, 4900)
}

///|
test "a dense 100000 by 100000 tolerance window has no false pairs" {
  let rows = Array::make(MAX_RECORDS, 10L)
  let outcome = pair_timestamps(rows[:], rows[:], tolerance_ms=0L)
  assert_true(outcome.pairs().is_empty())
  let a_counts = outcome.device_candidate_counts()
  let b_counts = outcome.reference_candidate_counts()
  assert_eq(a_counts.length(), MAX_RECORDS)
  assert_eq(b_counts.length(), MAX_RECORDS)
  assert_true(a_counts.all(n => n == MAX_RECORDS))
  assert_true(b_counts.all(n => n == MAX_RECORDS))
}
