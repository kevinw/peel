//
// Run child processes in parallel
//
parallel_run :: (args_for_each_run: [][]string) -> bool {
  fail :: (fmt: string, args: ..Any) #expand {
    for * children if !it.done {
      kill_process(*it.proc);
    }
    log_error(fmt, ..args);
    `return false;
  }

  children: [..]struct { proc: Process; done: bool; };
  defer {
      for children deinit(*it.proc);
  }

  // spawn processes
  for args: args_for_each_run {
    child := array_add(*children);
    create_success := create_process(*child.proc, ..args, capture_and_return_output=true);
    if !create_success
      fail("Failed to create subprocess for build %", it_index);
  }

  // interleave output
  done_count := 0;
  while done_count < children.count {
    made_progress := false;
    for args_for_each_run {
      if children[it_index].done continue;
      child := *children[it_index].proc;

      out_buf: [4096]u8;
      err_buf: [4096]u8;
      read_ok, output_bytes, error_bytes := read_from_process(child, out_buf, err_buf, timeout_ms = 0);
      if !read_ok fail("Failed while reading output from build %", it_index);

      if output_bytes > 0 {
        write_string(to_string(out_buf.data, output_bytes), to_standard_error = false);
        made_progress = true;
      }
      if error_bytes > 0 {
        write_string(to_string(err_buf.data, error_bytes), to_standard_error = true);
        made_progress = true;
      }

      if child.output.eof && child.error.eof {
        result_ok, process_result := get_process_result(child, timeout_ms = -1);
        if !result_ok fail("Failed to fetch subprocess result for build %", it_index);

        children[it_index].done = true;
        done_count += 1;

        if process_result.type != .EXITED || process_result.exit_code != 0 {
          fail("Subprocess build % failed with exit code %.", it_index, process_result.exit_code);
        }
      }
    }
    if !made_progress {
      sleep_milliseconds(1);
    }
  }
  return true;
}

#scope_file
#import "Process";
#import "Basic";
