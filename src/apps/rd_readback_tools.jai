#load "framebuffer_tools.jai";

RD_Framebuffer_Stats :: FB_Framebuffer_Stats;

rd_parse_env_int :: (name: string, default: s64 = 0) -> s64 {
    return fb_parse_env_int(name, default);
}

rd_collect_swapchain_framebuffer_stats :: (view: Gpu_Texture_View) -> (RD_Framebuffer_Stats, bool) {
    return fb_collect_swapchain_framebuffer_stats(view);
}

rd_validate_swapchain_readback_non_black :: (view: Gpu_Texture_View) -> bool {
    return fb_validate_swapchain_readback_non_black(view, backend_label = "rd_metal");
}

rd_dump_swapchain_thumbnail_ppm :: (view: Gpu_Texture_View, output_path: string, thumb_width: u32 = 96, thumb_height: u32 = 96) -> bool {
    return fb_dump_swapchain_thumbnail_ppm(view, output_path, thumb_width, thumb_height);
}
