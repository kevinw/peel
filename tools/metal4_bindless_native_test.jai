#import "Basic";
#import "Objective_C";
#import "String";
#import,file "../modules/sgpu/modules/Metal/module.jai";

SHADER :: #string END
#include <metal_stdlib>
using namespace metal;

struct Bindless_Set0 {
    texture2d<float> texture_0 [[id(1)]];
};

struct VSOut {
    float4 pos [[position]];
};

vertex VSOut VSMain(uint vid [[vertex_id]]) {
    VSOut o = {};
    float2 p;
    if (vid == 0u)      p = float2(0.0,  0.8);
    else if (vid == 1u) p = float2(-0.8, -0.8);
    else                p = float2(0.8, -0.8);
    o.pos = float4(p, 0.0, 1.0);
    return o;
}

fragment float4 FSMain(VSOut in [[stage_in]], constant Bindless_Set0& b [[buffer(0)]]) {
    (void)in;
    constexpr sampler s(address::clamp_to_edge, filter::nearest);
    return b.texture_0.sample(s, float2(0.5, 0.5));
}
END;

to_temp_nsstring :: (s: string) -> *NSString {
    return NSString.initWithString(objc_alloc(NSString), s);
}

check_error :: (err: *NSError, label: string) {
    if err != null {
        log_error("%: %", label, to_string(NSString.UTF8String(NSError.localizedDescription(err))));
        exit(1);
    }
}

