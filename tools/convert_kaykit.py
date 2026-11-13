#!/usr/bin/env python3
"""Переводит модели KayKit (CC0, Kay Lousberg) в формат игры.

KayKit раскрашивает модели одной текстурой-палитрой. Игре текстуры не нужны:
скрипт берёт цвет палитры в каждой вершине (по UV) и записывает его в цвет
вершины, сводит все части модели в одну и сохраняет .gltf без текстуры.
В альфе цвета — сила качания на ветру (кроны деревьев), её читает шейдер.

Запуск из папки проекта (нужны numpy и Pillow):
  python3 tools/convert_kaykit.py <папка KayKit-Medieval-Hexagon-Pack>

Источник: https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0
"""

import base64
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "models")

# (файл в паке, имя у нас, качание: None — нет, число — высота, выше которой качается крона)
MODELS = [
    ("decoration/nature/tree_single_A.gltf", "tree_pine", 0.35),
    ("decoration/nature/tree_single_B.gltf", "tree_round", 0.45),
    ("decoration/nature/trees_A_small.gltf", "trees_pine_small", 0.35),
    ("decoration/nature/trees_B_small.gltf", "trees_round_small", 0.45),
    ("decoration/nature/rock_single_A.gltf", "rock_a", None),
    ("decoration/nature/rock_single_B.gltf", "rock_b", None),
    ("decoration/nature/rock_single_C.gltf", "rock_c", None),
    ("decoration/nature/rock_single_D.gltf", "rock_d", None),
    ("decoration/nature/rock_single_E.gltf", "rock_e", None),
    ("decoration/nature/waterlily_A.gltf", "waterlily_a", None),
    ("decoration/nature/waterlily_B.gltf", "waterlily_b", None),
    ("decoration/props/barrel.gltf", "barrel", None),
    ("decoration/props/bucket_water.gltf", "bucket", None),
    ("decoration/props/crate_A_small.gltf", "crate", None),
    ("decoration/props/crate_open.gltf", "crate_open", None),
    ("decoration/props/sack.gltf", "sack", None),
    ("decoration/props/wheelbarrow.gltf", "wheelbarrow", None),
    ("decoration/props/resource_lumber.gltf", "lumber", None),
    ("decoration/props/pallet.gltf", "pallet", None),
    ("buildings/yellow/building_windmill_yellow.gltf", "windmill", None, "-fan"),
    # Крылья мельницы — отдельно, с центром на оси: их вращает игра.
    ("buildings/yellow/building_windmill_yellow.gltf", "windmill_fan", None, "+fan"),
]

