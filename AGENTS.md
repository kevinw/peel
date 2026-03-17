# Peel 

We're making a rapid and ergonomic game prototyping framework in Jai, a new systems prog lang.

Major components we are iterating on as we develop it: 
- modules/sgpu: a thin-as-possible bindless gpu abstraction for Metal/Vulkan that attempts to go all-in on "gpu memory is just more memory"
- modules/Jai-Shader-Transpiler: a compiler plugin which transpiles requested Jai functions into SPIRV, and ultimately Metal or Vulkan GLSL. Changes to it can be tested with the full suite via `jai modules/Jai-Shader-Transpiler/build.jai - -run_tests`. It provides shader hot reloading on relevant .jai file changes as well. A major goal is to create performant, ergonomic and robust/safe ways to move more compute to GPU in a way that is accessible and easy to actually use for gamedev tasks from Jai.
- src/ui.jai uses modules/ImGui for UI rendering.

On Mac, our main dev platform right now, sgpu uses Metal4 bindings in modules/sgpu/modules/Metal. Metal4 is vulkan-esque in that barriers and fences are used for explicit synchronization.

Peel entry points are "apps" defined in `src/apps`.
They are built with our `build.jai` metaprogram.
`jai build.jai - src/apps/textured_triangle.jai` builds a single app.
`jai build.jai - src/apps/textured_triangle.jai -run` builds and runs a single app after compilation.
`jai build.jai - src/apps/textured_triangle.jai -run -dll` builds the app as a DLL and runs it via the host DLL loader, so subsequent dll builds can live reload the new app code without restarting. Globals are automatically copied by name when possible from the old DLL's address space to the new one's via the `modules/Globals_Reload.jai` metaprogramming plugin. 
`jai build.jai` builds all apps in parallel--useful for a smoke test after a big change.

For visual/UI tasks in peel, there are environment variables to allow you to do visual verification using framebuffer/readback snapshot tooling (for example, after first implementation and after coordinate/layout fixes), rather than relying only on code inspection. For example PEEL_SNAPSHOT=1 will capture a snapshot of the framebuffer and save it out to a jpeg. Or PEEL_MAX_FRAMES=30 will run the app for 30 frames and exit. See src/readback_stats.jai and src/framebuffer_tools.jai.

Hard-fail is usually better than fallback paths: because we're rapidly iterating, keeping tests and app builds green is important, but too many fallback paths can make the code harder to understand and maintain, so we try to keep the garden healthy: the ergonomics of the app code, and the slimness of the codebase, matter.

# Jai language notes and style guide

Jai inits all vars to zero, unless you say `foo: int = ---;`
Array slices `[]u32` or `[]My_Struct` are preferred over pointers and counts. They are more concise and less error-prone.
Dynamic arrays like `my_files: [..]string;` are the go-to data structure for a growing collection.
Jai's "temp" allocator is useful for short lived allocations and is reset after each frame. A dynamic array's allocator can be set to `my_files.allocator = temp;`.
Prefer to keep utility functions not used by external callers in #scope_file at the bottom of the file.
Utility functions don't need a prefix with the filename or module name if they are #scope_file.
Remember the distinction between #import'ed modules and #load'ed files. #load does a textual include, while #import is more like a namespace import, and is deduplicated.
Only create new modules for reusable code which might be useful elsewhere. Prefer to put them in modules/.
When initializing a string with a count and data, prefer my_string := string.{ count, data_ptr };
When initializing structs, when possible, prefer 

foo := My_Struct.{
  value = 42,
  other_value = "hello",
};

over 

foo: My_Struct;
foo.value = 42;
foo.other_value = "hello";

For typed array literals of structs, omit redundant inner type names when possible for readability.
Prefer `pieces := Tetris_Offset.[{-1, 0}, {0, 0}, {1, 0}, {2, 0}];` over repeating `Tetris_Offset.{...}` for each element.
Constants are defined like `foo :: 42;` or `foo: int: 42;` (note that in the first, the type is inferred).
Consider using the `enum_flags` syntax when we have 3+ bool toggles in a struct.
Useful gamedev and "standard library" code is in ~/jai/modules and their examples folders.
Useful Jai knowledge is in ~/jai/how_to  -- listing files there is a good way to see topics available.
Jai has rich type information available at compile time and it's easy to define polymorphic functions and structs.

For logging enum names, rather than doing a function like this:
manip_mode_name :: (mode: Manip_Mode) -> string {
    if mode == .TRANSLATE return "Translate";
    if mode == .ROTATE return "Rotate";
    return "Unknown";
}
just do log("%", mode); -- jai will print the enum name by default, which is much more concise and less error-prone.

When you have an if chain with 3+ elements like...
```
  if foo == 42 return 100;
  if foo == 45 return 200;
  if foo == 50 return 300;
```
...Please use the "switch if" instead:
```
  if foo == {
  case 42; return 100;
  case 45; #through;
  case 50; return 300;
  } 
```
And re: "switch if", remember that the c++ 'break' is implicit in Jai's switch statements, so you don't need to worry about fallthrough bugs. if you do need fallthrough, you can use #through; like above.
Jai doesn't support closures, but if you have a small bit of code that you want to reuse in multiple places in a function, you can define a macro. Some backticked statements are supported like `return and `defer.
my_outer_func :: () -> int {
    foo := 0;
    
    my_inner_macro :: () #expand {
        foo += 1;
        log("foo now: %", foo);
        if foo == 2 {
          `return 100;
        }
    }
    
    my_inner_macro();
    my_inner_macro();
    my_inner_macro();
}

The simplest loops are over slices, and `it` and `it_index` are available in the loop body
```
func :: (my_collection: []s32) {
  for my_collection {
    log("element %: %", it_index, it);
  }
}
```
You can also name them:
```
for elem, elem_index: my_collection {
  log("element %: %", elem_index, elem);
}
```

Prefer `assert(my_condition, "my message: %", my_val)` over `assert(my_condition, tprint("my message: %", my_val))`.
Prefer `print_to_builder(*string_builder, "my message: %", my_val)` over `append(*string_builder, tprint("my message: %", my_val))`.