main :: () {
    init_objective_c();
    pool := objc_new(NSAutoreleasePool);
    defer release(pool);

    device := MTLCreateSystemDefaultDevice();
    assert(device != null, "No Metal device");

    // Source texture (white)
    src_desc := objc_new(MTLTextureDescriptor);
    defer release(src_desc);
    src_desc.setTextureType(src_desc, ._2D);
    src_desc.setPixelFormat(src_desc, .RGBA8Unorm);
    src_desc.setWidth(src_desc, 4);
    src_desc.setHeight(src_desc, 4);
    src_desc.setDepth(src_desc, 1);
    src_desc.setMipmapLevelCount(src_desc, 1);
    src_desc.setArrayLength(src_desc, 1);
    src_desc.setSampleCount(src_desc, 1);
    src_desc.setUsage(src_desc, cast(MTLTextureUsage) MTLTextureUsage_1.ShaderRead);
    src_desc.setStorageMode(src_desc, .Shared);
    src_tex := device.newTextureWithDescriptor(device, src_desc);
    assert(src_tex != null);

    white : [4 * 4 * 4] u8;
    for i: 0..15 {
        base := i * 4;
        white[base + 0] = 255;
        white[base + 1] = 255;
        white[base + 2] = 255;
        white[base + 3] = 255;
    }
    region := MTLRegion.{ origin = .{x = 0, y = 0, z = 0}, size = .{width = 4, height = 4, depth = 1} };
    src_tex.replaceRegion(src_tex, region, 0, xx *white[0], 16);

    // Output RT
    rt_desc := objc_new(MTLTextureDescriptor);
    defer release(rt_desc);
    rt_desc.setTextureType(rt_desc, ._2D);
    rt_desc.setPixelFormat(rt_desc, .BGRA8Unorm);
    rt_desc.setWidth(rt_desc, 64);
    rt_desc.setHeight(rt_desc, 64);
    rt_desc.setDepth(rt_desc, 1);
    rt_desc.setMipmapLevelCount(rt_desc, 1);
    rt_desc.setArrayLength(rt_desc, 1);
    rt_desc.setSampleCount(rt_desc, 1);
    rt_desc.setUsage(rt_desc, cast(MTLTextureUsage) (MTLTextureUsage_1.RenderTarget | .ShaderRead));
    rt_desc.setStorageMode(rt_desc, .Shared);
    rt_tex := device.newTextureWithDescriptor(device, rt_desc);
    assert(rt_tex != null);

    // Library + pipeline
    comp_opts := objc_new(MTLCompileOptions);
    defer release(comp_opts);
    comp_opts.setLanguageVersion(comp_opts, ._3_2);

    err: *NSError = null;
    lib := device.newLibraryWithSource(device, to_temp_nsstring(SHADER), comp_opts, *err);
    check_error(err, "newLibraryWithSource");
    assert(lib != null);
    defer release(lib);

    vs := lib.newFunctionWithName(lib, to_temp_nsstring("VSMain"));
    fs := lib.newFunctionWithName(lib, to_temp_nsstring("FSMain"));
    assert(vs != null && fs != null);
    defer release(vs);
    defer release(fs);

    vfd := objc_new(MTL4LibraryFunctionDescriptor);
    defer release(vfd);
    vfd.setLibrary(vfd, lib);
    vfd.setName(vfd, MTLFunction.name(vs));

    ffd := objc_new(MTL4LibraryFunctionDescriptor);
    defer release(ffd);
    ffd.setLibrary(ffd, lib);
    ffd.setName(ffd, MTLFunction.name(fs));

    rp_desc := objc_new(MTL4RenderPipelineDescriptor);
    defer release(rp_desc);
    rp_desc.setVertexFunctionDescriptor(rp_desc, vfd);
    rp_desc.setFragmentFunctionDescriptor(rp_desc, ffd);
    ca := rp_desc.colorAttachments(rp_desc);
    ca0 := MTL4RenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(ca, 0);
    ca0.setPixelFormat(ca0, .BGRA8Unorm);

    cdesc := objc_new(MTL4CompilerDescriptor);
    defer release(cdesc);
    compiler := device.newCompilerWithDescriptor(device, cdesc, *err);
    check_error(err, "newCompilerWithDescriptor");
    assert(compiler != null);
    defer release(compiler);

    pso := compiler.newRenderPipelineStateWithDescriptor(compiler, rp_desc, null, *err);
    check_error(err, "MTL4 newRenderPipelineStateWithDescriptor");
    assert(pso != null);
    defer release(pso);

    // MTL4 queue/cmd setup
    q_desc := objc_new(MTL4CommandQueueDescriptor);
    defer release(q_desc);
    q := device.newMTL4CommandQueueWithDescriptor(device, q_desc, *err);
    check_error(err, "newMTL4CommandQueueWithDescriptor");
    assert(q != null);
    defer release(q);

    rs_desc := objc_new(MTLResidencySetDescriptor);
    defer release(rs_desc);
    rs_desc.setInitialCapacity(rs_desc, 16);
    rs := device.newResidencySetWithDescriptor(device, rs_desc, *err);
    check_error(err, "newResidencySetWithDescriptor");
    assert(rs != null);
    defer release(rs);
    rs.addAllocation(rs, cast(*MTLAllocation) src_tex);
    rs.addAllocation(rs, cast(*MTLAllocation) rt_tex);
    rs.addAllocation(rs, cast(*MTLAllocation) pso);
    rs.commit(rs);
    q.addResidencySet(q, rs);

    pool_desc := objc_new(MTLResourceViewPoolDescriptor);
    defer release(pool_desc);
    pool_desc.setResourceViewCount(pool_desc, 8);
    tex_pool := device.newTextureViewPoolWithDescriptor(device, pool_desc, *err);
    check_error(err, "newTextureViewPoolWithDescriptor");
    assert(tex_pool != null);
    defer release(tex_pool);

    a_desc := objc_new(MTL4CommandAllocatorDescriptor);
    defer release(a_desc);
    alloc := device.newCommandAllocatorWithDescriptor(device, a_desc, *err);
    check_error(err, "newCommandAllocatorWithDescriptor");
    assert(alloc != null);
    defer release(alloc);

    cmd := device.newCommandBuffer(device);
    assert(cmd != null);
    defer release(cmd);
    cmd.beginCommandBufferWithAllocator(cmd, alloc);

    pass := objc_new(MTL4RenderPassDescriptor);
    defer release(pass);
    pass_colors := pass.colorAttachments(pass);
    pass_ca0 := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(pass_colors, 0);
    pass_ca0.setTexture(pass_ca0, rt_tex);
    pass_ca0.setLoadAction(pass_ca0, .Clear);
    pass_ca0.setStoreAction(pass_ca0, .Store);
    pass_ca0.setClearColor(pass_ca0, .{red=0, green=0, blue=0, alpha=1});

    enc := cmd.renderCommandEncoderWithDescriptor(cmd, pass);
    assert(enc != null);
    enc.setRenderPipelineState(enc, pso);
    enc.setCullMode(enc, .None);
    enc.setViewport(enc, .{originX=0, originY=0, width=64, height=64, znear=0, zfar=1});
    enc.setScissorRect(enc, .{x=0, y=0, width=64, height=64});

    // Argument table with bindless texture array at id(0)
    t_desc := objc_new(MTL4ArgumentTableDescriptor);
    defer release(t_desc);
    t_desc.setMaxBufferBindCount(t_desc, 2);
    t_desc.setMaxTextureBindCount(t_desc, 8);
    t_desc.setMaxSamplerStateBindCount(t_desc, 1);
    t_desc.setInitializeBindings(t_desc, YES);
    t_desc.setSupportAttributeStrides(t_desc, NO);
    table := device.newArgumentTableWithDescriptor(device, t_desc, *err);
    check_error(err, "newArgumentTableWithDescriptor");
    assert(table != null);
    defer release(table);

    dummy := device.newBufferWithLength(device, 256, cast(MTLResourceOptions) MTLResource.StorageModeShared);
    assert(dummy != null);
    defer release(dummy);
    rs.addAllocation(rs, cast(*MTLAllocation) dummy);
    table.setAddress(table, dummy.gpuAddress(dummy), 0);

    // Bind texture at index 1
    tex_id := tex_pool.setTextureView(tex_pool, src_tex, 1);
    table.setTexture(table, tex_id, 1);

    enc.setArgumentTable(enc, table, cast(MTLRenderStages) MTLRenderStage.Fragment);
    enc.drawPrimitives(enc, .Triangle, 0, 3, 1);
    enc.endEncoding(enc);

    cmd.endCommandBuffer(cmd);
    q.commit(q, *cmd, 1);

    evt := device.newSharedEvent(device);
    assert(evt != null);
    defer release(evt);
    q.signalEvent(q, evt, 1);
    evt.waitUntilSignaledValue(evt, 1, milliseconds=0xFFFF_FFFF_FFFF_FFFF);

    pixels : [64 * 64 * 4] u8;
    out_region := MTLRegion.{ origin = .{x = 0, y = 0, z = 0}, size = .{width = 64, height = 64, depth = 1} };
    rt_tex.getBytes(rt_tex, xx *pixels[0], 64 * 4, out_region, 0);

    mid := (32 * 64 + 32) * 4;
    log("NATIVE_MTL4_BINDLESS_PIXEL bgra=(%, %, %, %)", pixels[mid + 0], pixels[mid + 1], pixels[mid + 2], pixels[mid + 3]);
}
