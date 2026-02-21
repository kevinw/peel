// jai code which goes in a dll

#program_export
say_hello_from_the_dll :: () #c_call {
    push_context,defer_pop;
    log("hello from the dll");
    //return 42, "meep";
}

#import "Basic";