COMPONENT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_accessor(gltf, buffers, index):
    accessor = gltf["accessors"][index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    data = buffers[view["buffer"]]
    count = accessor["count"]
    width = COUNT[accessor["type"]]
    fmt = COMPONENT[accessor["componentType"]]
    size = struct.calcsize(fmt)
    stride = view.get("byteStride", size * width)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    out = np.empty((count, width), dtype=np.float64)
    for i in range(count):
        out[i] = struct.unpack_from("<" + fmt * width, data, start + i * stride)
    if accessor.get("normalized") and fmt != "f":
        out /= float((1 << (8 * size)) - 1)
    return out


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def node_matrix(node):
    matrix = np.eye(4)
    if "matrix" in node:
        return np.array(node["matrix"]).reshape(4, 4).T
    if "scale" in node:
        matrix = np.diag(list(node["scale"]) + [1.0]) @ matrix
    if "rotation" in node:
        rotation = np.eye(4)
        rotation[:3, :3] = quat_matrix(node["rotation"])
        matrix = rotation @ matrix
    if "translation" in node:
        translation = np.eye(4)
        translation[:3, 3] = node["translation"]
        matrix = translation @ matrix
    return matrix


def harmonize(rgb):
    """Подгоняет палитру KayKit под нашу: листва — тёплая жёлто-зелёная,
    камни — тёплые серые (у KayKit они бирюзовые)."""
    rgb = rgb * 0.92 + 0.06
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    luma = 0.3 * r + 0.59 * g + 0.11 * b
    green = (g > r + 0.05) & (g > b)
    leafy = np.stack([g * 0.66, g * 1.02, g * 0.42], axis=1)
    rgb[green] = rgb[green] * 0.35 + leafy[green] * 0.65
    spread = rgb.max(axis=1) - rgb.min(axis=1)
    grey = spread < 0.22
    warm_grey = np.stack([luma * 1.04, luma * 1.0, luma * 0.93], axis=1)
    rgb[grey] = rgb[grey] * 0.4 + warm_grey[grey] * 0.6
    return np.clip(rgb, 0.0, 1.0)


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def convert(pack, source, name, sway_from, part=""):
    path = os.path.join(pack, "addons/kaykit_medieval_hexagon_pack/Assets/gltf", source)
    folder = os.path.dirname(path)
    gltf = json.load(open(path))
    buffers = [open(os.path.join(folder, b["uri"]), "rb").read() for b in gltf["buffers"]]
    palette = np.asarray(Image.open(os.path.join(folder, gltf["images"][0]["uri"])).convert("RGB"),
                         dtype=np.float64) / 255.0
    height, width = palette.shape[:2]

    positions, normals, colors, indices = [], [], [], []

    def wanted(node_name):
        if not part:
            return True
        has = part[1:] in node_name
        return has if part[0] == "+" else not has

    def visit(node_index, parent):
        node = gltf["nodes"][node_index]
        matrix = parent @ node_matrix(node)
        if part.startswith("+") and wanted(node.get("name", "")):
            # Деталь отдельно: без своего сдвига, ось вращения — в начале координат.
            matrix = parent @ node_matrix({k: v for k, v in node.items() if k != "translation"})
            print(f"  {node.get('name')} pivot {node.get('translation')}")
        if "mesh" in node and wanted(node.get("name", "")):
            for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
                attributes = primitive["attributes"]
                pos = read_accessor(gltf, buffers, attributes["POSITION"])
                nrm = read_accessor(gltf, buffers, attributes["NORMAL"])
                uv = read_accessor(gltf, buffers, attributes["TEXCOORD_0"])
                idx = read_accessor(gltf, buffers, primitive["indices"])[:, 0].astype(np.int64)
                pos = (matrix @ np.c_[pos, np.ones(len(pos))].T).T[:, :3]
                normal_matrix = np.linalg.inv(matrix[:3, :3]).T
                nrm = (normal_matrix @ nrm.T).T
                nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
                px = np.clip((uv[:, 0] % 1.0) * width, 0, width - 1).astype(int)
                py = np.clip((uv[:, 1] % 1.0) * height, 0, height - 1).astype(int)
                # В sRGB, как есть: Godot сам переводит цвета вершин в линейные.
                rgb = harmonize(palette[py, px].copy())
                start = sum(len(p) for p in positions)
                positions.append(pos)
                normals.append(nrm)
                colors.append(rgb)
                indices.append(idx + start)
        for child in node.get("children", []):
            visit(child, matrix)

    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        visit(root, np.eye(4))

    pos = np.concatenate(positions).astype(np.float32)
    nrm = np.concatenate(normals).astype(np.float32)
    rgb = np.concatenate(colors)
    alpha = np.zeros(len(pos))
    if sway_from is not None:
        top = pos[:, 1].max()
        alpha = np.clip((pos[:, 1] - sway_from) / max(top - sway_from, 1e-3), 0.0, 1.0) * 0.35
    col = np.c_[rgb, alpha].astype(np.float32)
    idx = np.concatenate(indices).astype(np.uint32)

    blob = pos.tobytes() + nrm.tobytes() + col.tobytes() + idx.tobytes()
    sizes = [pos.nbytes, nrm.nbytes, col.nbytes, idx.nbytes]
    offsets = np.cumsum([0] + sizes[:-1]).tolist()
    out = {
        "asset": {"version": "2.0", "generator": "convert_kaykit.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2},
            "indices": 3,
        }]}],
        "buffers": [{"byteLength": len(blob),
                     "uri": "data:application/octet-stream;base64," + base64.b64encode(blob).decode()}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": offsets[0], "byteLength": sizes[0], "target": 34962},
            {"buffer": 0, "byteOffset": offsets[1], "byteLength": sizes[1], "target": 34962},
            {"buffer": 0, "byteOffset": offsets[2], "byteLength": sizes[2], "target": 34962},
            {"buffer": 0, "byteOffset": offsets[3], "byteLength": sizes[3], "target": 34963},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(col), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ],
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, name + ".gltf"), "w") as handle:
        json.dump(out, handle)
    print(f"{name}: {len(idx) // 3} triangles, height {pos[:, 1].max() - pos[:, 1].min():.2f}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    for entry in MODELS:
        convert(sys.argv[1], *entry)
