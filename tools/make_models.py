#!/usr/bin/env python3
"""Собственные модели игры: газонокосилка по частям и соломенная шляпа.

Готовой бесплатной косилки в подходящем стиле не нашлось, поэтому она
смоделирована здесь: скруглённые коробки, тела вращения и трубки, цвет —
в вершинах (как у остальных моделей, см. tools/convert_kaykit.py).
Части отдельно, чтобы игра могла крутить колёса, раздувать мешок и менять
корпус и мотор при улучшениях.

Запуск из папки проекта (нужен numpy):
  python3 tools/make_models.py

Оси: вперёд −Z, вверх +Y; начало координат косилки — на земле под ножом.
"""

import base64
import json
import math
import os

import numpy as np

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "models")

CREAM = (0.98, 0.94, 0.84)
DARK = (0.20, 0.21, 0.25)
TYRE = (0.16, 0.16, 0.19)
METAL = (0.74, 0.76, 0.80)
STEEL = (0.52, 0.55, 0.60)
STRAW = (0.95, 0.80, 0.42)
STRAW_DARK = (0.80, 0.62, 0.30)
CANVAS = (0.50, 0.66, 0.40)
CANVAS_DARK = (0.38, 0.52, 0.32)
RED = (0.86, 0.26, 0.24)
# Корпус по уровням ножа: ширина деки (нож + 0,1 м) и цвет.
DECKS = [(0.70, (0.90, 0.30, 0.26)), (0.90, (0.95, 0.55, 0.20)), (1.10, (0.30, 0.62, 0.85))]


class Mesh:
    """Набор треугольников с цветом; нормали считаются при записи."""

    def __init__(self):
        self.vertices = []   # (x, y, z)
        self.faces = []      # (a, b, c, цвет, сглаживать)

    def add(self, vertices, faces, color, smooth=True, outward_from=None):
        """Добавляет деталь. outward_from — точка внутри детали: грани
        разворачиваются наружу от неё."""
        start = len(self.vertices)
        vertices = [np.asarray(v, dtype=float) for v in vertices]
        self.vertices.extend(vertices)
        for face in faces:
            for i in range(1, len(face) - 1):
                a, b, c = face[0], face[i], face[i + 1]
                if outward_from is not None:
                    normal = np.cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
                    middle = (vertices[a] + vertices[b] + vertices[c]) / 3.0
                    if np.dot(normal, middle - np.asarray(outward_from)) < 0.0:
                        b, c = c, b
                self.faces.append((start + a, start + b, start + c, color, smooth))
        return self

    def merge(self, other, offset=(0.0, 0.0, 0.0)):
        start = len(self.vertices)
        self.vertices.extend([v + np.asarray(offset) for v in other.vertices])
        self.faces.extend([(a + start, b + start, c + start, color, smooth)
                           for a, b, c, color, smooth in other.faces])
        return self


