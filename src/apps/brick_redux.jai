WRITE_SHADER_OUTPUT :: true;

/*
Brick Redux

Implementation plan, distilled from BRICKMAP.md:

Phase 0. Stable baseline
- Keep one analytic raymarched scene with a fly camera.
- Keep object authoring on the CPU with gizmos and mouse manipulation.
- Keep a CPU BVH over authored objects so selection, dirty-region logic, and later cache work all share one spatial structure.
- Keep a quarter-resolution render target by default, then blit to the swapchain.

Phase 1. Scene representation
- Generalize the object list from one sphere to a small ordered list of analytic SDF edits.
- Keep the analytic raymarcher as the reference renderer while brick caching is developed.
- Add explicit dirty bounds for object edits and camera-driven cache work.

Phase 2. Brick cache prototype
- Introduce one brick grid around the camera with a deterministic atlas layout first.
- Bake analytic SDF + albedo into a 3D atlas in compute.
- Render by sampling cached brick distances instead of evaluating the full analytic scene per step.

Phase 3. Sparse allocation
- Replace the deterministic atlas layout with a pointer grid and sparse brick allocation.
- Keep the CPU BVH responsible for identifying which bricks overlap authored edits.
- Add validation for pointer-grid ownership, atlas references, and published brick state.

Phase 4. Camera-centered clipmaps
- Extend the single brick grid into nested camera-centered clipmap levels.
- Rebuild conservatively first, then preserve overlap once the simpler path is stable.
- Keep the analytic renderer available as a correctness oracle while the cached renderer is iterated.

Phase 5. Fully GPU-driven updates
- Move dirty-brick discovery, classify, bake, and publish onto the GPU.
- Preserve the CPU BVH as the authoritative authoring/query structure until GPU-side change tracking is proven.
- Reintroduce incremental work limits only after correctness and visual stability are solid.
*/

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "../ui/manip.jai";

#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
SHR :: #import,file "../shader_hot_reload.jai";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
Input :: #import "Input";
#import "Math";
#import "Random";

REDUX_MAX_OBJECTS :: 32;
REDUX_PARAM_RING_SLOTS :: 8;
REDUX_RENDER_SCALE_DEFAULT :: 0.25;

Redux_Shape :: enum u32 {
    SPHERE;
    BOX;
    TORUS;
    TRIANGULAR_PRISM;
}

Redux_Op :: enum u32 {
    UNION;
    SUBTRACT;
    INTERSECT;
}

Redux_Edit :: struct {
    shape: Redux_Shape;
    op: Redux_Op;
    position: Vector3;
    radius: float;
    major_radius: float;
    half_extents: Vector3;
    blend: float;
    rotation: Quaternion;
    color: Vector4;
}

AABB :: struct {
    min: Vector3;
    max: Vector3;
}

Redux_BVH_Node :: struct {
    bounds: AABB;
    left: s32;
    right: s32;
    object_index: s32;
}

Redux_BVH :: struct {
    object_bounds: [REDUX_MAX_OBJECTS] AABB;
    build_indices: [REDUX_MAX_OBJECTS] s32;
    nodes: [REDUX_MAX_OBJECTS * 2] Redux_BVH_Node;
    object_count: s32;
    node_count: s32;
    root_node: s32;
    max_depth: s32;
    leaf_count: s32;
}

Redux_Params :: struct {
    resolution: Vector2;
    camera_fov_y: float;
    camera_tan_half_fov: float;
    time: float;

    camera_pos: Vector3;
    _cam_pad0: float;
    camera_forward: Vector3;
    _cam_pad1: float;
    camera_right: Vector3;
    _cam_pad2: float;
    camera_up: Vector3;
    _cam_pad3: float;

    object_count: u32;
    use_ground: u32;
    _pad0: u32;
    _pad1: u32;

    object_shape: [REDUX_MAX_OBJECTS] Redux_Shape;
    object_op: [REDUX_MAX_OBJECTS] Redux_Op;
    object_pos_radius: [REDUX_MAX_OBJECTS] Vector4;
    object_half_extents: [REDUX_MAX_OBJECTS] Vector4;
    object_major_blend: [REDUX_MAX_OBJECTS] Vector4;
    object_rotation: [REDUX_MAX_OBJECTS] Vector4;
    object_color: [REDUX_MAX_OBJECTS] Vector4;
}

Redux_Blit_Params :: struct {
    source_texture_index: u32;
    source_sampler_index: u32;
}

Redux_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Redux_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Redux_Fragment_In :: struct {
    uv: Vector2;
}

graphics_pipeline: Gpu_Pipeline;
blit_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
params_ring_cpu: *[REDUX_PARAM_RING_SLOTS] Redux_Params;
params_ring_gpu: Gpu_Ptr;
blit_params_ring_cpu: *[REDUX_PARAM_RING_SLOTS] Redux_Blit_Params;
blit_params_ring_gpu: Gpu_Ptr;
params_cpu: *Redux_Params;
params_gpu: Gpu_Ptr;
blit_params_cpu: *Redux_Blit_Params;
blit_params_gpu: Gpu_Ptr;

