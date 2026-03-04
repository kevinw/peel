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
