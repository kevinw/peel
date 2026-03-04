# Jai style notes

Jai inits all vars to zero, unless you say foo: int = ---;
Array slices []u32 or []My_Struct are preferred over pointers and counts. They are more concise and less error-prone.
Dynamic arrays like [..]string are the go-to data structure for a growing collection.
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
Prefer `pieces : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{2, 0}];` over repeating `Tetris_Offset.{...}` for each element.

Consider using enum_flags when we have 3+ bool toggles in a struct.
Lots of useful gamedev code is in ~/jai/modules and their examples folders.
Lots of useful Jai knowledge is in ~/jai/how_to  -- listing the files there is a good way to see topics available.
For visual/UI tasks, do opportunistic visual verification using framebuffer/readback snapshot tooling (for example, after first implementation and after coordinate/layout fixes), rather than relying only on code inspection.

For logging enum names, rather than doing a function like this:
manip_mode_name :: (mode: Manip_Mode) -> string {
    if mode == .TRANSLATE return "Translate";
    if mode == .ROTATE return "Rotate";
    return "Unknown";
}
just do log("%", mode); -- jai will print the enum name by default, which is much more concise and less error-prone.

when you have an if chain with 3+ elements like
  if foo == 42 return 100;
  if foo == 45 return 200;
  if foo == 50 return 300;
please use the "switch" if instead:
  if foo == {
  case 42; return 100;
  case 45; return 200;
  case 50; return 300;
  } 
remember that the c++ 'break' is implicit in Jai's switch statements, so you don't need to worry about fallthrough bugs. if you do need fallthrough, you can use #through;
