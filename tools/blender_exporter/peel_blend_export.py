import os
import pathlib
import struct
import tempfile
import traceback
import math

import bpy
import mathutils


MAGIC = b"PEBLEND1"
VERSION = 1
DEFAULT_COLOR = (0.8, 0.8, 0.8, 1.0)
BLENDER_TO_PEEL_ROOT_ROTATION = mathutils.Euler((-math.pi * 0.5, math.pi, 0.0), "XYZ").to_quaternion()


def default_output_path(blend_path: str) -> str:
    return blend_path + ".peelscene"


def _safe_pointer(value) -> int:
    if value is None:
        return 0
    try:
        return value.as_pointer()
    except Exception:
        return 0


def _material_key(material) -> tuple:
    if material is None:
        return ("__default__", DEFAULT_COLOR)
    return ("material", _safe_pointer(material), tuple(float(x) for x in material.diffuse_color))


def _material_color(material) -> tuple[float, float, float, float]:
    if material is None:
        return DEFAULT_COLOR
    rgba = tuple(float(x) for x in material.diffuse_color)
    if len(rgba) == 4:
        return rgba
    return DEFAULT_COLOR


def _mesh_key(instance) -> tuple:
    obj = instance.object
    obj_original = getattr(obj, "original", obj)
    data_original = getattr(getattr(obj_original, "data", None), "original", getattr(obj_original, "data", None))
    data_ptr = _safe_pointer(data_original)
    object_ptr = _safe_pointer(obj_original)
    modifier_count = len(getattr(obj_original, "modifiers", ()))
    if data_ptr and modifier_count == 0:
        return ("data", data_ptr)
    return ("object", object_ptr)


def _matrix_trs(matrix) -> tuple[tuple[float, float, float], tuple[float, float, float, float], tuple[float, float, float]]:
    loc, rot, scale = matrix.decompose()
    rot_quat = rot.normalized()
    return (
        (float(loc.x), float(loc.y), float(loc.z)),
        (float(rot_quat.x), float(rot_quat.y), float(rot_quat.z), float(rot_quat.w)),
        (float(scale.x), float(scale.y), float(scale.z)),
    )


def _flush_edit_mode_meshes() -> None:
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        if obj.mode != "EDIT":
            continue
        try:
            obj.update_from_editmode()
        except Exception:
            pass


def _build_mesh_payload(scene_state, obj_eval, depsgraph) -> list[int]:
    mesh = obj_eval.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    if mesh is None:
        return []

    try:
        mesh.calc_loop_triangles()
        uv_layer = mesh.uv_layers.active.data if mesh.uv_layers.active else None
        loop_normals = hasattr(mesh.loops[0], "normal") if len(mesh.loops) > 0 else False

        material_groups: dict[int, list] = {}
        for tri in mesh.loop_triangles:
            material_groups.setdefault(int(tri.material_index), []).append(tri)

        exported_mesh_indices: list[int] = []
        for material_slot_index, triangles in material_groups.items():
            material = None
            if material_slot_index < len(obj_eval.material_slots):
                material = obj_eval.material_slots[material_slot_index].material

            material_key = _material_key(material)
            material_index = scene_state["material_indices"].get(material_key)
            if material_index is None:
                material_index = len(scene_state["materials"])
                scene_state["material_indices"][material_key] = material_index
                scene_state["materials"].append({
                    "name": material.name if material else "__default__",
                    "color": _material_color(material),
                })

            base_vertex = len(scene_state["vertices"])
            first_index = len(scene_state["indices"])
            vertex_map: dict[tuple, int] = {}

            for tri in triangles:
                for corner, loop_index in enumerate(tri.loops):
                    vertex_index = tri.vertices[corner]
                    vertex = mesh.vertices[vertex_index]
                    normal = vertex.normal
                    if loop_normals:
                        normal = mesh.loops[loop_index].normal

                    uv = (0.0, 0.0)
                    if uv_layer is not None:
                        uv_value = uv_layer[loop_index].uv
                        uv = (float(uv_value.x), float(uv_value.y))

                    key = (
                        round(float(vertex.co.x), 6),
                        round(float(vertex.co.y), 6),
                        round(float(vertex.co.z), 6),
                        round(float(normal.x), 6),
                        round(float(normal.y), 6),
                        round(float(normal.z), 6),
                        round(uv[0], 6),
                        round(uv[1], 6),
                    )
                    local_vertex_index = vertex_map.get(key)
                    if local_vertex_index is None:
                        local_vertex_index = len(scene_state["vertices"]) - base_vertex
                        vertex_map[key] = local_vertex_index
                        scene_state["vertices"].append({
                            "position": (float(vertex.co.x), float(vertex.co.y), float(vertex.co.z)),
                            "normal": (float(normal.x), float(normal.y), float(normal.z)),
                            "uv": uv,
                        })

                    scene_state["indices"].append(base_vertex + local_vertex_index)

            index_count = len(scene_state["indices"]) - first_index
            if index_count == 0:
                continue

            mesh_index = len(scene_state["meshes"])
            scene_state["meshes"].append({
                "base_vertex": base_vertex,
                "vertex_count": len(scene_state["vertices"]) - base_vertex,
                "first_index": first_index,
                "index_count": index_count,
                "material_index": material_index,
            })
            exported_mesh_indices.append(mesh_index)

        return exported_mesh_indices
    finally:
        obj_eval.to_mesh_clear()


