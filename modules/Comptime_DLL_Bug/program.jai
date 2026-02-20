mylib :: #library,no_static_library "mylib";
say_hello_from_the_dll :: ()  #foreign mylib;

main :: () {
    // runtime works fine.
    log("at runtime...");
    say_hello_from_the_dll();
}

#run,stallable {
    // CRASH
    say_hello_from_the_dll();

    #import "POSIX";
    handle := dlopen("mylib.dylib", RTLD_NOW);
    assert(handle != null);
    dyn_say_hello := cast(type_of(say_hello_from_the_dll))dlsym(handle, "say_hello_from_the_dll");
    assert(dyn_say_hello != null);
    log("resolved say_hello_from_the_dll via dlsym");
    dyn_say_hello();
}


#scope_file
#import "Basic";
