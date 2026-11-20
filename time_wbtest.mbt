///|
test "timestamp keeps exact precision at the limits of nonnegative Int64" {
  assert_eq(parse_timestamp_ms("0"), 0L)
  assert_eq(parse_timestamp_ms("9007199254740993"), 9007199254740993L)
  assert_eq(parse_timestamp_ms("9223372036854775807"), MAX_TIME_MS)
}

///|
test "invalid decimal timestamps keep only the source row and code" {
  for
    text in [
      "", "-1", "+1", " 1", "1 ", "1.0", "1e3", "１２", "9223372036854775808",
    ] {
    let rejected = try {
      ignore(parse_timestamp_ms(text, line=8))
      false
    } catch {
      InvalidInput(BadTime, 8) => true
      _ => false
    }
    assert_true(rejected)
  }
}
