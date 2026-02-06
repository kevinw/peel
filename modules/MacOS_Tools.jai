current_memory_usage_bytes :: () -> u64 {
    info: task_vm_info_data_t;

    natural_t :: u32;
    KERN_SUCCESS :: 0;
    TASK_VM_INFO_COUNT :: size_of(task_vm_info_data_t) / size_of(natural_t);

    count: mach_msg_type_number_t = TASK_VM_INFO_COUNT;
    result := task_info(mach_task_self(), TASK_VM_INFO, xx *info, *count);

    if result != KERN_SUCCESS {
        return 0;
    }

    return info.phys_footprint;
}

#scope_file
#import "macos";
