///|
test "both report formats preserve source rows and omit complete source identifiers" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t0\n100\t100")[:],
  )
  let device = parse_records(
    "id\tt_ms\nsynthetic-private-A\t10\nsynthetic-private-B\t20\nx\t99",
  )
  let reference = parse_records("id\tt_ms\nsynthetic-private-C\t15\ny\t100")
  let report = audit(clock, device[:], reference[:], tolerance_ms=5L)
  let encoded = report.to_json().stringify()
  let text = report.to_text()
  assert_true(!encoded.contains("synthetic-private"))
  assert_true(!text.contains("synthetic-private"))
  assert_true(
    text.contains(
      "status=REVIEW device=3 reference=2 pairs=1 issues=3 checkpoints=NOT_PROVIDED",
    ),
  )
  assert_true(text.contains("PAIR device_line=4 reference_line=3 delta_ms=1"))
  assert_true(
    text.contains(
      "ISSUE side=reference line=2 code=CANDIDATE_CONFLICT candidates=2",
    ),
  )
  assert_true(encoded.contains("\"delta_ms\":\"1\""))
  assert_true(
    encoded.contains("\"checkpoint_count\":0,\"max_abs_residual_ms\":null"),
  )
  assert_true(
    text.contains(
      "SEGMENT start_anchor_line=2 end_anchor_line=3 checkpoint_count=0",
    ),
  )
  assert_eq(
    report.to_pairs_tsv(),
    "device_line\treference_line\tdelta_ms\n4\t3\t1",
  )
  assert_eq(@json.parse(encoded).stringify(), encoded)
  assert_eq(
    audit(clock, device[:], reference[:], tolerance_ms=5L).to_json().stringify(),
    encoded,
  )
}

///|
test "the row index remains a valid TSV with no pairs" {
  let clock = ClockModel::new(
    parse_clock_points("device_ms\treference_ms\n0\t0\n100\t100")[:],
  )
  let device = parse_records("id\tt_ms\nsource\t10")
  let reference = parse_records("id\tt_ms\nref\t20")
  let report = audit(clock, device[:], reference[:], tolerance_ms=0L)
  assert_eq(report.to_pairs_tsv(), "device_line\treference_line\tdelta_ms")
}
