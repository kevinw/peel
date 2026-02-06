init_objective_c_tools :: () {
    if _sel.initWithObjects_forKeys_  return;
    init_objective_c_selector_struct(*_sel);
}

NSMutableDictionary :: struct (key: Type, value: Type) {
    using #as dict: NSDictionary(key, value);

    initWithObjects_forKeys :: (self: *NSMutableDictionary(key, value), objects: *NSArray(value), keys: *NSArray(key)) -> *NSMutableDictionary(key, value) {
        func :: #type (*void, Selector, *NSArray(value), *NSArray(key)) -> *NSMutableDictionary(key, value) #c_call;
        return (cast(func) objc_msgSend)(self, _sel.initWithObjects_forKeys_, objects, keys);
    }
}

push_nsautorelease_pool :: () #expand {
    pool := objc_init(objc_alloc(NSAutoreleasePool));
    `defer release(pool);
}

return_false_if :: (cond: bool, fmt_string: string, args: ..Any) #expand {
    if cond {
        log_error(fmt_string, ..args);
        `return false;
    }
}

to_temp_nsstring :: (str: string) -> *NSString #expand {
    result := NSString.initWithString(objc_alloc(NSString), str);
    `defer release(result);
    return result;
}

to_temp_nsstring :: (fmt: string, args: ..Any) -> *NSString #expand {
    str := tprint(fmt, ..args);

    result := NSString.initWithString(objc_alloc(NSString), str);
    `defer release(result);
    return result;
}

nserror_to_string :: (nsError: *NSError) -> string {
    // @Leak ?
    error_string := NSError.localizedDescription(nsError);
    error_string_utf8 := NSString.UTF8String(error_string);
    return to_string(error_string_utf8);
}

objc_new_defer_release :: ($T: Type) -> *T #expand {
    result := objc_new(T);
    `defer release(result);
    return result;
}

objc_push_new :: ($type: Type) -> *type #expand {
    instance := objc_init(objc_alloc(type));
    `defer release(instance);
    return instance;
}


make_nsdictionary_of_strings :: (elems: []$T/struct { name: string; value: string; }) -> *NSDictionary(NSString, NSString) {
    objects, keys: [..]*NSString;
    defer array_free(objects);
    defer array_free(keys);
    for elems {
        array_add(*keys,    NSString.getTempString(it.name));  // TODO: these use autorelease, but the rest is release. change this.
        array_add(*objects, NSString.getTempString(it.value));
    }
    nskeys := NSArray(NSString).arrayWithObjects(xx keys.data, keys.count.(u64));
    nsobjects := NSArray(NSString).arrayWithObjects(xx objects.data, objects.count.(u64));
    D :: NSMutableDictionary(NSString, NSString);
    return cast(*D)D.initWithObjects_forKeys(objc_alloc(D), nsobjects, nskeys);
    /*

    // TODO: Submit this to the Jai team.

    arrayWithObjects :: (objs: **Object_Type, count: NSUInteger) -> *NSArray(Object_Type) {
        func :: #type (*void, Selector, **Object_Type, NSUInteger) -> *NSArray(Object_Type) #c_call;
        return (cast(func) objc_msgSend)(objc_getClass("NSArray"), _sel.arrayWithObjects_count_, objs, count);
    }
    */
}

for_expansion :: (array: *$T/NSArray, body: Code, flags: For_Flags) #expand {
    assert(array != null, "for_expansion for NSArray received a null pointer");
    #assert(flags == 0);
    for i: 0..array.count(array) - 1 {
        `it := array.objectAtIndex(array, i);
        `it_index := i;
        // TODO: implement remove
        // #insert(remove=#assert(false), break=break) body; // also: jai_parser in Jails was hanging on the break in this line.
        #insert(remove=#assert(false)) body;
    }
}


#scope_file
#import "Objective_C";
#import "Basic";

_sel: struct {
    initWithObjects_forKeys_:                                         Selector;
}