render_texture: Gpu_Texture;
render_view: Gpu_Texture_View;
render_sampler: Gpu_Sampler;
render_point_sampler: Gpu_Sampler;
render_width: s32;
render_height: s32;
render_scale: float = REDUX_RENDER_SCALE_DEFAULT;
blit_nearest := false;
use_ground := true;

camera: Editor_Camera = .{
    position = .{0.0, 1.35, 4.5},
    yaw = 0.0,
    pitch = -0.20,
    move_speed = 5.0,
    boost_multiplier = 2.2,
    mouse_sensitivity = 0.0060,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};

gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;
manip_ctx: Manip_Context;
redux_edits_cpu: [REDUX_MAX_OBJECTS] Redux_Edit;
redux_manip_objects: [REDUX_MAX_OBJECTS] Manip_Object;
redux_edit_count: s32;
redux_bvh: Redux_BVH;

ui_open := true;
left_was_down := false;
REDUX_RANDOM_SEED :: cast(u64) 0xB12C0DE5;

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, redux_vertex_main, redux_fragment_main);
    blit_source := cast([]u8) get_transpiled(.METAL, redux_blit_vertex_main, redux_blit_fragment_main);

    raster_desc: Gpu_Raster_Desc = .{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM},
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, redux_vertex_main, redux_fragment_main);
    blit_ok     := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *blit_pipeline, blit_source, raster_desc, .METAL, redux_blit_vertex_main, redux_blit_fragment_main);

    gpu_arena = gpu_make_arena(256 * 1024, label = "brick redux arena");
    params_ring_cpu, params_ring_gpu = gpu_arena_alloc(*gpu_arena, [REDUX_PARAM_RING_SLOTS] Redux_Params);
    blit_params_ring_cpu, blit_params_ring_gpu = gpu_arena_alloc(*gpu_arena, [REDUX_PARAM_RING_SLOTS] Redux_Blit_Params);

    params_cpu      = redux_params_ring_cpu_slot(params_ring_cpu, 0);
    params_gpu      = redux_params_ring_gpu_slot(params_ring_gpu, Redux_Params, 0);
    blit_params_cpu = redux_params_ring_cpu_slot(blit_params_ring_cpu, 0);
    blit_params_gpu = redux_params_ring_gpu_slot(blit_params_ring_gpu, Redux_Blit_Params, 0);

    for i: 0..REDUX_PARAM_RING_SLOTS-1 {
        params_ring_cpu.*[i] = .{};
        blit_params_ring_cpu.*[i] = .{};
    }

    render_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR, mag_filter = .LINEAR, mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
    });
    render_point_sampler = gpu_create_sampler(.{
        min_filter = .NEAREST, mag_filter = .NEAREST, mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
    });

    Gizmo.init(*gizmo_ctx);
    Gizmo_Render.init(*gizmo_render_ctx, max_lines = 65536);
    Gizmo_Render.bind_gizmo(*gizmo_render_ctx, *gizmo_ctx);
    random_seed(REDUX_RANDOM_SEED);
    redux_edit_count = 1;
    redux_edits_cpu[0] = .{
        shape = .SPHERE,
        op = .UNION,
        position = .{0.0, 0.0, 0.0},
        radius = 1.0,
        major_radius = 1.0,
        half_extents = .{1.0, 1.0, 1.0},
        blend = 0.0,
        rotation = .{w = 1.0},
        color = .{0.94, 0.52, 0.28, 1.0},
    };

    rebuild_bvh();
    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    if render_view != 0 gpu_free_texture_view(render_view);
    if render_texture != 0 gpu_free(render_texture);
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
} @on_unload

