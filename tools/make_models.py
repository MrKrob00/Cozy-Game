#!/usr/bin/env python3
"""Собственные модели игры: газонокосилка по частям, соломенная шляпа, ёжик,
находки (уточка, очки, гном, письмо, чайник), почтовый ящик, компостный ящик,
кусты и плитки дорожки.

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


def ball(mesh, radii, center, color, segments=10, rings=6, smooth=True):
    """Шар или эллипсоид: radii — число или (x, y, z)."""
    radii = np.array((radii,) * 3 if np.isscalar(radii) else radii, dtype=float)
    part = Mesh()
    profile = []
    for i in range(rings + 1):
        angle = -math.pi / 2 + math.pi * i / rings
        profile.append((math.cos(angle) if 0 < i < rings else 0.0, math.sin(angle)))
    lathe(part, profile, (0, 0, 0), color, segments, "y", smooth)
    center = np.asarray(center, dtype=float)
    mesh.add([v * radii + center for v in part.vertices], [(a, b, c) for a, b, c, _, _ in part.faces],
             color, smooth, outward_from=center)


def cone(mesh, base, tip, radius, color, segments=5, smooth=False):
    """Конус от центра основания base к вершине tip."""
    base, tip = np.asarray(base, dtype=float), np.asarray(tip, dtype=float)
    axis = (tip - base) / np.linalg.norm(tip - base)
    helper = np.array([0.0, 1.0, 0.0]) if abs(axis[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    side = np.cross(axis, helper)
    side /= np.linalg.norm(side)
    other = np.cross(axis, side)
    vertices = [base + (side * math.cos(2 * math.pi * k / segments)
                        + other * math.sin(2 * math.pi * k / segments)) * radius for k in range(segments)]
    vertices += [tip, base]
    faces = []
    for k in range(segments):
        j = (k + 1) % segments
        faces.append([k, j, segments])
        faces.append([j, k, segments + 1])
    mesh.add(vertices, faces, color, smooth, outward_from=base + (tip - base) * 0.3)


def jitter(mesh, amount, seed=1.0):
    """Слегка сдвигает вершины (одинаково для совпадающих): живой, неровный вид."""
    moved = []
    for v in mesh.vertices:
        key = np.round(v, 4)
        phase = key[0] * 12.9898 + key[1] * 78.233 + key[2] * 37.719 + seed
        shift = np.array([math.sin(phase * 43.3), math.sin(phase * 91.7 + 1.3), math.sin(phase * 27.1 + 2.1)])
        moved.append(v + shift * amount)
    mesh.vertices = moved
    return mesh


def write(mesh, name, smooth_angle=50.0, sway_from=None, sway=0.35):
    """Пишет .gltf с цветом вершин. Соседние грани с углом меньше smooth_angle
    сглаживаются, остальные рёбра остаются жёсткими. sway_from — высота, выше
    которой модель качается на ветру (сила — в альфе цвета, до sway)."""
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
    if sway_from == "all":
        # Вся модель качается одинаково: шейдер сам усиливает качание с высотой.
        col[:, 3] = sway
    elif sway_from is not None:
        top = pos[:, 1].max()
        col[:, 3] = np.clip((pos[:, 1] - sway_from) / max(top - sway_from, 1e-3), 0.0, 1.0) * sway
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
    """Колесо: шина с протектором и диск. Ось — X, начало координат в центре.
    Колёс четыре, и они маленькие на экране: деталей ровно столько, чтобы
    было видно, что колесо крутится (около 300 треугольников)."""
    mesh = Mesh()
    tyre = [(0.09, -0.045), (0.14, -0.045), (0.15, -0.025), (0.15, 0.025), (0.14, 0.045), (0.09, 0.045)]
    lathe(mesh, tyre, (0, 0, 0), TYRE, segments=12, axis="x")
    hub = [(0.0, -0.05), (0.08, -0.05), (0.095, -0.03), (0.095, 0.03), (0.08, 0.05), (0.0, 0.05)]
    lathe(mesh, hub, (0, 0, 0), CREAM, segments=10, axis="x")
    lathe(mesh, [(0.0, -0.062), (0.028, -0.062), (0.028, 0.062), (0.0, 0.062)], (0, 0, 0), STEEL,
          segments=8, axis="x")
    # Грунтозацепы: по ним видно, что колесо крутится.
    for i in range(8):
        angle = 2 * math.pi * i / 8
        box(mesh, (0.1, 0.03, 0.045), (0, math.cos(angle) * 0.15, math.sin(angle) * 0.15), DARK, bevel=0.0)
        # Коробка должна лежать по касательной: поворачиваем её вокруг X.
        start = len(mesh.vertices) - 24
        center = np.array([0, math.cos(angle) * 0.15, math.sin(angle) * 0.15])
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        for k in range(start, len(mesh.vertices)):
            y, z = mesh.vertices[k][1] - center[1], mesh.vertices[k][2] - center[2]
            mesh.vertices[k] = np.array([mesh.vertices[k][0], center[1] + y * cos_a - z * sin_a,
                                         center[2] + y * sin_a + z * cos_a])
    # Отверстия в диске (с обеих сторон: колёса стоят по обе стороны деки).
    for i in range(5):
        angle = 2 * math.pi * i / 5
        for side in (-1, 1):
            lathe(mesh, [(0.0, 0.0), (0.016, 0.0), (0.0, 0.004)],
                  (side * 0.049 - (0.004 if side > 0 else 0.0), math.cos(angle) * 0.058, math.sin(angle) * 0.058),
                  DARK, segments=5, axis="x")
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


# --- Зверьки, находки, садовые мелочи ---

SPIKES = (0.45, 0.32, 0.24)
SPIKES_DARK = (0.36, 0.25, 0.19)
FUR = (0.93, 0.80, 0.64)
FUR_DARK = (0.80, 0.64, 0.50)
INK = (0.15, 0.13, 0.14)
DUCK = (1.0, 0.86, 0.22)
DUCK_DARK = (0.95, 0.74, 0.16)
BEAK = (0.96, 0.52, 0.18)
GOLD = (1.0, 0.80, 0.25)
GLASS = (0.66, 0.86, 0.95)
SKIN = (1.0, 0.82, 0.66)
GNOME_COAT = (0.30, 0.50, 0.85)
WHITE = (0.97, 0.97, 0.95)
PAPER = (0.98, 0.95, 0.86)
PAPER_DARK = (0.90, 0.85, 0.74)
ENAMEL = (0.40, 0.62, 0.86)
ENAMEL_DARK = (0.30, 0.48, 0.72)
WOOD = (0.70, 0.50, 0.32)
WOOD_DARK = (0.56, 0.39, 0.25)
SOIL = (0.42, 0.31, 0.22)
COMPOST = (0.45, 0.62, 0.25)
COMPOST_DARK = (0.38, 0.50, 0.22)
POST_BLUE = (0.25, 0.42, 0.78)
POST_LIGHT = (0.36, 0.54, 0.88)
LEAVES = [(0.30, 0.62, 0.32), (0.40, 0.70, 0.34), (0.24, 0.54, 0.36)]
STONES = [(0.74, 0.73, 0.72), (0.66, 0.66, 0.68), (0.80, 0.78, 0.74)]


# Лапки ёжика: где стоят (игра двигает их на бегу, см. Animal).
HEDGEHOG_FEET = [(-0.14, 0.04, -0.2), (0.14, 0.04, -0.2), (-0.16, 0.04, 0.24), (0.16, 0.04, 0.24)]


def hedgehog_foot():
    """Лапка ёжика; начало координат — в её середине."""
    mesh = Mesh()
    ball(mesh, (0.072, 0.045, 0.1), (0, 0, 0), FUR, segments=7, rings=4)
    return mesh


def hedgehog():
    """Ёжик: смотрит на −Z, стоит на земле. Иголки — конусы по спине.
    Лапки — отдельная модель (hedgehog_foot): на бегу они перебирают."""
    mesh = Mesh()
    center, radii = np.array([0.0, 0.26, 0.06]), np.array([0.29, 0.25, 0.36])
    ball(mesh, radii, center, SPIKES, segments=12, rings=7)
    # Мордочка, нос, глаза, уши, лапки.
    ball(mesh, (0.2, 0.17, 0.2), (0, 0.18, -0.22), FUR, segments=10, rings=6)
    cone(mesh, (0, 0.17, -0.36), (0, 0.155, -0.53), 0.095, FUR, segments=8, smooth=True)
    ball(mesh, 0.042, (0, 0.165, -0.52), INK, segments=7, rings=4)
    for side in (-1, 1):
        ball(mesh, 0.03, (side * 0.085, 0.255, -0.385), INK, segments=6, rings=4)
        ball(mesh, (0.06, 0.07, 0.035), (side * 0.15, 0.35, -0.25), FUR_DARK, segments=7, rings=4)
    # Иголки: точки по спирали на спине, наклон назад.
    count = 90
    for i in range(count):
        y = 1 - 2 * (i + 0.5) / count
        ring = math.sqrt(1 - y * y)
        angle = i * math.pi * (3 - math.sqrt(5))
        direction = np.array([math.cos(angle) * ring, y, math.sin(angle) * ring])
        if direction[1] < -0.2 or (direction[2] < -0.45 and direction[1] < 0.75):
            continue
        normal = direction / radii
        normal /= np.linalg.norm(normal)
        lean = normal + np.array([0.0, 0.12, 0.4])
        lean /= np.linalg.norm(lean)
        surface = center + direction * radii
        length = 0.10 + 0.035 * math.sin(i * 1.7)
        cone(mesh, surface - lean * 0.04, surface + lean * length, 0.045,
             SPIKES_DARK if i % 3 == 0 else SPIKES, segments=4)
    return mesh


def duck():
    """Резиновая уточка. Начало координат — в середине тельца."""
    mesh = Mesh()
    ball(mesh, (0.17, 0.13, 0.2), (0, 0, 0.02), DUCK, segments=12, rings=7)
    cone(mesh, (0, 0.03, 0.15), (0, 0.15, 0.28), 0.08, DUCK, segments=8, smooth=True)
    ball(mesh, 0.115, (0, 0.17, -0.09), DUCK, segments=12, rings=7)
    box(mesh, (0.1, 0.035, 0.1), (0, 0.15, -0.21), BEAK, bevel=0.014)
    for side in (-1, 1):
        ball(mesh, 0.022, (side * 0.055, 0.215, -0.18), INK, segments=6, rings=4)
        ball(mesh, (0.035, 0.07, 0.115), (side * 0.16, 0.015, 0.04), DUCK_DARK, segments=8, rings=5)
    return mesh


def glasses():
    """Очки: круглая оправа, стёкла, дужки. Начало координат — у переносицы снизу."""
    mesh = Mesh()
    for side in (-1, 1):
        middle = np.array([side * 0.125, 0.05, 0.0])
        lathe(mesh, [(0.0, -0.007), (0.092, -0.007), (0.092, 0.007), (0.0, 0.007)], middle, GLASS,
              segments=14, axis="z")
        rim = [middle + np.array([math.cos(2 * math.pi * k / 14), math.sin(2 * math.pi * k / 14), 0.0]) * 0.1
               for k in range(15)]
        tube(mesh, rim, 0.016, INK, segments=5)
        tube(mesh, [(side * 0.225, 0.07, 0.0), (side * 0.235, 0.07, 0.03), (side * 0.235, 0.07, 0.2),
                    (side * 0.235, 0.035, 0.26)], 0.013, INK, segments=5)
    tube(mesh, [(-0.035, 0.08, 0.0), (0.0, 0.1, 0.0), (0.035, 0.08, 0.0)], 0.013, INK, segments=5)
    return mesh


def gnome():
    """Садовый гном: колпак, борода, кафтан. Начало координат — у пояса."""
    mesh = Mesh()
    lathe(mesh, [(0.0, -0.13), (0.14, -0.13), (0.155, -0.08), (0.11, 0.1), (0.0, 0.1)], (0, 0, 0), GNOME_COAT,
          segments=12)
    lathe(mesh, [(0.13, -0.035), (0.142, -0.035), (0.136, 0.0), (0.124, 0.0)], (0, 0, 0), INK, segments=12)
    for side in (-1, 1):
        ball(mesh, (0.06, 0.04, 0.085), (side * 0.07, -0.115, -0.08), INK, segments=7, rings=4)
        ball(mesh, 0.045, (side * 0.145, 0.0, -0.02), SKIN, segments=7, rings=4)
    ball(mesh, 0.105, (0, 0.17, 0), SKIN, segments=10, rings=6)
    ball(mesh, (0.095, 0.12, 0.07), (0, 0.08, -0.075), WHITE, segments=9, rings=5)
    ball(mesh, 0.032, (0, 0.165, -0.105), (1.0, 0.70, 0.60), segments=7, rings=4)
    lathe(mesh, [(0.0, 0.2), (0.125, 0.2), (0.13, 0.23), (0.085, 0.36), (0.035, 0.48), (0.0, 0.52)], (0, 0, 0), RED,
          segments=12)
    return mesh


def letter():
    """Письмо: конверт клапаном вверх, сургучная печать."""
    mesh = Mesh()
    box(mesh, (0.36, 0.03, 0.25), (0, 0, 0), PAPER, bevel=0.008)
    # Клапан и швы — тонкие накладки.
    mesh.add([(-0.17, 0.0165, -0.115), (0.17, 0.0165, -0.115), (0.0, 0.0165, 0.025)], [[0, 1, 2]], PAPER_DARK,
             smooth=False, outward_from=(0, -1, 0))
    for side in (-1, 1):
        mesh.add([(side * 0.17, 0.0158, 0.115), (side * 0.17, 0.0158, 0.095), (0.0, 0.0158, -0.005),
                  (0.0, 0.0158, 0.015)], [[0, 1, 2, 3]], PAPER_DARK, smooth=False, outward_from=(0, -1, 0))
    lathe(mesh, [(0.0, 0.0), (0.042, 0.0), (0.036, 0.014), (0.0, 0.016)], (0, 0.016, 0.02), RED, segments=9)
    return mesh


def teapot():
    """Эмалированный чайник. Начало координат — чуть ниже середины."""
    mesh = Mesh()
    lathe(mesh, [(0.0, -0.1), (0.11, -0.1), (0.165, -0.03), (0.172, 0.05), (0.135, 0.15), (0.085, 0.185),
                 (0.0, 0.185)], (0, 0, 0), ENAMEL, segments=14)
    lathe(mesh, [(0.095, -0.118), (0.118, -0.118), (0.118, -0.095), (0.095, -0.095)], (0, 0, 0), ENAMEL_DARK,
          segments=14)
    lathe(mesh, [(0.0, 0.18), (0.09, 0.18), (0.075, 0.212), (0.0, 0.222)], (0, 0, 0), ENAMEL_DARK, segments=14)
    ball(mesh, 0.032, (0, 0.245, 0), GOLD, segments=8, rings=5)
    tube(mesh, [(0.13, -0.01, 0), (0.215, 0.04, 0), (0.25, 0.12, 0), (0.285, 0.16, 0)], 0.03, ENAMEL, segments=7)
    tube(mesh, [(-0.13, 0.12, 0), (-0.235, 0.135, 0), (-0.275, 0.05, 0), (-0.235, -0.035, 0), (-0.14, -0.045, 0)],
         0.02, ENAMEL_DARK, segments=6)
    # Белые горошины.
    for angle, height in ((0.9, 0.06), (2.3, 0.0), (3.9, 0.07), (5.3, 0.01)):
        ball(mesh, (0.03, 0.03, 0.03), (math.cos(angle) * 0.158, height, math.sin(angle) * 0.158), WHITE,
             segments=6, rings=4)
    return mesh


def compost_bin(size=(1.3, 0.9, 1.1)):
    """Компостный ящик из досок с щелями, верх открыт. Стоит на земле."""
    mesh = Mesh()
    hx, hz = size[0] / 2, size[2] / 2
    for side in (-1, 1):
        for row in range(3):
            y = 0.17 + row * 0.29
            box(mesh, (size[0], 0.22, 0.06), (0, y, hz * side), WOOD, bevel=0.018)
            box(mesh, (0.06, 0.22, size[2]), (hx * side, y, 0), WOOD, bevel=0.018)
        for z_side in (-1, 1):
            box(mesh, (0.13, size[1] + 0.1, 0.13), (hx * side, (size[1] + 0.1) / 2, hz * z_side), WOOD_DARK,
                bevel=0.03)
    box(mesh, (size[0] - 0.1, 0.06, size[2] - 0.1), (0, 0.03, 0), SOIL, bevel=0.01)
    return mesh


def compost_pile():
    """Куча в ящике: игра растягивает её по высоте. Начало координат — в середине."""
    mesh = Mesh()
    ball(mesh, (0.5, 0.5, 0.42), (0, 0, 0), COMPOST, segments=9, rings=5)
    ball(mesh, (0.26, 0.3, 0.24), (0.22, 0.2, 0.12), COMPOST_DARK, segments=7, rings=4)
    ball(mesh, (0.24, 0.26, 0.22), (-0.2, 0.22, -0.1), COMPOST_DARK, segments=7, rings=4)
    jitter(mesh, 0.025, 3.0)
    return mesh


def mailbox():
    """Почтовый ящик «Бюро находок» на столбике: щель спереди (+Z), флажок сбоку."""
    mesh = Mesh()
    box(mesh, (0.11, 1.0, 0.11), (0, 0.5, 0), WOOD_DARK, bevel=0.025)
    box(mesh, (0.26, 0.05, 0.26), (0, 0.975, 0), WOOD, bevel=0.015)
    box(mesh, (0.5, 0.28, 0.36), (0, 1.14, 0), POST_BLUE, bevel=0.03)
    lathe(mesh, [(0.0, -0.25), (0.165, -0.25), (0.18, -0.235), (0.18, 0.235), (0.165, 0.25), (0.0, 0.25)],
          (0, 1.27, 0), POST_BLUE, segments=14, axis="x")
    box(mesh, (0.36, 0.2, 0.014), (0, 1.14, 0.184), POST_LIGHT, bevel=0.006)
    box(mesh, (0.26, 0.035, 0.012), (0, 1.19, 0.194), INK, bevel=0.004)
    ball(mesh, 0.022, (0.12, 1.09, 0.195), GOLD, segments=6, rings=4)
    box(mesh, (0.024, 0.22, 0.03), (0.262, 1.33, 0.02), CREAM, bevel=0.006)
    box(mesh, (0.03, 0.1, 0.14), (0.262, 1.4, -0.05), RED, bevel=0.008)
    return mesh


def bush(variant):
    """Куст из нескольких крон: единичный размер — радиус большой кроны 1 м."""
    mesh = Mesh()
    a, b, c = LEAVES[variant % 3], LEAVES[(variant + 1) % 3], LEAVES[(variant + 2) % 3]
    ball(mesh, (1.0, 0.8, 1.0), (0, 0.55, 0), a, segments=8, rings=5)
    if variant == 0:
        ball(mesh, (0.62, 0.5, 0.62), (0.62, 0.36, 0.34), b, segments=7, rings=4)
        ball(mesh, (0.58, 0.48, 0.58), (-0.58, 0.34, -0.3), c, segments=7, rings=4)
        ball(mesh, (0.5, 0.42, 0.5), (0.1, 1.02, -0.06), b, segments=7, rings=4)
    else:
        ball(mesh, (0.7, 0.58, 0.7), (-0.5, 0.42, 0.42), b, segments=7, rings=4)
        ball(mesh, (0.55, 0.45, 0.55), (0.55, 0.32, -0.42), c, segments=7, rings=4)
        ball(mesh, (0.45, 0.38, 0.45), (0.3, 0.95, 0.3), c, segments=7, rings=4)
    jitter(mesh, 0.05, 1.0 + variant)
    return mesh


def stepping_stone(variant):
    """Плитка дорожки: неровный плоский камень. Единичный размер — радиус 1 м,
    высоту игра не растягивает (модель уже приплюснута)."""
    mesh = Mesh()
    lathe(mesh, [(0.0, 0.0), (0.93, 0.0), (1.0, 0.07), (0.95, 0.17), (0.0, 0.17)], (0, 0, 0),
          STONES[variant % 3], segments=8)
    moved = []
    for v in mesh.vertices:
        angle = math.atan2(v[2], v[0])
        wobble = 1.0 + 0.09 * math.sin(angle * 3 + variant * 1.7) + 0.05 * math.sin(angle * 5 + variant)
        moved.append(np.array([v[0] * wobble, v[1], v[2] * wobble * (0.9 + 0.05 * variant)]))
    mesh.vertices = moved
    return mesh


TUFT_GREENS = [(0.40, 0.66, 0.32), (0.52, 0.76, 0.36), (0.34, 0.58, 0.32)]
FLOWER_STEM = (0.32, 0.58, 0.30)
FLOWER_HEART = (1.0, 0.84, 0.30)
WILD_PETALS = [(1.0, 0.98, 0.94), (1.0, 0.86, 0.32), (1.0, 0.58, 0.68), (0.74, 0.62, 1.0)]


def tuft(variant):
    """Кочка травы: несколько изогнутых плоских травинок (дёшево: их на лугу
    тысячи). Высота около 0,4 м, начало координат — на земле."""
    mesh = Mesh()
    blades = 5 + variant
    for i in range(blades):
        angle = 2 * math.pi * i / blades + variant * 0.7
        lean = 0.12 + 0.08 * ((i * 7 + variant) % 3)
        height = 0.3 + 0.1 * ((i * 5 + variant * 3) % 4) / 3
        out = np.array([math.cos(angle), 0.0, math.sin(angle)])
        side = np.array([-out[2], 0.0, out[0]])
        base = out * 0.04
        width = 0.045
        middle = base + out * lean * 0.45 + np.array([0, height * 0.55, 0])
        tip = base + out * lean + np.array([0, height, 0])
        color = TUFT_GREENS[(i + variant) % 3]
        vertices = [base - side * width, base + side * width, middle + side * width * 0.6,
                    middle - side * width * 0.6, tip]
        # Обе стороны: травинка плоская.
        for faces in ([[0, 1, 2, 3], [3, 2, 4]], [[0, 3, 2, 1], [3, 4, 2]]):
            part = Mesh()
            part.vertices = [np.asarray(v, dtype=float) for v in vertices]
            for face in faces:
                for k in range(1, len(face) - 1):
                    part.faces.append((face[0], face[k], face[k + 1], color, False))
            mesh.merge(part)
    return mesh


def wild_flower(variant):
    """Полевой цветок: стебелёк, пять лепестков, серединка (около 30
    треугольников). Высота около 0,3 м."""
    mesh = Mesh()
    height = 0.26 + 0.04 * (variant % 2)
    tube(mesh, [(0, 0, 0), (0.015, height * 0.5, 0), (0, height, 0)], 0.012, FLOWER_STEM, segments=3, smooth=False)
    # Листик у стебля.
    mesh.add([(0.0, 0.07, 0.0), (0.09, 0.12, 0.02), (0.02, 0.1, 0.0)], [[0, 1, 2]], FLOWER_STEM, smooth=False)
    mesh.add([(0.0, 0.07, 0.0), (0.02, 0.1, 0.0), (0.09, 0.12, 0.02)], [[0, 1, 2]], FLOWER_STEM, smooth=False)
    petal = WILD_PETALS[variant % len(WILD_PETALS)]
    center = np.array([0.0, height, 0.0])
    for k in range(5):
        angle = 2 * math.pi * k / 5
        direction = np.array([math.cos(angle), 0.18, math.sin(angle)])
        across = np.array([-math.sin(angle), 0.0, math.cos(angle)])
        mesh.add([center, center + direction * 0.06 + across * 0.035, center + direction * 0.085,
                  center + direction * 0.06 - across * 0.035], [[0, 1, 2, 3]], petal, smooth=False,
                 outward_from=center - np.array([0, 1, 0]))
    ball(mesh, (0.025, 0.018, 0.025), center + np.array([0, 0.01, 0]), FLOWER_HEART, segments=5, rings=2,
         smooth=False)
    return mesh


def pebble():
    """Камешек для бордюров клумб и берега пруда: единичный размер — радиус 1 м."""
    mesh = Mesh()
    ball(mesh, (1.0, 0.7, 0.9), (0, 0.25, 0), STONES[0], segments=7, rings=4)
    jitter(mesh, 0.07, 5.0)
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
    write(hedgehog(), "hedgehog")
    write(hedgehog_foot(), "hedgehog_foot")
    write(duck(), "duck")
    write(glasses(), "glasses")
    write(gnome(), "gnome")
    write(letter(), "letter")
    write(teapot(), "teapot")
    write(compost_bin(), "compost_bin")
    write(compost_pile(), "compost_pile")
    write(mailbox(), "mailbox")
    for variant in range(2):
        write(bush(variant), f"bush_{variant}", smooth_angle=70.0, sway_from=0.3, sway=0.15)
    for variant in range(3):
        write(stepping_stone(variant), f"stepping_stone_{variant}")
    write(pebble(), "pebble", smooth_angle=70.0)
    for variant in range(3):
        write(tuft(variant), f"tuft_{variant}", sway_from="all", sway=1.0)
    for variant in range(4):
        write(wild_flower(variant), f"wild_flower_{variant}", sway_from="all", sway=0.8)
