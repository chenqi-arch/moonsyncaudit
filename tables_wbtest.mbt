///|
test "tables preserve Unicode IDs, tied millisecond order and source rows" {
  let rows = parse_records(
    "\uFEFFid\tt_ms\r\n巡检🛤\t12\r\npart-2\t12\nframe-3\t30",
  )
  assert_eq(rows.length(), 3)
  assert_eq(rows[0].id, "巡检🛤")
  assert_eq(rows[1].time_ms, 12L)
  assert_eq(rows[2].line, 4)
  let anchors = parse_clock_points(
    "device_ms\treference_ms\n0\t100\n1000000\t1000300\n",
  )
  assert_eq(anchors.length(), 2)
  assert_eq(anchors[1].reference_ms, 1000300L)
  assert_eq(anchors[1].line, 3)
}

///|
test "record table rejects malformed rows without echoing raw cells" {
  let cases : Array[(String, InputCode, Int)] = [
    ("", BadHeader, 1),
    ("wrong\tt_ms\nabc\t1", BadHeader, 1),
    ("id\tt_ms\nx", BadRow, 2),
    ("id\tt_ms\nx\t1\textra", BadRow, 2),
    ("id\tt_ms\nx\t1\r", BadRow, 2),
    ("id\tt_ms\n\r\n", BadRow, 2),
    ("id\tt_ms\nx\t1\n\n", BadRow, 3),
    ("id\tt_ms\n\t1", BadId, 2),
    ("id\tt_ms\n \t1", BadId, 2),
    ("id\tt_ms\nx\t1\nx\t2", DuplicateId, 3),
    ("id\tt_ms\nx\t2\ny\t1", TimeReversed, 3),
    ("id\tt_ms\nsample-secret\tbad", BadTime, 2),
  ]
  for (text, expected_code, expected_line) in cases {
    let rejected = try {
      ignore(parse_records(text))
      false
    } catch {
      InvalidInput(code, line) => {
        assert_eq(code, expected_code)
        assert_eq(line, expected_line)
        true
      }
    }
    assert_true(rejected)
  }
}

///|
test "header alone represents an empty side and clock columns are exact" {
  assert_eq(parse_records("id\tt_ms\n").length(), 0)
  assert_eq(parse_clock_points("device_ms\treference_ms").length(), 0)
  let rejected = try {
    ignore(parse_clock_points("reference_ms\tdevice_ms\n1\t1"))
    false
  } catch {
    InvalidInput(BadHeader, 1) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "TSV row budget accepts exactly its limit" {
  let mut count = 0
  read_tsv("id\tt_ms\none\t1\ntwo\t2", "id\tt_ms", 2, (_, _, _) => count += 1)
  assert_eq(count, 2)
  let rejected = try {
    read_tsv("id\tt_ms\none\t1\ntwo\t2\nthree\t3", "id\tt_ms", 2, (_, _, _) => {
      ()
    })
    false
  } catch {
    InvalidInput(RowLimit, 4) => true
    _ => false
  }
  assert_true(rejected)
}