redux_ui :: () {
    using ImGui;

    SetNextWindowPos(.{20.0, 20.0}, .FirstUseEver);
    SetNextWindowSize(.{400.0, 240.0}, .FirstUseEver);
    if Begin("Brick Redux", *ui_open, flags = .NoCollapse) {
        Text("Plan-first reboot of brickmap.");
        Text("Camera: RMB look, WASDQE fly, Shift boost");
        Text("Gizmo: LMB select/drag, 1/2/3 mode, 4/5 space");
        Text("Objects: %", redux_edit_count);
        Text("BVH nodes/leaves/depth: % / % / %", redux_bvh.node_count, redux_bvh.leaf_count, redux_bvh.max_depth);
        SliderFloat("Render Scale", *render_scale, 0.25, 1.0);
        Checkbox("Nearest Blit", *blit_nearest);
        Checkbox("Ground Plane", *use_ground);

        selected := cast(s64) manip_ctx.selected_index;
        if selected >= 0 && selected < redux_edit_count {
            edit := redux_edit_for_index(cast(s32) selected);
            changed := false;
            changed |= DragFloat3("Position", cast(*[3]float) *edit.position.x, 0.01);
            Text("Shape: %", edit.shape);
            Text("Op: %", edit.op);
            changed |= DragFloat("Blend", *edit.blend, 0.01, 0.0, 1.0);
            if edit.shape == .SPHERE {
                changed |= DragFloat("Radius", *edit.radius, 0.01, 0.05, 10.0);
                edit.radius = max(edit.radius, 0.05);
            } else if edit.shape == .TORUS {
                changed |= DragFloat("Major Radius", *edit.major_radius, 0.01, 0.05, 10.0);
                changed |= DragFloat("Minor Radius", *edit.radius, 0.01, 0.03, 4.0);
                edit.major_radius = max(edit.major_radius, 0.05);
                edit.radius = max(edit.radius, 0.03);
            } else {
                changed |= DragFloat3("Half Extents", cast(*[3]float) *edit.half_extents.x, 0.01);
                edit.half_extents.x = max(edit.half_extents.x, 0.05);
                edit.half_extents.y = max(edit.half_extents.y, 0.05);
                edit.half_extents.z = max(edit.half_extents.z, 0.05);
            }
            if changed {
                rebuild_bvh();
            }
        }
    }
    End();
} @on_ui

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    frame_number := cast(s64) gpu_submission_frame_index();
    params_cpu = redux_params_ring_cpu_slot(params_ring_cpu, frame_number);
    params_gpu = redux_params_ring_gpu_slot(params_ring_gpu, Redux_Params, frame_number);
    blit_params_cpu = redux_params_ring_cpu_slot(blit_params_ring_cpu, frame_number);
    blit_params_gpu = redux_params_ring_gpu_slot(blit_params_ring_gpu, Redux_Blit_Params, frame_number);
    params_cpu.* = .{};
    blit_params_cpu.* = .{};

    for Input.events_this_frame {
        using it;
        if type != .KEYBOARD || !key_pressed continue;
        if key_code == {
        case #char "1"; manip_ctx.mode = .TRANSLATE;
        case #char "2"; manip_ctx.mode = .ROTATE;
        case #char "3"; manip_ctx.mode = .SCALE;
        case #char "4"; manip_ctx.space = .WORLD;
        case #char "5"; manip_ctx.space = .LOCAL;
        }
    }

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w <= 0 || win_h <= 0 return;
    viewport := Vector2.{cast(float) win_w, cast(float) win_h};
    aspect := viewport.x / max(viewport.y, 1.0);

    mx, my, mouse_ok := get_mouse_pointer_position(cast(Window_Type) window, true);
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    left_pressed := left_down && !left_was_down;
    left_released := !left_down && left_was_down;
    left_was_down = left_down;

    io := ImGui.GetIO();
    _ = editor_camera_update(*camera, editor_dt, mx, my, mouse_ok,
        allow_move = !io.WantCaptureKeyboard,
        allow_look = right_down && !io.WantCaptureMouse);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(*camera, *cam_forward, *cam_right, *cam_up);
    view := editor_camera_make_view(*camera);
    proj := make_projection_matrix(PI / 3.0, aspect, 0.05, 120.0);
    Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, proj * view);
    Gizmo.begin_frame(*gizmo_ctx);
    Gizmo.draw_grid_xz(*gizmo_ctx, center = .{0.0, 0.0, 0.0}, half_extent = 10.0, spacing = 1.0, major_every = 5, line_thickness = 1.0);
    build_manip_objects_from_edits();

    frame := Manip_Frame_Input.{
        viewport = viewport,
        camera_pos     = camera.position,
        camera_forward = cam_forward,
        camera_right   = cam_right,
        camera_up      = cam_up,
        fov_y = PI / 3.0,
        mouse_pos = .{cast(float) mx, cast(float) my},
        mouse_valid = mouse_ok,
        mouse_down = left_down,
        mouse_pressed = left_pressed,
        mouse_released = left_released,
        block_mouse = io.WantCaptureMouse || right_down,
    };

    manip_slice: []Manip_Object = .{redux_edit_count, cast(*Manip_Object) *redux_manip_objects};
    manip_result := manip_update(*manip_ctx, *gizmo_ctx, manip_slice, frame);
    if manip_result.changed {
        apply_manip_objects_to_edits(manip_slice);
        rebuild_bvh();
    }

    if left_pressed && !right_down && !io.WantCaptureMouse && !manip_result.captured_mouse {
        ray_origin, ray_dir, ray_ok := mouse_world_ray(viewport, tan(params_cpu.camera_fov_y * 0.5), camera.position, cam_forward, cam_right, cam_up, .{cast(float) mx, cast(float) my}, mouse_ok);
        if ray_ok {
            _, hit_pos, hit_ok := ray_ground_hit(ray_origin, ray_dir);
            if hit_ok {
                spawn_random_edit(hit_pos);
                rebuild_bvh();
            }
        }
    }

    if !ensure_render_target(win_w, win_h) return;

    params_cpu.resolution = .{cast(float) render_width, cast(float) render_height};
    params_cpu.camera_fov_y = PI / 3.0;
    params_cpu.camera_tan_half_fov = tan(params_cpu.camera_fov_y * 0.5);
    params_cpu.time = cast(float) frame_count * (1.0 / 60.0);
    params_cpu.camera_pos = camera.position;
    params_cpu.camera_forward = cam_forward;
    params_cpu.camera_right = cam_right;
    params_cpu.camera_up = cam_up;
    params_cpu.use_ground = ifx use_ground then cast(u32) 1 else cast(u32) 0;
    params_cpu.object_count = cast(u32) redux_edit_count;
    fill_shader_params_from_scene();

    blit_params_cpu.source_texture_index = cast(u32) render_view - 1;
    blit_params_cpu.source_sampler_index = cast(u32) blit_sampler_handle() - 1;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            color_targets = .[
                .{
                    view = render_view,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.035, 0.040, 0.052, 1.0],
                },
            ],
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        result = gpu_set_pipeline(cmd_buff, graphics_pipeline);
        assert(result == .SUCCESS, tprint("Brick Redux graphics pipeline bind failed: %", result));
        result = gpu_draw_instanced_direct(cmd_buff, params_gpu, 3, 1);
        assert(result == .SUCCESS, tprint("Brick Redux fullscreen draw failed: %", result));
    }

    {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            color_targets = .[
                .{
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.03, 0.035, 0.05, 1.0],
                },
            ],
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, blit_pipeline);
        gpu_draw_instanced_direct(cmd_buff, blit_params_gpu, 3, 1);
        Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .NONE);
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

