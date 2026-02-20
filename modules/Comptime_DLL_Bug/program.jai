mylib :: #library,no_static_library "mylib";
say_hello_from_the_dll :: () #elsewhere mylib;

main :: () {
    // runtime works fine.
    say_hello_from_the_dll();
}

#run,stallable {
    //
    // CRASH
    //

    // but this causes a crash, despite the compiler usually being able to link dynamically
    // (at least on macOS).
    say_hello_from_the_dll();

    /*
    #import "POSIX";
    handle := dlopen("mylib.dylib", RTLD_NOW);
    assert(handle != null);
    dyn_say_hello := cast(type_of(MyLib.say_hello_from_the_dll))dlsym(handle, "say_hello_from_the_dll");
    log("calling say hello");
    dyn_say_hello();
    */
}


#scope_file
#import "Basic";