def box(mesh, size, center, color, bevel=0.03, smooth=True):
    """Коробка со снятыми фасками."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    b = min(bevel, hx * 0.9, hy * 0.9, hz * 0.9)
    vertices = []
    index = {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                index[(sx, sy, sz, "x")] = len(vertices)
                vertices.append((sx * hx, sy * (hy - b), sz * (hz - b)))
                index[(sx, sy, sz, "y")] = len(vertices)
                vertices.append((sx * (hx - b), sy * hy, sz * (hz - b)))
                index[(sx, sy, sz, "z")] = len(vertices)
                vertices.append((sx * (hx - b), sy * (hy - b), sz * hz))
    faces = []
    for s in (-1, 1):
        faces.append([index[(s, -1, -1, "x")], index[(s, 1, -1, "x")], index[(s, 1, 1, "x")], index[(s, -1, 1, "x")]])
        faces.append([index[(-1, s, -1, "y")], index[(1, s, -1, "y")], index[(1, s, 1, "y")], index[(-1, s, 1, "y")]])
        faces.append([index[(-1, -1, s, "z")], index[(1, -1, s, "z")], index[(1, 1, s, "z")], index[(-1, 1, s, "z")]])
    for a in (-1, 1):
        for c in (-1, 1):
            faces.append([index[(-1, a, c, "y")], index[(1, a, c, "y")], index[(1, a, c, "z")], index[(-1, a, c, "z")]])
            faces.append([index[(a, -1, c, "x")], index[(a, 1, c, "x")], index[(a, 1, c, "z")], index[(a, -1, c, "z")]])
            faces.append([index[(a, c, -1, "x")], index[(a, c, 1, "x")], index[(a, c, 1, "y")], index[(a, c, -1, "y")]])
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                faces.append([index[(sx, sy, sz, "x")], index[(sx, sy, sz, "y")], index[(sx, sy, sz, "z")]])
    center = np.asarray(center, dtype=float)
    mesh.add([np.asarray(v) + center for v in vertices], faces, color, smooth, outward_from=center)


def lathe(mesh, profile, center, color, segments=14, axis="y", smooth=True):
    """Тело вращения: profile — точки (радиус, высота вдоль оси) снизу вверх."""
    vertices = []
    for radius, along in profile:
        for i in range(segments):
            angle = 2 * math.pi * i / segments
            u, v = math.cos(angle) * radius, math.sin(angle) * radius
            if axis == "y":
                vertices.append((u, along, v))
            elif axis == "x":
                vertices.append((along, u, v))
            else:
                vertices.append((u, v, along))
    faces = []
    for row in range(len(profile) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            a, b = row * segments + i, row * segments + j
            c, d = (row + 1) * segments + j, (row + 1) * segments + i
            if profile[row][0] < 1e-6:
                faces.append([a, c, d])
            elif profile[row + 1][0] < 1e-6:
                faces.append([a, b, d])
            else:
                faces.append([a, b, c, d])
    center = np.asarray(center, dtype=float)
    lows = [p[1] for p in profile]
    middle_along = (min(lows) + max(lows)) / 2
    inside = {"y": (0, middle_along, 0), "x": (middle_along, 0, 0), "z": (0, 0, middle_along)}[axis]
    mesh.add([np.asarray(v) + center for v in vertices], faces, color, smooth,
             outward_from=np.asarray(inside) + center)


def tube(mesh, path, radius, color, segments=7, smooth=True):
    """Трубка вдоль ломаной."""
    path = [np.asarray(p, dtype=float) for p in path]
    rings = []
    normal = None
    for i, point in enumerate(path):
        before = path[i] - path[i - 1] if i > 0 else path[1] - path[0]
        after = path[i + 1] - path[i] if i < len(path) - 1 else before
        direction = before / np.linalg.norm(before) + after / np.linalg.norm(after)
        direction /= np.linalg.norm(direction)
        if normal is None:
            helper = np.array([0.0, 1.0, 0.0]) if abs(direction[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
            normal = np.cross(direction, helper)
        normal = normal - direction * np.dot(normal, direction)
        normal /= np.linalg.norm(normal)
        side = np.cross(direction, normal)
        # На изгибе кольцо шире, чтобы трубка не сужалась.
        widen = 1.0 / max(np.dot(direction, after / np.linalg.norm(after)), 0.5)
        rings.append([point + (normal * math.cos(2 * math.pi * k / segments)
                               + side * math.sin(2 * math.pi * k / segments)) * radius * widen
                      for k in range(segments)])
    vertices = [v for ring in rings for v in ring]
    faces = []
    for row in range(len(rings) - 1):
        for k in range(segments):
            j = (k + 1) % segments
            faces.append([row * segments + k, row * segments + j, (row + 1) * segments + j, (row + 1) * segments + k])
    start_cap = len(vertices)
    vertices.append(path[0])
    vertices.append(path[-1])
    for k in range(segments):
        j = (k + 1) % segments
        faces.append([start_cap, j, k])
        faces.append([start_cap + 1, (len(rings) - 1) * segments + k, (len(rings) - 1) * segments + j])
    # Грани трубки разворачиваем наружу от её оси по одной.
    start = len(mesh.vertices)
    mesh.vertices.extend(vertices)
    for face in faces:
        for i in range(1, len(face) - 1):
            a, b, c = face[0], face[i], face[i + 1]
            middle = (vertices[a] + vertices[b] + vertices[c]) / 3.0
            nearest = min(path, key=lambda p: np.linalg.norm(p - middle))
            face_normal = np.cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
            outward = middle - nearest
            if np.linalg.norm(outward) < 1e-5:
                outward = middle - (path[0] + path[-1]) / 2
            if np.dot(face_normal, outward) < 0.0:
                b, c = c, b
            mesh.faces.append((start + a, start + b, start + c, color, smooth))


def write(mesh, name, smooth_angle=50.0):
    """Пишет .gltf с цветом вершин. Соседние грани с углом меньше smooth_angle
    сглаживаются, остальные рёбра остаются жёсткими."""
    vertices = np.array(mesh.vertices)
    normals = []
    for a, b, c, _, _ in mesh.faces:
        normal = np.cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
        normals.append(normal)
    areas = [np.linalg.norm(n) for n in normals]
    units = [n / max(area, 1e-12) for n, area in zip(normals, areas)]
    # Грани, сходящиеся в одной точке (по координатам).
    around = {}
    for face_index, face in enumerate(mesh.faces):
        for corner in face[:3]:
            around.setdefault(tuple(np.round(vertices[corner], 5)), []).append(face_index)
    limit = math.cos(math.radians(smooth_angle))
    positions, out_normals, colors = [], [], []
    for face_index, (a, b, c, color, smooth) in enumerate(mesh.faces):
        if areas[face_index] < 1e-10:
            continue
        for corner in (a, b, c):
            normal = normals[face_index].copy()
            if smooth:
                for other in around[tuple(np.round(vertices[corner], 5))]:
                    if other != face_index and mesh.faces[other][4] \
                            and np.dot(units[other], units[face_index]) > limit:
                        normal += normals[other]
            normal /= max(np.linalg.norm(normal), 1e-12)
            positions.append(vertices[corner])
            out_normals.append(normal)
            colors.append((*color, 0.0))
    pos = np.array(positions, dtype=np.float32)
    nrm = np.array(out_normals, dtype=np.float32)
    col = np.array(colors, dtype=np.float32)
    idx = np.arange(len(pos), dtype=np.uint32)
    blob = pos.tobytes() + nrm.tobytes() + col.tobytes() + idx.tobytes()
    sizes = [pos.nbytes, nrm.nbytes, col.nbytes, idx.nbytes]
    offsets = np.cumsum([0] + sizes[:-1]).tolist()
    out = {
        "asset": {"version": "2.0", "generator": "make_models.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3}]}],
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
    size = pos.max(axis=0) - pos.min(axis=0)
    print(f"{name}: {len(idx) // 3} triangles, {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f}")


def deck(width, paint):
    """Корпус: дека с юбкой, бампер, полосы, площадка под мотор, крепления колёс."""
    mesh = Mesh()
    half = width / 2
    # Дека: широкий низ и приподнятая середина — ступенькой, как у настоящих.
    box(mesh, (width, 0.17, 0.78), (0, 0.255, 0.0), paint, bevel=0.06)
    box(mesh, (width * 0.74, 0.1, 0.56), (0, 0.37, 0.02), paint, bevel=0.045)
    # Тёмная юбка у земли прикрывает нож.
    box(mesh, (width + 0.03, 0.07, 0.72), (0, 0.15, 0.0), DARK, bevel=0.02)
    # Бампер спереди и светлые полосы по бортам.
    tube(mesh, [(-half - 0.02, 0.2, -0.33), (-half * 0.8, 0.2, -0.43), (half * 0.8, 0.2, -0.43),
                (half + 0.02, 0.2, -0.33)], 0.032, CREAM)
    for side in (-1, 1):
        box(mesh, (0.02, 0.05, 0.42), (side * (half + 0.004), 0.28, 0.0), CREAM, bevel=0.008)
        # Оси колёс.
        for z in (-0.24, 0.26):
            lathe(mesh, [(0.0, 0.0), (0.035, 0.0), (0.035, 0.07), (0.0, 0.07)],
                  (side * half - (0.07 if side > 0 else 0.0), 0.15, z), STEEL, segments=8, axis="x")
    # Значок спереди и выброс травы сзади (горловина мешка).
    lathe(mesh, [(0.0, 0.0), (0.06, 0.0), (0.05, 0.015), (0.0, 0.015)], (0, 0.3, -0.405), CREAM,
          segments=10, axis="z")
    box(mesh, (width * 0.5, 0.14, 0.1), (0, 0.33, 0.4), DARK, bevel=0.02)
    # Площадка под мотор.
    lathe(mesh, [(0.0, 0.0), (0.17, 0.0), (0.17, 0.02), (0.0, 0.02)], (0, 0.42, -0.06), DARK, segments=14)
    return mesh


def engine():
    """Мотор: блок, цилиндр с рёбрами охлаждения, фильтр, глушитель, ручка стартёра.
    Начало координат — на площадке деки (игра увеличивает мотор при улучшении)."""
    mesh = Mesh()
    box(mesh, (0.3, 0.12, 0.28), (0, 0.07, 0.0), DARK, bevel=0.03)
    # Цилиндр с рёбрами.
    lathe(mesh, [(0.0, 0.13), (0.105, 0.13), (0.105, 0.3), (0.0, 0.3)], (0, 0, 0), STEEL, segments=12)
    for y in (0.16, 0.2, 0.24, 0.28):
        lathe(mesh, [(0.105, y - 0.008), (0.135, y - 0.008), (0.135, y + 0.008), (0.105, y + 0.008)],
              (0, 0, 0), METAL, segments=12)
    # Воздушный фильтр слева, бак справа.
    box(mesh, (0.1, 0.12, 0.16), (-0.19, 0.2, 0.0), CREAM, bevel=0.025)
    box(mesh, (0.11, 0.1, 0.2), (0.19, 0.19, 0.02), RED, bevel=0.03)
    lathe(mesh, [(0.0, 0.24), (0.03, 0.24), (0.03, 0.262), (0.0, 0.262)], (0.19, 0, 0.02), DARK, segments=8)
    # Глушитель: труба вбок и назад.
    tube(mesh, [(0.0, 0.2, 0.1), (0.0, 0.2, 0.2), (0.12, 0.24, 0.24)], 0.028, STEEL, segments=6)
    tube(mesh, [(0.12, 0.24, 0.24), (0.17, 0.257, 0.257)], 0.037, DARK, segments=6)
    # Ручка стартёра.
    tube(mesh, [(-0.06, 0.25, -0.12), (-0.06, 0.27, -0.17)], 0.012, DARK, segments=5)
    tube(mesh, [(-0.1, 0.27, -0.17), (-0.02, 0.27, -0.17)], 0.02, RED, segments=6)
    return mesh


def engine_cap():
    """Крышка мотора: подпрыгивает на ходу. Начало координат — её низ."""
    mesh = Mesh()
    lathe(mesh, [(0.0, 0.0), (0.085, 0.0), (0.095, 0.02), (0.085, 0.05), (0.04, 0.07), (0.0, 0.07)],
          (0, 0, 0), STRAW, segments=12)
    return mesh


def wheel():
    """Колесо: шина с протектором и диск. Ось — X, начало координат в центре."""
    mesh = Mesh()
    tyre = [(0.09, -0.045), (0.135, -0.045), (0.15, -0.03), (0.15, 0.03), (0.135, 0.045), (0.09, 0.045)]
    lathe(mesh, tyre, (0, 0, 0), TYRE, segments=16, axis="x")
    hub = [(0.0, -0.05), (0.07, -0.05), (0.095, -0.035), (0.095, 0.035), (0.07, 0.05), (0.0, 0.05)]
    lathe(mesh, hub, (0, 0, 0), CREAM, segments=12, axis="x")
    lathe(mesh, [(0.0, -0.062), (0.028, -0.062), (0.028, 0.062), (0.0, 0.062)], (0, 0, 0), STEEL,
          segments=8, axis="x")
    # Грунтозацепы: по ним видно, что колесо крутится.
    for i in range(8):
        angle = 2 * math.pi * i / 8
        box(mesh, (0.1, 0.03, 0.045), (0, math.cos(angle) * 0.15, math.sin(angle) * 0.15), DARK, bevel=0.008)
        # Коробка должна лежать по касательной: поворачиваем её вокруг X.
        start = len(mesh.vertices) - 24
        center = np.array([0, math.cos(angle) * 0.15, math.sin(angle) * 0.15])
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        for k in range(start, len(mesh.vertices)):
            y, z = mesh.vertices[k][1] - center[1], mesh.vertices[k][2] - center[2]
            mesh.vertices[k] = np.array([mesh.vertices[k][0], center[1] + y * cos_a - z * sin_a,
                                         center[2] + y * sin_a + z * cos_a])
    # Отверстия в диске.
    for i in range(5):
        angle = 2 * math.pi * i / 5
        for side in (-1, 1):
            lathe(mesh, [(0.0, 0.0), (0.016, 0.0), (0.016, 0.004), (0.0, 0.004)],
                  (side * 0.049 - (0.004 if side > 0 else 0.0), math.cos(angle) * 0.058, math.sin(angle) * 0.058),
                  DARK, segments=6, axis="x")
    return mesh


def handle(grip=(0.23, 0.80, 0.58)):
    """Ручка: две трубы от деки к рукам, перекладина с резиновыми рукоятками,
    распорка и рычаг газа. grip — где ладонь (x, y, z)."""
    mesh = Mesh()
    gx, gy, gz = grip
    for side in (-1, 1):
        tube(mesh, [(side * gx, 0.3, 0.3), (side * gx, 0.36, 0.36), (side * gx, gy - 0.04, gz - 0.03),
                    (side * gx, gy, gz)], 0.022, METAL)
        # Крепление к деке.
        box(mesh, (0.05, 0.07, 0.07), (side * gx, 0.31, 0.31), DARK, bevel=0.012)
    tube(mesh, [(-gx - 0.09, gy, gz), (gx + 0.09, gy, gz)], 0.022, METAL)
    for side in (-1, 1):
        tube(mesh, [(side * (gx - 0.07), gy, gz), (side * (gx + 0.1), gy, gz)], 0.034, DARK, segments=8)
    # Распорка посередине и рычаг газа.
    mid_y, mid_z = 0.36 + (gy - 0.4) * 0.55, 0.36 + (gz - 0.39) * 0.55
    tube(mesh, [(-gx, mid_y, mid_z), (gx, mid_y, mid_z)], 0.016, STEEL, segments=6)
    tube(mesh, [(gx * 0.45, gy, gz), (gx * 0.45, gy + 0.06, gz - 0.05)], 0.012, DARK, segments=5)
    lathe(mesh, [(0.0, 0.0), (0.024, 0.0), (0.024, 0.03), (0.0, 0.03)], (gx * 0.45, gy + 0.05, gz - 0.06), RED,
          segments=8)
    return mesh


def bag():
    """Мешок для травы: раздувается по мере наполнения. Начало координат —
    у горловины снизу, мешок уходит назад (+Z) и вверх."""
    mesh = Mesh()
    box(mesh, (0.46, 0.34, 0.4), (0, 0.19, 0.22), CANVAS, bevel=0.09)
    # Каркас сверху и ручка.
    tube(mesh, [(-0.2, 0.35, 0.05), (-0.2, 0.37, 0.36), (0.2, 0.37, 0.36), (0.2, 0.35, 0.05)], 0.018,
         CANVAS_DARK, segments=6)
    tube(mesh, [(-0.07, 0.37, 0.2), (-0.07, 0.42, 0.2), (0.07, 0.42, 0.2), (0.07, 0.37, 0.2)], 0.014, DARK,
         segments=5)
    # Горловина.
    box(mesh, (0.4, 0.2, 0.06), (0, 0.17, 0.02), CANVAS_DARK, bevel=0.02)
    return mesh


def straw_hat():
    """Соломенная шляпа с лентой. Начало координат — на макушке, низ тульи."""
    mesh = Mesh()
    brim = [(0.0, 0.0), (0.2, 0.0), (0.345, -0.03), (0.36, -0.016), (0.2, 0.03), (0.0, 0.03)]
    lathe(mesh, brim, (0, 0, 0), STRAW, segments=16)
    crown = [(0.2, 0.02), (0.215, 0.09), (0.2, 0.16), (0.14, 0.2), (0.0, 0.21)]
    lathe(mesh, crown, (0, 0, 0), STRAW, segments=16)
    band = [(0.212, 0.035), (0.224, 0.045), (0.226, 0.085), (0.216, 0.095)]
    lathe(mesh, band, (0, 0, 0), RED, segments=16)
    # Край полей темнее: видно плетение.
    lathe(mesh, [(0.35, -0.034), (0.37, -0.026), (0.37, -0.01), (0.35, -0.006)], (0, 0, 0), STRAW_DARK,
          segments=16)
    return mesh


if __name__ == "__main__":
    for level, (width, paint) in enumerate(DECKS):
        write(deck(width, paint), f"mower_deck_{level}")
    write(engine(), "mower_engine")
    write(engine_cap(), "mower_cap")
    write(wheel(), "mower_wheel")
    write(handle(), "mower_handle")
    write(bag(), "mower_bag")
    write(straw_hat(), "straw_hat")
