//
// Note: this module also serves as a bucket where Globals_Reload deposits functions returning pointers to data which needs to be reloaded.
//

Global_Entry :: struct {
  name_hash: u32;
  module_name_hash: u32;
  data: *void;
  size: s64;
  ti: *Type_Info;
}

Proc_Flags :: enum_flags u8 {
    None :: 0;
    Key_Press_Proc :: 1 << 0;
    Key_Hold_Proc  :: 1 << 1;
}
