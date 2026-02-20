// jai code which goes in a dll

#program_export
say_hello_from_the_dll :: () {
    Remap_Context();
    log("hello from the dll");
}

#import "Basic";
#import "Remap_Context";
