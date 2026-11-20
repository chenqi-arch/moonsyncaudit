///|
priv suberror CliError {
  UsageError
  InputProblem(String, String, Int)
}

///|
priv struct Options {
  device : String
  reference : String
  anchors : String
  tolerance_ms : Int64
  checkpoints : String?
  checkpoint_tolerance_ms : Int64
  as_json : Bool
}

///|
let usage : String =
  #|MoonSyncAudit checks the pairing of two offline timestamp tables.
  #|Usage:
  #|  moon run --target js cmd/main -- audit DEVICE.tsv REFERENCE.tsv ANCHORS.tsv --tolerance-ms N
  #|    [--checkpoints POINTS.tsv] [--checkpoint-tolerance-ms N] [--format text|json]
  #|Exit 0: pass. Exit 1: rows or check points need review. Exit 2: invalid input or file error.

///|
fn parse_tolerance(raw : String, option : String) -> Int64 raise CliError {
  @sync.parse_timestamp_ms(raw[:]) catch {
    _ => raise InputProblem(option, "BAD_TOLERANCE", 0)
  }
}

///|
fn parse_options(args : FixedArray[String]) -> Options raise CliError {
  guard args.length() >= 6 && args[0] == "audit" else { raise UsageError }
  let flags : Map[String, String] = Map([])
  let mut index = 4
  while index < args.length() {
    let name = args[index]
    guard index + 1 < args.length() && !flags.contains(name) else {
      raise UsageError
    }
    match name {
      "--tolerance-ms"
      | "--checkpoints"
      | "--checkpoint-tolerance-ms"
      | "--format" => flags[name] = args[index + 1]
      _ => raise UsageError
    }
    index += 2
  }
  guard flags.get("--tolerance-ms") is Some(tolerance) else { raise UsageError }
  let tolerance_ms = parse_tolerance(tolerance, "tolerance-ms")
  let checkpoints = flags.get("--checkpoints")
  let checkpoint_tolerance_ms = match flags.get("--checkpoint-tolerance-ms") {
    Some(raw) => {
      guard checkpoints is Some(_) else { raise UsageError }
      parse_tolerance(raw, "checkpoint-tolerance-ms")
    }
    None => tolerance_ms
  }
  let as_json = match flags.get("--format") {
    None | Some("text") => false
    Some("json") => true
    _ => raise UsageError
  }
  {
    device: args[1],
    reference: args[2],
    anchors: args[3],
    tolerance_ms,
    checkpoints,
    checkpoint_tolerance_ms,
    as_json,
  }
}

///|
fn read_table(path : String, label : String) -> String raise CliError {
  let input = node_read_table(path, @sync.TABLE_LIMIT_BYTES)
  if input.has_prefix("+") {
    return input[1:].to_owned()
  }
  let code = match input {
    "L" => "TABLE_LIMIT"
    "U" => "INVALID_UTF8"
    _ => "READ_FAILED"
  }
  raise InputProblem(label, code, 0)
}

///|
fn load_records(
  path : String,
  label : String,
) -> Array[@sync.Record] raise CliError {
  let text = read_table(path, label)
  @sync.parse_records(text) catch {
    error => raise InputProblem(label, error.code().tag(), error.line())
  }
}

///|
fn load_points(
  path : String,
  label : String,
) -> Array[@sync.ClockPoint] raise CliError {
  let text = read_table(path, label)
  @sync.parse_clock_points(text) catch {
    error => raise InputProblem(label, error.code().tag(), error.line())
  }
}

///|
fn run(options : Options) -> @sync.AuditReport raise CliError {
  let device = load_records(options.device, "device")
  let reference = load_records(options.reference, "reference")
  let anchors = load_points(options.anchors, "anchors")
  let clock = @sync.ClockModel::new(anchors[:]) catch {
    error => raise InputProblem("anchors", error.code().tag(), error.line())
  }
  let checkpoints = options.checkpoints.map(path => {
    load_points(path, "checkpoints")
  })
  let checkpoint_views = checkpoints.map(points => points[:])
  @sync.audit(
    clock,
    device[:],
    reference[:],
    tolerance_ms=options.tolerance_ms,
    checkpoints?=checkpoint_views,
    checkpoint_tolerance_ms=options.checkpoint_tolerance_ms,
  ) catch {
    error => {
      let label = match error.code() {
        @sync.CheckpointOrder
        | @sync.CheckpointsMissing
        | @sync.CheckpointOnAnchor => "checkpoints"
        _ => "audit"
      }
      raise InputProblem(label, error.code().tag(), error.line())
    }
  }
}

///|
fn main {
  let args = node_args()
  if args.length() == 1 && (args[0] == "--help" || args[0] == "-h") {
    println(usage)
    return
  }
  try {
    let options = parse_options(args)
    let report = run(options)
    println(
      if options.as_json {
        report.to_json().stringify()
      } else {
        report.to_text()
      },
    )
    node_set_exit(if report.passed() { 0 } else { 1 })
  } catch {
    UsageError => {
      node_stderr("ERROR code=USAGE\n" + usage)
      node_set_exit(2)
    }
    InputProblem(label, code, line) => {
      node_stderr("ERROR input=\{label} code=\{code} line=\{line}")
      node_set_exit(2)
    }
  }
}
