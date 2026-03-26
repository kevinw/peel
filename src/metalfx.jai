#scope_export

#if OS == .MACOS {
    using,only(dlopen, RTLD_LAZY, RTLD_LOCAL) POSIX :: #import "POSIX";
    #import "Objective_C_Tools";

    metalfx_framework_handle: *void;
    metalfx_framework_loaded := false;
    metalfx_compiler: *MTL4Compiler;
    metalfx_compiler_device: *MTLDevice;

    METALFX_FRAMEWORK_PATH :: "/System/Library/Frameworks/MetalFX.framework/MetalFX";

    selector_supported :: (obj: *void, name: string) -> bool {
        if obj == null return false;
        responds: (*void, Selector, Selector) -> BOOL #c_call;
        responds = xx objc_msgSend;
        return responds(obj, selector("respondsToSelector:"), selector(name)) != NO;
    }

    set_u64_if_supported :: (obj: *void, name: string, value: u64) {
        if !selector_supported(obj, name) return;
        set_u64: (*void, Selector, u64) -> void #c_call;
        set_u64 = xx objc_msgSend;
        set_u64(obj, selector(name), value);
    }

    set_u64_via_kvc :: (obj: *void, key: string, value: u64) {
        if obj == null return;

        property_count: u32;
        properties := class_copyPropertyList(object_getClass(xx obj), *property_count);
        property_found := false;
        for i: 0..property_count-1 {
            name := property_getName(properties[i]);
            if name != null && to_string(name) == key {
                property_found = true;
                break;
            }
        }
        if !property_found return;

        number_class := objc_getClass("NSNumber");
        if number_class == null return;

        make_number: (*void, Selector, u64) -> *NSNumber #c_call;
        make_number = xx objc_msgSend;
        set_value: (*void, Selector, *void, *NSString) -> void #c_call;
        set_value = xx objc_msgSend;

        number := make_number(number_class, selector("numberWithUnsignedLongLong:"), value);
        if number == null return;

        set_value(obj, selector("setValue:forKey:"), xx number, xx to_temp_nsstring(key));
    }

    set_metalfx_barrier_stages :: (scaler: *void, output_consumer_stages: MTLStages = cast(MTLStages) MTLStage.Fragment) {
        if scaler == null return;

        // Metal4FX appears to require explicit producer/consumer stage metadata for its textures.
        // These selectors aren't present in the public headers, so probe them dynamically.
        input_producer_stages := cast(u64) MTLStage.Fragment;
        output_consumer_stages_u64 := cast(u64) output_consumer_stages;

        set_u64_if_supported(scaler, "setColorTextureBarrierStages:", input_producer_stages);
        set_u64_if_supported(scaler, "setDepthTextureBarrierStages:", input_producer_stages);
        set_u64_if_supported(scaler, "setMotionTextureBarrierStages:", input_producer_stages);
        set_u64_if_supported(scaler, "setReactiveMaskTextureBarrierStages:", input_producer_stages);
        set_u64_if_supported(scaler, "setExposureTextureBarrierStages:", input_producer_stages);
        set_u64_if_supported(scaler, "setOutputTextureBarrierStages:", output_consumer_stages_u64);
        set_u64_via_kvc(scaler, "outputTextureBarrierStages", output_consumer_stages_u64);
    }

    ensure_metalfx_loaded :: () -> bool {
        if metalfx_framework_loaded return metalfx_framework_handle != null;
        metalfx_framework_loaded = true;
        metalfx_framework_handle = dlopen(METALFX_FRAMEWORK_PATH, RTLD_LAZY | RTLD_LOCAL);
        if metalfx_framework_handle == null {
            log_error("MetalFX: failed to load framework at '%'.", METALFX_FRAMEWORK_PATH);
            return false;
        }
        return true;
    }

    MTLFXSpatialScalerColorProcessingMode :: enum s64 {
        Perceptual :: 0;
        Linear     :: 1;
        HDR        :: 2;
    }

    metalfx_supports_spatial :: (device: *MTLDevice) -> bool {
        if !ensure_metalfx_loaded() || device == null return false;
        cls := objc_getClass("MTLFXSpatialScalerDescriptor");
        if cls == null return false;
        supports_device: (*void, Selector, *MTLDevice) -> BOOL #c_call;
        supports_device = xx objc_msgSend;
        return supports_device(cls, selector("supportsMetal4FX:"), device) != NO;
    }

    metalfx_supports_temporal :: (device: *MTLDevice) -> bool {
        if !ensure_metalfx_loaded() || device == null return false;
        cls := objc_getClass("MTLFXTemporalScalerDescriptor");
        if cls == null return false;
        supports_device: (*void, Selector, *MTLDevice) -> BOOL #c_call;
        supports_device = xx objc_msgSend;
        return supports_device(cls, selector("supportsMetal4FX:"), device) != NO;
    }

    metalfx_release_object :: (obj: *void) {
        if obj != null release(obj);
    }

    metalfx_release_compiler :: () {
        if metalfx_compiler != null {
            release(metalfx_compiler);
            metalfx_compiler = null;
        }
        metalfx_compiler_device = null;
    }

    ensure_metalfx_compiler :: (device: *MTLDevice) -> *MTL4Compiler {
        if device == null return null;
        if metalfx_compiler != null && metalfx_compiler_device == device return metalfx_compiler;
        metalfx_release_compiler();

        desc := objc_new(MTL4CompilerDescriptor);
        if desc == null return null;
        defer release(desc);

        compiler := MTLDevice.newCompilerWithDescriptor(device, desc, xx null);
        if compiler == null {
            log_error("MetalFX: failed creating MTL4Compiler.");
            return null;
        }

        metalfx_compiler = compiler;
        metalfx_compiler_device = device;
        return compiler;
    }

    metalfx_new_spatial_scaler :: (
        device: *MTLDevice,
        color_format: MTLPixelFormat,
        output_format: MTLPixelFormat,
        input_width: u32,
        input_height: u32,
        output_width: u32,
        output_height: u32,
        color_mode: MTLFXSpatialScalerColorProcessingMode = .Perceptual
    ) -> *void {
        if !ensure_metalfx_loaded() || device == null return null;
        compiler := ensure_metalfx_compiler(device);
        if compiler == null return null;
        cls := objc_getClass("MTLFXSpatialScalerDescriptor");
        if cls == null return null;

        desc := objc_init(objc_alloc(cls));
        if desc == null return null;
        defer release(desc);

        set_u64: (*void, Selector, u64) -> void #c_call;
        set_u64 = xx objc_msgSend;
        set_i64: (*void, Selector, s64) -> void #c_call;
        set_i64 = xx objc_msgSend;

        set_u64(desc, selector("setColorTextureFormat:"), cast(u64) color_format);
        set_u64(desc, selector("setOutputTextureFormat:"), cast(u64) output_format);
        set_u64(desc, selector("setInputWidth:"), cast(u64) input_width);
        set_u64(desc, selector("setInputHeight:"), cast(u64) input_height);
        set_u64(desc, selector("setOutputWidth:"), cast(u64) output_width);
        set_u64(desc, selector("setOutputHeight:"), cast(u64) output_height);
        set_i64(desc, selector("setColorProcessingMode:"), cast(s64) color_mode);

        new_scaler: (*void, Selector, *MTLDevice, *MTL4Compiler) -> *void #c_call;
        new_scaler = xx objc_msgSend;
        return new_scaler(desc, selector("newSpatialScalerWithDevice:compiler:"), device, compiler);
    }

    metalfx_spatial_encode :: (
        scaler: *void,
        cmd_buffer: *MTL4CommandBuffer,
        color_texture: *MTLTexture,
        output_texture: *MTLTexture,
        input_content_width: u32,
        input_content_height: u32
    ) {
        if scaler == null || cmd_buffer == null || color_texture == null || output_texture == null return;

        set_u64: (*void, Selector, u64) -> void #c_call;
        set_u64 = xx objc_msgSend;
        set_obj: (*void, Selector, *void) -> void #c_call;
        set_obj = xx objc_msgSend;
        encode: (*void, Selector, *MTL4CommandBuffer) -> void #c_call;
        encode = xx objc_msgSend;

        set_u64(scaler, selector("setInputContentWidth:"), cast(u64) input_content_width);
        set_u64(scaler, selector("setInputContentHeight:"), cast(u64) input_content_height);
        set_obj(scaler, selector("setColorTexture:"), xx color_texture);
        set_obj(scaler, selector("setOutputTexture:"), xx output_texture);
        set_metalfx_barrier_stages(scaler);
        encode(scaler, selector("encodeToCommandBuffer:"), cmd_buffer);
    }

    metalfx_new_temporal_scaler :: (
        device: *MTLDevice,
        color_format: MTLPixelFormat,
        depth_format: MTLPixelFormat,
        motion_format: MTLPixelFormat,
        output_format: MTLPixelFormat,
        input_width: u32,
        input_height: u32,
        output_width: u32,
        output_height: u32
    ) -> *void {
        if !ensure_metalfx_loaded() || device == null return null;
        cls := objc_getClass("MTLFXTemporalScalerDescriptor");
        if cls == null return null;

        desc := objc_init(objc_alloc(cls));
        if desc == null return null;
        defer release(desc);

        set_u64: (*void, Selector, u64) -> void #c_call;
        set_u64 = xx objc_msgSend;
        set_u64(desc, selector("setColorTextureFormat:"), cast(u64) color_format);
        set_u64(desc, selector("setDepthTextureFormat:"), cast(u64) depth_format);
        set_u64(desc, selector("setMotionTextureFormat:"), cast(u64) motion_format);
        set_u64(desc, selector("setOutputTextureFormat:"), cast(u64) output_format);
        set_u64(desc, selector("setInputWidth:"), cast(u64) input_width);
        set_u64(desc, selector("setInputHeight:"), cast(u64) input_height);
        set_u64(desc, selector("setOutputWidth:"), cast(u64) output_width);
        set_u64(desc, selector("setOutputHeight:"), cast(u64) output_height);
        new_scaler: (*void, Selector, *MTLDevice) -> *void #c_call;
        new_scaler = xx objc_msgSend;
        return new_scaler(desc, selector("newTemporalScalerWithDevice:"), device);
    }

    metalfx_temporal_encode :: (
        scaler: *void,
        cmd_buffer: *MTL4CommandBuffer,
        color_texture: *MTLTexture,
        depth_texture: *MTLTexture,
        motion_texture: *MTLTexture,
        output_texture: *MTLTexture,
        input_content_width: u32,
        input_content_height: u32,
        jitter_x: float,
        jitter_y: float,
        reset_history: bool
    ) {
        if scaler == null || cmd_buffer == null || color_texture == null || depth_texture == null || motion_texture == null || output_texture == null return;

        set_u64: (*void, Selector, u64) -> void #c_call;
        set_u64 = xx objc_msgSend;
        set_obj: (*void, Selector, *void) -> void #c_call;
        set_obj = xx objc_msgSend;
        set_f32: (*void, Selector, float) -> void #c_call;
        set_f32 = xx objc_msgSend;
        set_bool: (*void, Selector, BOOL) -> void #c_call;
        set_bool = xx objc_msgSend;
        encode: (*void, Selector, *MTL4CommandBuffer) -> void #c_call;
        encode = xx objc_msgSend;

        set_u64(scaler, selector("setInputContentWidth:"), cast(u64) input_content_width);
        set_u64(scaler, selector("setInputContentHeight:"), cast(u64) input_content_height);
        set_obj(scaler, selector("setColorTexture:"), xx color_texture);
        set_obj(scaler, selector("setDepthTexture:"), xx depth_texture);
        set_obj(scaler, selector("setMotionTexture:"), xx motion_texture);
        set_obj(scaler, selector("setOutputTexture:"), xx output_texture);
        set_f32(scaler, selector("setJitterOffsetX:"), jitter_x);
        set_f32(scaler, selector("setJitterOffsetY:"), jitter_y);
        set_f32(scaler, selector("setMotionVectorScaleX:"), 1.0);
        set_f32(scaler, selector("setMotionVectorScaleY:"), 1.0);
        set_bool(scaler, selector("setDepthReversed:"), NO);
        set_bool(scaler, selector("setReset:"), ifx reset_history then YES else NO);
        set_metalfx_barrier_stages(scaler);
        encode(scaler, selector("encodeToCommandBuffer:"), cmd_buffer);
    }
}
