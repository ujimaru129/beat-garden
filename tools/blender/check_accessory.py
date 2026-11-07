"""Check a Blender model against Roblox rigid-accessory rules before exporting.

How to use (Blender 4.x):
  1. Select the accessory mesh in Object Mode.
  2. Scripting tab > Open this file > set ACCESSORY_TYPE / BODY_SCALE below > Run Script.
  3. Read the report in the Info area / system console. Fix every "NG", then export.

Or from a terminal:
  blender -b model.blend --python tools/blender/check_accessory.py -- shoulder_collar normal

Rules come from Roblox "Rigid accessory specifications" (checked 2026-11-07):
https://create.roblox.com/docs/art/accessories/specifications
  - single mesh, max 4,000 triangles, watertight (no holes / open edges)
  - textures max 2048x2048
  - max size in studs per accessory type and body scale (1 Blender unit = 1 stud
    when scene Unit Scale is 1.0 and FBX export uses "Apply Scalings: FBX Unit Scale")
"""

import sys

import bmesh
import bpy

ACCESSORY_TYPE = "shoulder_collar"  # see SIZE_LIMITS keys
BODY_SCALE = "normal"  # classic / normal / slender

MAX_TRIANGLES = 4000
MAX_TEXTURE = 2048

# (width X, height Y, depth Z) in studs. Roblox Y-up; in Blender, height is Z and depth is Y.
SIZE_LIMITS = {
    "classic": {
        "hat": (3, 4, 3),
        "face": (3, 2, 2),
        "neck": (3, 3, 2),
        "shoulder_neck": (7, 3, 3),
        "shoulder_collar": (3, 3, 3),
        "shoulder_arm": (3, 3, 3),
        "front": (3, 3, 3),
        "back": (10, 7, 4.5),
    },
    "normal": {
        "hat": (1.87, 2.5, 1.87),
        "face": (1.87, 1.25, 1.25),
        "neck": (2.95, 3.68, 2.16),
        "shoulder_neck": (6.90, 3.68, 3.24),
        "shoulder_collar": (2.95, 3.68, 3.24),
        "shoulder_arm": (2.67, 4.40, 3.09),
        "front": (2.95, 3.68, 3.24),
        "back": (9.86, 8.59, 4.87),
    },
    "slender": {
        "hat": (1.78, 2.5, 1.78),
        "face": (1.78, 1.25, 1.18),
        "neck": (2.59, 3.39, 1.92),
        "shoulder_neck": (6.05, 3.39, 2.88),
        "shoulder_collar": (2.59, 3.39, 2.88),
        "shoulder_arm": (2.37, 3.96, 2.75),
        "front": (2.59, 3.39, 2.88),
        "back": (8.64, 7.91, 4.32),
    },
}


def parse_cli():
    global ACCESSORY_TYPE, BODY_SCALE
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1 :]
        if len(args) >= 1:
            ACCESSORY_TYPE = args[0]
        if len(args) >= 2:
            BODY_SCALE = args[1]


def check(context=None):
    context = context or bpy.context
    results = []  # (ok: bool | None, message)

    def ok(cond, msg):
        results.append((bool(cond), msg))

    def note(msg):
        results.append((None, msg))

    limits = SIZE_LIMITS.get(BODY_SCALE, {}).get(ACCESSORY_TYPE)
    if limits is None:
        types = ", ".join(SIZE_LIMITS["normal"])
        return [(False, f"unknown type/scale: {ACCESSORY_TYPE}/{BODY_SCALE} (types: {types})")]

    scene = context.scene
    ok(
        abs(scene.unit_settings.scale_length - 1.0) < 1e-6,
        f"scene Unit Scale is 1.0 (now {scene.unit_settings.scale_length})",
    )

    selected = [o for o in context.selected_objects if o.type == "MESH"]
    if not selected and context.active_object and context.active_object.type == "MESH":
        selected = [context.active_object]
    ok(len(selected) == 1, f"exactly one mesh selected (now {len(selected)}). Join parts with Ctrl+J")
    if len(selected) != 1:
        return results
    obj = selected[0]

    # Evaluated mesh = what gets exported (modifiers applied)
    depsgraph = context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    try:
        mesh.calc_loop_triangles()
        tris = len(mesh.loop_triangles)
        ok(tris <= MAX_TRIANGLES, f"triangles <= {MAX_TRIANGLES} (now {tris})")

        bm = bmesh.new()
        bm.from_mesh(mesh)
        open_edges = sum(1 for e in bm.edges if not e.is_manifold)
        bm.free()
        ok(open_edges == 0, f"watertight: no open / non-manifold edges (now {open_edges})")

        ngons = sum(1 for p in mesh.polygons if len(p.vertices) > 4)
        if ngons:
            note(f"{ngons} faces with 5+ sides (Roblox recommends quads/triangles)")
    finally:
        eval_obj.to_mesh_clear()

    if any(abs(s - 1.0) > 1e-6 for s in obj.scale) or any(abs(r) > 1e-6 for r in obj.rotation_euler):
        note("object has unapplied scale/rotation. Ctrl+A > All Transforms before export")
    if obj.modifiers:
        note(f"{len(obj.modifiers)} modifier(s) not applied. Apply them before export")

    # World-space size. Blender X = width, Z = height, Y = depth.
    xs, ys, zs = zip(*[(obj.matrix_world @ v.co)[:] for v in obj.data.vertices]) if obj.data.vertices else ((0,), (0,), (0,))
    width, depth, height = max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)
    lw, lh, ld = limits
    ok(width <= lw, f"width (X) <= {lw} studs (now {width:.2f})")
    ok(height <= lh, f"height (Z in Blender) <= {lh} studs (now {height:.2f})")
    ok(depth <= ld, f"depth (Y in Blender) <= {ld} studs (now {depth:.2f})")

    # Textures used by the object's materials
    images = set()
    for slot in obj.material_slots:
        mat = slot.material
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    images.add(node.image)
    if not images:
        note("no image textures found on the materials")
    for img in images:
        w, h = img.size
        ok(w <= MAX_TEXTURE and h <= MAX_TEXTURE, f"texture '{img.name}' <= {MAX_TEXTURE}px (now {w}x{h})")
    ok(len(obj.material_slots) <= 1, f"one material (now {len(obj.material_slots)}). Bake to a single texture")

    return results


def report(results):
    print(f"\n=== Roblox accessory check: {ACCESSORY_TYPE} / {BODY_SCALE} ===")
    failed = 0
    for status, msg in results:
        tag = "OK  " if status is True else ("NG  " if status is False else "NOTE")
        if status is False:
            failed += 1
        print(f"[{tag}] {msg}")
    print("=== result: " + ("ready to export" if failed == 0 else f"{failed} problem(s) to fix") + " ===\n")
    return failed


if __name__ == "__main__":
    parse_cli()
    report(check())