scaled_dim :: (dim: s32, scale: float) -> s32 {
    rounded := cast(s32) floor(cast(float) dim * clamp(scale, 0.25, 1.0) + 0.5);
    return max(rounded, 1);
}

blit_sampler_handle :: () -> Gpu_Sampler {
    if blit_nearest return render_point_sampler;
    return render_sampler;
}

ensure_render_target :: (win_w: s32, win_h: s32) -> bool {
    target_w := scaled_dim(win_w, render_scale);
    target_h := scaled_dim(win_h, render_scale);
    if target_w == render_width && target_h == render_height && render_view != 0 return true;

    if render_view != 0 {
        gpu_wait_idle();
        gpu_free_texture_view(render_view);
        render_view = 0;
    }
    if render_texture != 0 {
        gpu_free(render_texture);
        render_texture = 0;
    }

    create_result: Gpu_Result;
    create_result, render_texture = gpu_create_texture(.{
        type = ._2D,
        dimensions = .[cast(u32) target_w, cast(u32) target_h, 1],
        format = .B8G8R8A8_UNORM,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    if create_result != .SUCCESS || render_texture == 0 {
        render_width = 0;
        render_height = 0;
        return false;
    }

    render_view = gpu_texture_view(render_texture);
    if render_view == 0 {
        gpu_free(render_texture);
        render_texture = 0;
        render_width = 0;
        render_height = 0;
        return false;
    }

    render_width = target_w;
    render_height = target_h;
    gpu_commit_residency();
    return true;
}

build_manip_objects_from_edits :: () {
    count := min(redux_edit_count, REDUX_MAX_OBJECTS);
    for i: 0..count-1 {
        edit := redux_edits_cpu[i];
        manip_shape := ifx edit.shape == .SPHERE then Manip_Object_Shape.SPHERE else Manip_Object_Shape.BOX;
        half := edit.half_extents;
        if edit.shape == .SPHERE {
            half = .{edit.radius, edit.radius, edit.radius};
        }
        redux_manip_objects[i] = .{
            name = tprint("Edit %", i),
            shape = manip_shape,
            position = edit.position,
            rotation = edit.rotation,
            scale = .{1.0, 1.0, 1.0},
            half_extents = half,
            color = edit.color,
        };
    }
}

apply_manip_objects_to_edits :: (objects: []Manip_Object) {
    count := min(cast(s32) objects.count, redux_edit_count);
    for i: 0..count-1 {
        obj := objects[i];
        edit := redux_edits_cpu[i];
        half := Vector3.{
            max(obj.half_extents.x * obj.scale.x, 0.05),
            max(obj.half_extents.y * obj.scale.y, 0.05),
            max(obj.half_extents.z * obj.scale.z, 0.05),
        };
        edit.position = obj.position;
        edit.rotation = obj.rotation;
        edit.color = obj.color;

        if edit.shape == {
        case .SPHERE;
            r := max(max(half.x, half.y), half.z);
            edit.radius = max(r, 0.05);
            edit.major_radius = edit.radius;
            edit.half_extents = .{edit.radius, edit.radius, edit.radius};
        case .TORUS;
            edit.major_radius = max(max(half.x, half.z), 0.08);
            edit.radius = max(half.y, 0.04);
            ring := edit.major_radius + edit.radius;
            edit.half_extents = .{ring, edit.radius, ring};
        case .BOX;
            edit.half_extents = half;
            edit.radius = max(max(half.x, half.y), half.z);
            edit.major_radius = edit.radius;
        case .TRIANGULAR_PRISM;
            edit.half_extents = half;
            edit.radius = max(half.x, half.z);
            edit.major_radius = edit.radius;
        }

        redux_edits_cpu[i] = edit;
    }
}

fill_shader_params_from_scene :: () {
    count := min(redux_edit_count, REDUX_MAX_OBJECTS);
    params_cpu.object_count = cast(u32) count;
    for i: 0..count-1 {
        obj := redux_edits_cpu[i];
        params_cpu.object_shape[i] = obj.shape;
        params_cpu.object_op[i] = obj.op;
        params_cpu.object_pos_radius[i] = .{obj.position.x, obj.position.y, obj.position.z, obj.radius};
        params_cpu.object_half_extents[i] = .{obj.half_extents.x, obj.half_extents.y, obj.half_extents.z, 0.0};
        params_cpu.object_major_blend[i] = .{obj.major_radius, obj.blend, 0.0, 0.0};
        params_cpu.object_rotation[i] = .{obj.rotation.x, obj.rotation.y, obj.rotation.z, obj.rotation.w};
        params_cpu.object_color[i] = obj.color;
    }
}

object_bounds :: (obj: Redux_Edit) -> AABB {
    extent := Vector3.{obj.radius, obj.radius, obj.radius};
    if obj.shape == {
    case .BOX;
        extent = .{length(obj.half_extents), length(obj.half_extents), length(obj.half_extents)};
    case .TRIANGULAR_PRISM;
        extent = obj.half_extents;
    case .TORUS;
        ring := obj.major_radius + obj.radius;
        extent = .{ring, obj.radius, ring};
    case .SPHERE;
        extent = .{obj.radius, obj.radius, obj.radius};
    }
    margin := obj.blend + 0.05;
    extent += .{margin, margin, margin};
    return .{
        min = obj.position - extent,
        max = obj.position + extent,
    };
}

rebuild_bvh :: () {
    count := min(redux_edit_count, REDUX_MAX_OBJECTS);
    redux_bvh.object_count = count;
    redux_bvh.node_count = 0;
    redux_bvh.root_node = -1;
    redux_bvh.max_depth = 0;
    redux_bvh.leaf_count = 0;

    for i: 0..count-1 {
        redux_bvh.object_bounds[i] = object_bounds(redux_edits_cpu[i]);
        redux_bvh.build_indices[i] = i;
    }

    if count > 0 {
        redux_bvh.root_node = bvh_build_range(0, count, 0);
    }
}

redux_edit_for_index :: (index: s32) -> *Redux_Edit {
    return cast(*Redux_Edit) redux_edits_cpu.data + index;
}

random_color :: () -> Vector4 {
    palette: [8]Vector3 = .[
        .{0.94, 0.52, 0.28},
        .{0.31, 0.70, 0.93},
        .{0.48, 0.83, 0.43},
        .{0.92, 0.77, 0.30},
        .{0.84, 0.42, 0.79},
        .{0.72, 0.63, 0.56},
        .{0.92, 0.42, 0.36},
        .{0.42, 0.85, 0.78},
    ];
    idx := clamp(cast(s32) floor(random_get_zero_to_one() * cast(float) palette.count), 0, palette.count - 1);
    c := palette[idx];
    return .{c.x, c.y, c.z, 1.0};
}

spawn_random_edit :: (position: Vector3) {
    if redux_edit_count >= REDUX_MAX_OBJECTS return;

    shape_idx := clamp(cast(s32) floor(random_get_zero_to_one() * 4.0), 0, 3);
    shape: Redux_Shape;
    if shape_idx == {
    case 0; shape = .SPHERE;
    case 1; shape = .BOX;
    case 2; shape = .TORUS;
    case 3; shape = .TRIANGULAR_PRISM;
    }

    op_roll := random_get_zero_to_one();
    op: Redux_Op = .UNION;
    /*
    if op_roll > 0.85 {
        op = .SUBTRACT;
    } else if op_roll > 0.70 {
        op = .INTERSECT;
    }
    */

    size := 0.25 + random_get_zero_to_one() * 0.55;
    height := 0.20 + random_get_zero_to_one() * 0.45;
    yaw := random_get_zero_to_one() * PI * 2.0;
    q := quat_from_euler_xyz(.{0.0, yaw, 0.0});
    blend := ifx random_get_zero_to_one() > 0.55 then random_get_zero_to_one() * 0.18 else 0.0;

    edit := Redux_Edit.{
        shape = shape,
        op = op,
        position = position + .{0.0, max(height, size), 0.0},
        radius = size,
        major_radius = size,
        half_extents = .{size, height, size},
        blend = blend,
        rotation = q,
        color = random_color(),
    };

    manip_shape := Manip_Object_Shape.BOX;
    manip_half := edit.half_extents;
    if shape == {
    case .SPHERE;
        manip_shape = .SPHERE;
        manip_half = .{size, size, size};
        edit.half_extents = manip_half;
        edit.radius = size;
        edit.major_radius = size;
    case .TORUS;
        edit.radius = max(0.08, size * 0.35);
        edit.major_radius = max(0.14, size * 0.95);
        ring := edit.major_radius + edit.radius;
        edit.half_extents = .{ring, edit.radius, ring};
        manip_half = edit.half_extents;
    case .BOX;
        manip_half = edit.half_extents;
    case .TRIANGULAR_PRISM;
        manip_half = edit.half_extents;
    }

    index := redux_edit_count;
    redux_edits_cpu[index] = edit;
    _ = manip_shape;
    _ = manip_half;
    redux_edit_count += 1;
    manip_ctx.selected_index = redux_edit_count - 1;
}

mouse_world_ray :: (resolution: Vector2, tan_half_fov: float,
    camera_pos: Vector3, camera_forward: Vector3, camera_right: Vector3, camera_up: Vector3,
    mouse_pos: Vector2, mouse_valid: bool) -> (origin: Vector3, dir: Vector3, ok: bool) {
    if !mouse_valid return .{}, .{}, false;
    if resolution.x <= 1.0 || resolution.y <= 1.0 return .{}, .{}, false;

    uv := Vector2.{(mouse_pos.x + 0.5) / resolution.x, (mouse_pos.y + 0.5) / resolution.y};
    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    p.x *= resolution.x / max(resolution.y, 1.0);
    rd_un := camera_forward + camera_right * (p.x * tan_half_fov) + camera_up * (p.y * tan_half_fov);
    rd := safe_normalize(rd_un);
    return camera_pos, rd, true;
}

ray_ground_hit :: (ray_origin: Vector3, ray_dir: Vector3) -> (t: float, pos: Vector3, ok: bool) {
    if abs(ray_dir.y) <= 0.000001 return 0.0, .{}, false;
    t := -ray_origin.y / ray_dir.y;
    if t <= 0.0 return t, .{}, false;
    return t, ray_origin + ray_dir * t, true;
}

redux_params_ring_index :: (frame_number: s64 = -1) -> s64 {
    if frame_number < 0 frame_number = cast(s64) gpu_submission_frame_index();
    idx := frame_number % REDUX_PARAM_RING_SLOTS;
    if idx < 0 idx += REDUX_PARAM_RING_SLOTS;
    return idx;
}

redux_params_ring_cpu_slot :: (ring: *[REDUX_PARAM_RING_SLOTS] $T, frame_number: s64 = -1) -> *T #expand {
    idx := redux_params_ring_index(frame_number);
    return cast(*T) ring + idx;
}

redux_params_ring_gpu_slot :: (ring_base_gpu: Gpu_Ptr, $T: Type, frame_number: s64 = -1) -> Gpu_Ptr #expand {
    idx := redux_params_ring_index(frame_number);
    return ring_base_gpu + (idx * size_of(T)).(Gpu_Ptr);
}