def export_scene(output_path: str, depsgraph=None) -> None:
    context = bpy.context
    _flush_edit_mode_meshes()
    try:
        context.view_layer.update()
    except Exception:
        pass
    depsgraph = depsgraph or context.evaluated_depsgraph_get()

    blend_path = bpy.data.filepath
    model_name = pathlib.Path(blend_path).stem if blend_path else "untitled"

    scene_state = {
        "materials": [],
        "material_indices": {},
        "vertices": [],
        "indices": [],
        "meshes": [],
        "nodes": [],
        "node_mesh_refs": [],
    }

    root_index = 0
    scene_state["nodes"].append({
        "name": model_name,
        "parent_index": -1,
        "first_child_index": -1,
        "next_sibling_index": -1,
        "first_mesh_ref": 0,
        "mesh_ref_count": 0,
        "translation": (0.0, 0.0, 0.0),
        "rotation": (
            float(BLENDER_TO_PEEL_ROOT_ROTATION.x),
            float(BLENDER_TO_PEEL_ROOT_ROTATION.y),
            float(BLENDER_TO_PEEL_ROOT_ROTATION.z),
            float(BLENDER_TO_PEEL_ROOT_ROTATION.w),
        ),
        "scale": (1.0, 1.0, 1.0),
    })

    mesh_indices_by_key: dict[tuple, list[int]] = {}
    child_indices: list[int] = []

    for instance in depsgraph.object_instances:
        obj = instance.object
        if obj is None or obj.type != "MESH":
            continue

        mesh_key = _mesh_key(instance)
        mesh_indices = mesh_indices_by_key.get(mesh_key)
        if mesh_indices is None:
            mesh_indices = _build_mesh_payload(scene_state, obj, depsgraph)
            mesh_indices_by_key[mesh_key] = mesh_indices

        translation, rotation, scale = _matrix_trs(instance.matrix_world)
        first_mesh_ref = len(scene_state["node_mesh_refs"])
        scene_state["node_mesh_refs"].extend(mesh_indices)
        node_index = len(scene_state["nodes"])
        child_indices.append(node_index)
        scene_state["nodes"].append({
            "name": getattr(getattr(obj, "original", obj), "name", obj.name),
            "parent_index": root_index,
            "first_child_index": -1,
            "next_sibling_index": -1,
            "first_mesh_ref": first_mesh_ref,
            "mesh_ref_count": len(mesh_indices),
            "translation": translation,
            "rotation": rotation,
            "scale": scale,
        })

    if child_indices:
        scene_state["nodes"][root_index]["first_child_index"] = child_indices[0]
        for index, child_index in enumerate(child_indices[:-1]):
            scene_state["nodes"][child_index]["next_sibling_index"] = child_indices[index + 1]

    data = bytearray()
    data.extend(MAGIC)
    data.extend(struct.pack("<I", VERSION))
    data.extend(struct.pack(
        "<6I",
        len(scene_state["materials"]),
        len(scene_state["meshes"]),
        len(scene_state["nodes"]),
        len(scene_state["node_mesh_refs"]),
        len(scene_state["vertices"]),
        len(scene_state["indices"]),
    ))

    model_name_bytes = model_name.encode("utf-8")
    data.extend(struct.pack("<I", len(model_name_bytes)))
    data.extend(model_name_bytes)

    for material in scene_state["materials"]:
        name_bytes = material["name"].encode("utf-8")
        data.extend(struct.pack("<I", len(name_bytes)))
        data.extend(name_bytes)
        data.extend(struct.pack("<4f", *material["color"]))

    for mesh in scene_state["meshes"]:
        data.extend(struct.pack(
            "<5I",
            mesh["base_vertex"],
            mesh["vertex_count"],
            mesh["first_index"],
            mesh["index_count"],
            mesh["material_index"],
        ))

    for node in scene_state["nodes"]:
        name_bytes = node["name"].encode("utf-8")
        data.extend(struct.pack("<I", len(name_bytes)))
        data.extend(name_bytes)
        data.extend(struct.pack(
            "<4i",
            int(node["parent_index"]),
            int(node["first_child_index"]),
            int(node["next_sibling_index"]),
            0,
        ))
        data.extend(struct.pack(
            "<4I",
            int(node["first_mesh_ref"]),
            int(node["mesh_ref_count"]),
            0,
            0,
        ))
        data.extend(struct.pack("<3f", *node["translation"]))
        data.extend(struct.pack("<4f", *node["rotation"]))
        data.extend(struct.pack("<3f", *node["scale"]))

    for mesh_ref in scene_state["node_mesh_refs"]:
        data.extend(struct.pack("<I", int(mesh_ref)))

    for vertex in scene_state["vertices"]:
        px, py, pz = vertex["position"]
        nx, ny, nz = vertex["normal"]
        u, v = vertex["uv"]
        data.extend(struct.pack(
            "<14f",
            px, py, pz, 1.0,
            nx, ny, nz, 0.0,
            1.0, 0.0, 0.0, 1.0,
            u, v,
        ))

    for index in scene_state["indices"]:
        data.extend(struct.pack("<I", int(index)))

    output = pathlib.Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as handle:
        handle.write(data)
        temp_path = pathlib.Path(handle.name)
    temp_path.replace(output)


def export_scene_or_raise(output_path: str) -> None:
    try:
        export_scene(output_path)
    except Exception:
        traceback.print_exc()
        raise
