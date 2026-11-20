///|
extern "js" fn node_args() -> FixedArray[String] =
  #| () => globalThis.process.argv.slice(2)

///|
extern "js" fn node_stderr(message : String) -> Unit =
  #| (message) => { globalThis.process.stderr.write(message + "\n"); }

///|
extern "js" fn node_set_exit(code : Int) -> Unit =
  #| (code) => { globalThis.process.exitCode = code; }

///|
// Prefix the decoded text with a private success marker. Failures return a
// single category with no source path or operating-system error message.
extern "js" fn node_read_table(path : String, limit : Int) -> String =
  #| (path, limit) => {
  #|   const fs = globalThis.process.getBuiltinModule("node:fs");
  #|   let handle;
  #|   try {
  #|     handle = fs.openSync(path, fs.constants.O_RDONLY | (fs.constants.O_NONBLOCK ?? 0));
  #|     if (!fs.fstatSync(handle).isFile()) return "R";
  #|     const chunks = [];
  #|     let consumed = 0;
  #|     let used = 0;
  #|     let block = Buffer.allocUnsafe(Math.min(65536, limit + 1));
  #|     while (true) {
  #|       const got = fs.readSync(handle, block, used, block.length - used, null);
  #|       if (got === 0) break;
  #|       used += got;
  #|       consumed += got;
  #|       if (consumed > limit) return "L";
  #|       if (used === block.length) {
  #|         chunks.push(block);
  #|         block = Buffer.allocUnsafe(Math.min(65536, limit + 1 - consumed));
  #|         used = 0;
  #|       }
  #|     }
  #|     if (used > 0) chunks.push(block.subarray(0, used));
  #|     try {
  #|       const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
  #|       return "+" + decoder.decode(Buffer.concat(chunks, consumed));
  #|     } catch {
  #|       return "U";
  #|     }
  #|   } catch {
  #|     return "R";
  #|   } finally {
  #|     if (handle !== undefined) {
  #|       try { fs.closeSync(handle); } catch {}
  #|     }
  #|   }
  #| }
