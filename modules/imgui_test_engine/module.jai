#if OS == {
case .MACOS;   #load "macos.jai";
case .WINDOWS; #load "windows.jai";
case .LINUX;   #load "linux.jai";
case; #assert false "TODO: implement for this platform";
}