bvh_alloc_node :: () -> s32 {
    assert(redux_bvh.node_count < redux_bvh.nodes.count, "Brick Redux BVH node overflow.");
    out := redux_bvh.node_count;
    redux_bvh.node_count += 1;
    return out;
}

bvh_axis_value :: (v: Vector3, axis: s32) -> float {
    if axis == {
    case 0; return v.x;
    case 1; return v.y;
    case 2; return v.z;
    }
    return v.x;
}

aabb_center :: (b: AABB) -> Vector3 {
    return (b.min + b.max) * 0.5;
}

aabb_union :: (a: AABB, b: AABB) -> AABB {
    return .{
        min = .{min(a.min.x, b.min.x), min(a.min.y, b.min.y), min(a.min.z, b.min.z)},
        max = .{max(a.max.x, b.max.x), max(a.max.y, b.max.y), max(a.max.z, b.max.z)},
    };
}

bvh_build_range :: (start: s32, end: s32, depth: s32) -> s32 {
    node_index := bvh_alloc_node();
    count := end - start;
    assert(count > 0, "Invalid Brick Redux BVH build range.");
    if depth > redux_bvh.max_depth redux_bvh.max_depth = depth;

    bounds := redux_bvh.object_bounds[redux_bvh.build_indices[start]];
    centroid_min := aabb_center(bounds);
    centroid_max := centroid_min;
    for i: start+1..end-1 {
        b := redux_bvh.object_bounds[redux_bvh.build_indices[i]];
        bounds = aabb_union(bounds, b);
        c := aabb_center(b);
        centroid_min.x = min(centroid_min.x, c.x);
        centroid_min.y = min(centroid_min.y, c.y);
        centroid_min.z = min(centroid_min.z, c.z);
        centroid_max.x = max(centroid_max.x, c.x);
        centroid_max.y = max(centroid_max.y, c.y);
        centroid_max.z = max(centroid_max.z, c.z);
    }

    if count == 1 {
        redux_bvh.leaf_count += 1;
        redux_bvh.nodes[node_index] = .{
            bounds = bounds,
            left = -1,
            right = -1,
            object_index = redux_bvh.build_indices[start],
        };
        return node_index;
    }

    extent := centroid_max - centroid_min;
    axis: s32 = 0;
    if extent.y > extent.x axis = 1;
    if extent.z > bvh_axis_value(extent, axis) axis = 2;
    split_value := (bvh_axis_value(centroid_min, axis) + bvh_axis_value(centroid_max, axis)) * 0.5;

    left_i := start;
    right_i := end - 1;
    while left_i <= right_i {
        idx := redux_bvh.build_indices[left_i];
        c := aabb_center(redux_bvh.object_bounds[idx]);
        if bvh_axis_value(c, axis) < split_value {
            left_i += 1;
            continue;
        }

        tmp := redux_bvh.build_indices[left_i];
        redux_bvh.build_indices[left_i] = redux_bvh.build_indices[right_i];
        redux_bvh.build_indices[right_i] = tmp;
        right_i -= 1;
    }

    split := left_i;
    if split <= start || split >= end split = start + count / 2;

    left := bvh_build_range(start, split, depth + 1);
    right := bvh_build_range(split, end, depth + 1);

    redux_bvh.nodes[node_index] = .{
        bounds = bounds,
        left = left,
        right = right,
        object_index = -1,
    };
    return node_index;
}

