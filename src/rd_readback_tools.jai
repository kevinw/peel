#load "framebuffer_tools.jai";

RD_Framebuffer_Stats :: FB_Framebuffer_Stats;

rd_collect_swapchain_framebuffer_stats :: (view: Gpu_Texture_View) -> (RD_Framebuffer_Stats, bool) {
    stats, ok := fb_collect_swapchain_framebuffer_stats(view);
    out: RD_Framebuffer_Stats = stats;
    return out, ok;
}

rd_validate_swapchain_readback_non_black :: (view: Gpu_Texture_View) -> bool {
    return fb_validate_swapchain_readback_non_black(view, backend_label = "rd_metal");
}
