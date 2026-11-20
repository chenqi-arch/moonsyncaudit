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
  assert_eq(@json.parse(encoded).stringify(), encoded)
  assert_eq(
    audit(clock, device[:], reference[:], tolerance_ms=5L).to_json().stringify(),
    encoded,
  )
}