#scope_export

redux_vertex_main :: (using in: Redux_Vertex_In) -> Redux_Vertex_Out {
    using out: Redux_Vertex_Out;

    pos: Vector2;
    if vertex_id == 0 {
        pos = .{-1.0, -1.0};
    } else if vertex_id == 1 {
        pos = .{3.0, -1.0};
    } else {
        pos = .{-1.0, 3.0};
    }

    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5};
    return out;
} @vertex_shader

redux_blit_vertex_main :: (using in: Redux_Vertex_In) -> Redux_Vertex_Out {
    using out: Redux_Vertex_Out;

    pos: Vector2;
    if vertex_id == 0 {
        pos = .{-1.0, -1.0};
    } else if vertex_id == 1 {
        pos = .{3.0, -1.0};
    } else {
        pos = .{-1.0, 3.0};
    }

    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5};
    return out;
} @vertex_shader

redux_blit_fragment_main :: (using in: Redux_Fragment_In, params: *Redux_Blit_Params) -> struct { out_color: Vector4; } {
    c := sample_2d(params.source_texture_index, params.source_sampler_index, .{uv.x, 1.0 - uv.y});
    return .{out_color = c};
} @fragment_shader

safe_normalize :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 <= 0.000001 return .{0.0, 1.0, 0.0};
    return v * (1.0 / sqrt(len2));
}

rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    q_xyz := Vector3.{q.x, q.y, q.z};
    t := cross(q_xyz, v) * 2.0;
    return v + t * q.w + cross(q_xyz, t);
}

inv_rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    qc := Vector4.{-q.x, -q.y, -q.z, q.w};
    return rotate_quat(v, qc);
}

sdf_sphere :: (p: Vector3, radius: float) -> float {
    return sqrt(dot(p, p)) - radius;
}

sdf_box :: (p: Vector3, b: Vector3) -> float {
    q := Vector3.{abs(p.x) - b.x, abs(p.y) - b.y, abs(p.z) - b.z};
    outside := Vector3.{max(q.x, 0.0), max(q.y, 0.0), max(q.z, 0.0)};
    outside_len := sqrt(dot(outside, outside));
    inside := min(max(q.x, max(q.y, q.z)), 0.0);
    return outside_len + inside;
}

sd_torus :: (p: Vector3, major_radius: float, minor_radius: float) -> float {
    qx := sqrt(p.x * p.x + p.z * p.z) - major_radius;
    return sqrt(qx * qx + p.y * p.y) - minor_radius;
}

sd_triangular_prism :: (p: Vector3, half_extents: Vector3) -> float {
    q := Vector3.{abs(p.x), abs(p.y), abs(p.z)};
    tri_2d := max(q.x * 0.8660254 + p.z * 0.5, -p.z) - half_extents.x;
    return max(tri_2d, q.y - half_extents.y);
}

smooth_min :: (a: float, b: float, k: float) -> float {
    if k <= 0.00001 return min(a, b);
    h := clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

smooth_max :: (a: float, b: float, k: float) -> float {
    if k <= 0.00001 return max(a, b);
    h := clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return lerp(b, a, h) + k * h * (1.0 - h);
}

eval_scene_sdf_albedo :: (params: *Redux_Params, p: Vector3) -> Vector4 {
    d := cast(float) 100000.0;
    albedo := Vector3.{0.62, 0.68, 0.78};

    count := cast(s32) params.object_count;
    for i: 0..count-1 {
        pos_radius := params.object_pos_radius[i];
        local := p - Vector3.{pos_radius.x, pos_radius.y, pos_radius.z};
        rot := params.object_rotation[i];
        local = inv_rotate_quat(local, rot);
        major_blend := params.object_major_blend[i];
        half_ext := params.object_half_extents[i];

        sd: float;
        if #complete params.object_shape[i] == {
        case .SPHERE;
            sd = sdf_sphere(local, pos_radius.w);
        case .BOX;
            sd = sdf_box(local, .{half_ext.x, half_ext.y, half_ext.z});
        case .TORUS;
            sd = sd_torus(local, major_blend.x, pos_radius.w);
        case .TRIANGULAR_PRISM;
            sd = sd_triangular_prism(local, .{half_ext.x, half_ext.y, half_ext.z});
        }

        color := params.object_color[i];
        edit_albedo := Vector3.{color.x, color.y, color.z};
        blend := major_blend.y;

        if #complete params.object_op[i] == {
        case .UNION;
            if blend > 0.00001 {
                h := clamp(0.5 + 0.5 * (sd - d) / blend, 0.0, 1.0);
                d = smooth_min(d, sd, blend);
                albedo = .{
                    lerp(edit_albedo.x, albedo.x, h),
                    lerp(edit_albedo.y, albedo.y, h),
                    lerp(edit_albedo.z, albedo.z, h),
                };
            } else if sd < d {
                d = sd;
                albedo = edit_albedo;
            }
        case .SUBTRACT;
            sub_d := -sd;
            if blend > 0.00001 {
                h := clamp(0.5 + 0.5 * (d - sub_d) / blend, 0.0, 1.0);
                d = smooth_max(d, sub_d, blend);
                albedo = .{
                    lerp(edit_albedo.x, albedo.x, h),
                    lerp(edit_albedo.y, albedo.y, h),
                    lerp(edit_albedo.z, albedo.z, h),
                };
            } else if sub_d > d {
                d = sub_d;
                albedo = edit_albedo;
            }
        case .INTERSECT;
            if blend > 0.00001 {
                h := clamp(0.5 + 0.5 * (d - sd) / blend, 0.0, 1.0);
                d = smooth_max(d, sd, blend);
                albedo = .{
                    lerp(edit_albedo.x, albedo.x, h),
                    lerp(edit_albedo.y, albedo.y, h),
                    lerp(edit_albedo.z, albedo.z, h),
                };
            } else if sd > d {
                d = sd;
                albedo = edit_albedo;
            }
        }
    }

    if params.use_ground != 0 {
        ground := p.y;
        if ground < d {
            d = ground;
            albedo = .{0.42, 0.48, 0.30};
        }
    }

    return .{d, albedo.x, albedo.y, albedo.z};
}

scene_normal :: (params: *Redux_Params, p: Vector3) -> Vector3 {
    eps := 0.01;
    dpx := eval_scene_sdf_albedo(params, p + .{eps, 0.0, 0.0}).x;
    dnx := eval_scene_sdf_albedo(params, p - .{eps, 0.0, 0.0}).x;
    dpy := eval_scene_sdf_albedo(params, p + .{0.0, eps, 0.0}).x;
    dny := eval_scene_sdf_albedo(params, p - .{0.0, eps, 0.0}).x;
    dpz := eval_scene_sdf_albedo(params, p + .{0.0, 0.0, eps}).x;
    dnz := eval_scene_sdf_albedo(params, p - .{0.0, 0.0, eps}).x;
    return safe_normalize(.{dpx - dnx, dpy - dny, dpz - dnz});
}

redux_fragment_main :: (using in: Redux_Fragment_In, params: *Redux_Params) -> struct { out_color: Vector4; } {
    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    aspect := params.resolution.x / max(params.resolution.y, 1.0);
    p.x *= aspect;

    ro := params.camera_pos;
    rd := safe_normalize(params.camera_forward + params.camera_right * (p.x * params.camera_tan_half_fov) + params.camera_up * (p.y * params.camera_tan_half_fov));

    t := 0.0;
    hit := false;
    hit_albedo := Vector3.{0.0, 0.0, 0.0};
    for 0..160 {
        pos := ro + rd * t;
        d_color := eval_scene_sdf_albedo(params, pos);
        d := d_color.x;
        if d < 0.0015 {
            hit = true;
            hit_albedo = .{d_color.y, d_color.z, d_color.w};
            break;
        }
        t += max(d * 0.85, 0.0025);
        if t > 120.0 break;
    }

    sky_a := Vector3.{0.10, 0.12, 0.16};
    sky_b := Vector3.{0.58, 0.71, 0.90};
    sky_t := clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    color := Vector3.{
        lerp(sky_a.x, sky_b.x, sky_t),
        lerp(sky_a.y, sky_b.y, sky_t),
        lerp(sky_a.z, sky_b.z, sky_t),
    };

    if hit {
        pos := ro + rd * t;
        n := scene_normal(params, pos);
        sun := safe_normalize(.{0.55, 0.72, 0.38});
        ndl := max(dot(n, sun), 0.0);
        hemi := 0.5 + 0.5 * n.y;
        color = hit_albedo * (0.15 + 0.75 * ndl + 0.20 * hemi);
    }

    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader
