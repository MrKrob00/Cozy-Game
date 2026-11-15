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


def write(mesh, name, smooth_angle=50.0, sway_from=None, sway=0.35, normal_mode=None):
    """Пишет .gltf с цветом вершин. Соседние грани с углом меньше smooth_angle
    сглаживаются, остальные рёбра остаются жёсткими. sway_from — высота, выше
    которой модель качается на ветру (сила — в альфе цвета, до sway).
    normal_mode="up" — тонкие плоские вещи (лист, травинка): обе стороны освещены
    как верхняя (иначе нижняя сторона тёмная); normal_mode=(x, y, z) — нормали от
    этой точки наружу, как у шара (комок травинок светится целиком)."""
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
    if normal_mode == "up":
        nrm[:] = (0.0, 1.0, 0.0)
    elif normal_mode is not None:
        out = pos - np.asarray(normal_mode, dtype=np.float32) + np.array([0.0, 0.05, 0.0], dtype=np.float32)
        nrm = out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-6)
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


def srgb(color):
    """Цвет из шейдера игры (sRGB, как source_color) → линейный цвет вершин."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in color)


# Цвета травы игры (shaders/grass.gdshader): корень, верхушка, верхушка высокой.
GRASS_ROOT = srgb((0.16, 0.45, 0.22))
GRASS_TIP = srgb((0.55, 0.82, 0.30))
GRASS_TALL_TIP = srgb((0.80, 0.86, 0.38))


def visible_only(mesh, min_normal_y=-0.7):
    """Убирает грани, смотрящие вниз: их закрывает земля или то, на чём
    деталь лежит (низ досок, дно кучи). Камера смотрит сверху и сбоку."""
    kept = []
    for face in mesh.faces:
        a, b, c = (np.asarray(mesh.vertices[i]) for i in face[:3])
        normal = np.cross(b - a, c - a)
        length = np.linalg.norm(normal)
        if length > 1e-12 and normal[1] / length < min_normal_y:
            continue
        kept.append(face)
    mesh.faces = kept
    return mesh


def compost_bin(size=(1.3, 0.9, 1.1)):
    """Компостный ящик: сплошные стенки из плотно сбитых досок (без щелей),
    угловые столбики, верх открыт. Стоит на земле. Невидимое (низ досок и
    столбиков, дно) убрано."""
    mesh = Mesh()
    hx, hz = size[0] / 2, size[2] / 2
    rows = 3
    board = size[1] / rows
    for side in (-1, 1):
        for row in range(rows):
            y = board * (row + 0.5)
            tone = WOOD if (row + (side > 0)) % 2 == 0 else WOOD_DARK
            box(mesh, (size[0], board, 0.07), (0, y, hz * side), tone, bevel=0.012)
            box(mesh, (0.07, board, size[2]), (hx * side, y, 0), tone, bevel=0.012)
        for z_side in (-1, 1):
            box(mesh, (0.13, size[1] + 0.1, 0.13), (hx * side, (size[1] + 0.1) / 2, hz * z_side), WOOD_DARK,
                bevel=0.03)
    # Верхняя обвязка по краю стенок.
    for side in (-1, 1):
        box(mesh, (size[0] + 0.06, 0.05, 0.11), (0, size[1] + 0.02, hz * side), WOOD_DARK, bevel=0.012)
        box(mesh, (0.11, 0.05, size[2] + 0.06), (hx * side, size[1] + 0.02, 0), WOOD_DARK, bevel=0.012)
    box(mesh, (size[0] - 0.1, 0.06, size[2] - 0.1), (0, 0.03, 0), SOIL, bevel=0.01)
    return visible_only(mesh)


def compost_pile():
    """Куча в ящике: горка скошенной травы игры — сотни травинок её цветов
    (от тёмного корня к светлой верхушке), лежат вповалку, часть торчит.
    Под ними тёмная зелёная масса. Игра растягивает кучу по высоте; начало
    координат — у дна ящика. Только то, что видно: низа нет, лежащие
    травинки — одной стороной вверх."""
    import random
    rng = random.Random(7)
    mesh = Mesh()
    profile = [(0.56, -0.2), (0.56, -0.05), (0.5, 0.12), (0.38, 0.27), (0.2, 0.36), (0.0, 0.39)]
    lathe(mesh, profile, (0, 0, 0), srgb((0.36, 0.60, 0.26)), segments=14)

    def squared(x, z):
        """Круг → почти квадрат: ящик квадратный, трава доходит до углов."""
        r = math.hypot(x, z)
        if r < 1e-6:
            return x, z
        c, s_ = abs(x) / r, abs(z) / r
        k = (1.0 / max(c, s_)) ** 0.85
        return x * k, z * k

    mesh.vertices = [np.array([*squared(v[0], v[2])[:1], v[1], squared(v[0], v[2])[1]]) for v in mesh.vertices]
    jitter(mesh, 0.02, 5.0)
    visible_only(mesh, min_normal_y=-0.2)

    def surface(x, z):
        """Высота кучи над точкой (по профилю)."""
        r = math.hypot(x, z)
        points = list(reversed(profile))
        for (r0, y0), (r1, y1) in zip(points, points[1:]):
            if r0 <= r <= r1:
                return y0 + (y1 - y0) * (r - r0) / max(r1 - r0, 1e-6)
        return -0.05

    def blade(base, yaw, tilt, length, width, tip_color, two_sided):
        """Травинка как у травы игры: сужается к острому концу, чуть изогнута."""
        direction = np.array([math.cos(yaw) * math.cos(tilt), math.sin(tilt), math.sin(yaw) * math.cos(tilt)])
        side = np.array([-math.sin(yaw), 0.0, math.cos(yaw)])
        up = np.cross(side, direction)
        points, widths, colors = [], [], []
        for k in range(4):
            t = k / 3
            bend = 0.12 * length * t * t
            points.append(np.asarray(base) + direction * length * t - up * bend * 0.3 + np.array([0, bend * 0.2, 0]))
            widths.append(width * (1.0 - t) ** 0.8 if k < 3 else 0.0)
        for k in range(3):
            t = (k + 0.5) / 3
            colors.append(tuple(GRASS_ROOT[i] + (tip_color[i] - GRASS_ROOT[i]) * min(1.0, 0.6 + 0.5 * t) for i in range(3)))
        strip = ribbon(Mesh(), points, widths, side, colors)
        if not two_sided:
            # Лежит: остаётся только сторона, что смотрит вверх.
            visible_only(strip, min_normal_y=0.0)
        mesh.merge(strip)

    count = 460
    for i in range(count):
        angle = i * 2.39996 + rng.uniform(-0.3, 0.3)
        radius = 0.5 * math.sqrt((i + 0.5) / count)
        x, z = math.cos(angle) * radius, math.sin(angle) * radius
        y = surface(x, z) + rng.uniform(0.0, 0.03)
        x, z = squared(x, z)
        standing = rng.random() < 0.18
        tilt = rng.uniform(0.5, 1.1) if standing else rng.uniform(-0.05, 0.3)
        # Лежащие у края свисают наружу, по склону кучи.
        yaw = angle + rng.uniform(-1.4, 1.4) if not standing else rng.uniform(0, math.tau)
        tip = GRASS_TALL_TIP if rng.random() < 0.25 else GRASS_TIP
        length = rng.uniform(0.16, 0.3)
        # Стенки сплошные: травинка не должна проходить сквозь них (ящик внутри
        # 1,2 × 1,0 м; игра сжимает кучу по Z до 0,85).
        reach = length * math.cos(tilt)
        end = (x + math.cos(yaw) * reach, z + math.sin(yaw) * reach)
        if abs(end[0]) > 0.6 or abs(end[1]) > 0.58:
            yaw += math.pi
        blade((x, y, z), yaw, tilt, length, rng.uniform(0.035, 0.05), tip, standing)
    return mesh


def ribbon(mesh, points, widths, side, colors):
    """Плоская лента с двух сторон (травинка, обрезок): точки осевой линии,
    ширина в каждой, направление «вбок» и цвет каждого отрезка."""
    side = np.asarray(side, dtype=float)
    for i in range(len(points) - 1):
        a, b = np.asarray(points[i], dtype=float), np.asarray(points[i + 1], dtype=float)
        wa, wb = widths[i] * 0.5, widths[i + 1] * 0.5
        quad = [a - side * wa, a + side * wa, b + side * wb, b - side * wb]
        if wb < 1e-6:
            quad = quad[:3]
        for order in (list(range(len(quad))), list(reversed(range(len(quad))))):
            part = Mesh()
            part.vertices = [np.asarray(v, dtype=float) for v in quad]
            for k in range(1, len(order) - 1):
                part.faces.append((order[0], order[k], order[k + 1], colors[i], True))
            mesh.merge(part)
    return mesh


def turned(mesh, yaw=0.0, pitch=0.0, roll=0.0, offset=(0.0, 0.0, 0.0), scale=1.0):
    """Копия модели, повёрнутая (вокруг Y, потом X, потом Z) и сдвинутая."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    rot_y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rot_x = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    rot_z = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]])
    matrix = rot_y @ rot_x @ rot_z
    out = Mesh()
    out.vertices = [matrix @ (np.asarray(v) * scale) + np.asarray(offset) for v in mesh.vertices]
    out.faces = list(mesh.faces)
    return out


# Светлые модели эффектов: цвет даёт материал (листья — каждый свой оттенок).
FX_LIGHT = (0.97, 0.97, 0.95)
FX_MID = (0.86, 0.86, 0.84)
FX_DARK = (0.74, 0.74, 0.72)


def fx_leaf():
    """Лист, слетающий с кроны: овальный с острым кончиком, мелкие зубчики по
    краю, сложен «лодочкой» по средней жилке, боковые жилки, черешок; кончик
    чуть загнут. Верх светлее низа. Две стороны (крутится в полёте).
    Длина около 0,26 м; цвет даёт материал (у каждого листа свой оттенок)."""
    mesh = Mesh()
    length, width = 0.22, 0.075
    steps = 14
    spine, left, right = [], [], []
    for i in range(steps + 1):
        t = i / steps
        z = -length / 2 + length * t
        # Ширина: округлое основание, самое широкое место в первой трети, острый кончик.
        w = width * math.sin(math.pi * t ** 0.8) ** 0.9
        # Зубчики: каждая вторая точка края чуть внутрь.
        if 0 < i < steps and i % 2 == 1:
            w *= 0.86
        curl = 0.03 * max(0.0, t - 0.7) ** 2 / 0.09
        y = curl
        spine.append(np.array([0.0, y, z]))
        left.append(np.array([-w, y + 0.32 * w, z]))
        right.append(np.array([w, y + 0.32 * w, z]))
    for edge, top in ((left, FX_LIGHT), (right, FX_MID)):
        for i in range(steps):
            quad = [spine[i], edge[i], edge[i + 1], spine[i + 1]]
            for flip, color in ((False, top), (True, FX_DARK)):
                part = Mesh()
                part.vertices = [np.asarray(v, dtype=float) for v in quad]
                order = [0, 3, 2, 1] if flip else [0, 1, 2, 3]
                for k in range(1, 3):
                    part.faces.append((order[0], order[k], order[k + 1], color, False))
                mesh.merge(part)
    lift = np.array([0.0, 0.003, 0.0])
    # Средняя жилка и черешок.
    ribbon(mesh, [spine[0] + lift, spine[steps // 2] + lift, spine[-2] + lift], [0.007, 0.005, 0.002], (1, 0, 0),
           [FX_DARK, FX_DARK])
    ribbon(mesh, [spine[0], spine[0] + np.array([0.0, 0.012, -0.045])], [0.009, 0.006], (1, 0, 0), [FX_DARK])
    # Боковые жилки: от середины к краю, вперёд.
    for i in (3, 6, 9):
        for edge in (left, right):
            start = spine[i] + lift
            end = spine[i] * 0.4 + edge[i + 2] * 0.6 + lift + np.array([0.0, 0.002, 0.0])
            side = np.cross(end - start, np.array([0.0, 1.0, 0.0]))
            side /= max(np.linalg.norm(side), 1e-6)
            ribbon(mesh, [start, end], [0.004, 0.0015], side, [FX_DARK])
    return mesh


def fx_clipping():
    """Срезанная травинка, вылетающая из-под косилки: узкая, изогнутая,
    светлый срез внизу. Две стороны. Длина около 0,15 м (мельче сверху не видно)."""
    mesh = Mesh()
    points = [(0.0, 0.0, -0.075), (0.0, 0.016, -0.025), (0.0, 0.02, 0.025), (0.0, 0.012, 0.075)]
    ribbon(mesh, points, [0.05, 0.046, 0.032, 0.0], (1, 0, 0), [FX_MID, FX_LIGHT, FX_LIGHT])
    return mesh


CLUMP_GREENS = [(0.50, 0.78, 0.32), (0.64, 0.86, 0.38), (0.44, 0.70, 0.30), (0.78, 0.84, 0.40)]


def fx_clump():
    """Комок скошенной травы (летит из мешка в компост): спутанные изогнутые
    травинки разных оттенков. Около 0,18 м."""
    mesh = Mesh()
    for i in range(11):
        yaw = i * 2.4
        pitch = math.sin(i * 1.7) * 0.9
        bend = 0.03 + 0.02 * (i % 3)
        length = 0.15 + 0.04 * ((i * 5) % 3) / 2
        half = length / 2
        points = [(0.0, 0.0, -half), (0.0, bend, -half * 0.3), (0.0, bend * 0.8, half * 0.4), (0.0, -0.01, half)]
        blade = ribbon(Mesh(), points, [0.03, 0.034, 0.026, 0.008], (1, 0, 0), [CLUMP_GREENS[i % 4]] * 3)
        mesh.merge(turned(blade, yaw=yaw, pitch=pitch, roll=i * 0.9, offset=(0.0, 0.0, 0.0)))
    return mesh


BALLOON_COLORS = [(0.93, 0.36, 0.30), (1.0, 0.95, 0.86), (0.98, 0.78, 0.30), (1.0, 0.95, 0.86)]
BALLOON_BAND = (0.30, 0.58, 0.86)
BALLOON_SKIRT = (0.58, 0.30, 0.26)
WICKER = (0.80, 0.62, 0.38)
STEEL_DARK = (0.38, 0.40, 0.45)
WICKER_DARK = (0.64, 0.46, 0.27)
LEATHER = (0.48, 0.30, 0.20)
SANDBAG = (0.86, 0.78, 0.60)


def hot_air_balloon():
    """Воздушный шар: купол-капля из 16 клиньев в полоску, синий пояс с
    зубцами по экватору, макушка, тёмная юбка у горловины, восемь строп к
    раме горелки, плетёная корзина с кожаным бортиком и мешками с песком.
    Высота около 2,7 м, начало координат — дно корзины."""
    mesh = Mesh()
    gores, steps = 16, 3
    count = gores * steps
    # Профиль купола (радиус, высота) снизу вверх: узкая горловина, капля.
    profile = [(0.2, 1.0), (0.3, 1.1), (0.5, 1.28), (0.7, 1.5), (0.86, 1.74), (0.96, 1.98), (0.99, 2.16),
               (0.95, 2.34), (0.84, 2.5), (0.66, 2.62), (0.42, 2.7), (0.18, 2.74), (0.0, 2.75)]
    band_rows = (5, 6)
    rows = []
    for radius, height in profile:
        ring = []
        for k in range(count):
            angle = 2 * math.pi * k / count
            # Клин чуть выпуклый между швами.
            bulge = 1.0 + 0.035 * math.sin(math.pi * (k % steps) / steps)
            ring.append((math.cos(angle) * radius * bulge, height, math.sin(angle) * radius * bulge))
        rows.append(ring)
    for r in range(len(rows) - 1):
        for k in range(count):
            j = (k + 1) % count
            if r in band_rows:
                # Пояс с зубцами: нижняя половина клина — пояс, верхняя — по цвету клина.
                color = BALLOON_BAND if (r == band_rows[0] or (k // steps) % 2 == 0) else \
                    BALLOON_COLORS[(k // steps) % len(BALLOON_COLORS)]
            elif r >= len(rows) - 3:
                color = BALLOON_COLORS[0]
            else:
                color = BALLOON_COLORS[(k // steps) % len(BALLOON_COLORS)]
            quad = [rows[r][k], rows[r][j], rows[r + 1][j], rows[r + 1][k]]
            if profile[r + 1][0] < 1e-6:
                quad = quad[:3]
            mesh.add(quad, [list(range(len(quad)))], color, smooth=True, outward_from=(0, 1.9, 0))
    # Юбка у горловины.
    lathe(mesh, [(0.17, 0.9), (0.21, 1.02)], (0, 0, 0), BALLOON_SKIRT, segments=12)
    lathe(mesh, [(0.21, 1.02), (0.17, 0.9)], (0, 0, 0), BALLOON_SKIRT, segments=12)
    # Рама и горелка.
    lathe(mesh, [(0.0, 0.66), (0.07, 0.66), (0.1, 0.74), (0.08, 0.82), (0.0, 0.84)], (0, 0, 0), STEEL, segments=8)
    lathe(mesh, [(0.03, 0.82), (0.05, 0.86), (0.0, 0.9)], (0, 0, 0), (1.0, 0.72, 0.30), segments=6)
    for k in range(4):
        angle = math.pi / 4 + k * math.pi / 2
        tube(mesh, [(math.cos(angle) * 0.2, 0.44, math.sin(angle) * 0.2),
                    (math.cos(angle) * 0.09, 0.7, math.sin(angle) * 0.09)], 0.008, STEEL_DARK, segments=4)
    # Стропы от рамы к поясу купола.
    for k in range(8):
        angle = k * math.pi / 4
        tube(mesh, [(math.cos(angle) * 0.18, 0.62, math.sin(angle) * 0.18),
                    (math.cos(angle) * 0.2, 1.0, math.sin(angle) * 0.2)], 0.006, WOOD_DARK, segments=3)
    # Корзина: плетение полосами, кожаный бортик, мешки с песком.
    for i, y in enumerate((0.05, 0.13, 0.21, 0.29, 0.37)):
        box(mesh, (0.44 - i * 0.004, 0.08, 0.44 - i * 0.004), (0, y, 0), WICKER if i % 2 == 0 else WICKER_DARK,
            bevel=0.015)
    for k in range(4):
        x = -0.15 + k * 0.1
        for z in (-0.222, 0.222):
            box(mesh, (0.025, 0.36, 0.01), (x, 0.2, z), WICKER_DARK, bevel=0.0, smooth=False)
            box(mesh, (0.01, 0.36, 0.025), (z, 0.2, x), WICKER_DARK, bevel=0.0, smooth=False)
    box(mesh, (0.5, 0.05, 0.5), (0, 0.43, 0), LEATHER, bevel=0.022)
    for side in (-1, 1):
        ball(mesh, (0.05, 0.065, 0.035), (side * 0.25, 0.3, 0.1), SANDBAG, segments=7, rings=4)
        tube(mesh, [(side * 0.25, 0.36, 0.1), (side * 0.24, 0.43, 0.1)], 0.005, WOOD_DARK, segments=3)
    return mesh


GIFT = (0.52, 0.76, 0.92)
GIFT_DOTS = (1.0, 0.97, 0.88)
RIBBON = (0.92, 0.30, 0.32)
RIBBON_DARK = (0.74, 0.20, 0.24)


def parcel():
    """Подарок с воздушного шара: голубая коробка в белый горошек, крышка
    шире коробки, красная лента крест-накрест и пышный бант из двух петель
    с хвостиками. Начало координат — дно коробки."""
    mesh = Mesh()
    box(mesh, (0.3, 0.2, 0.26), (0, 0.1, 0), GIFT, bevel=0.012)
    box(mesh, (0.32, 0.06, 0.28), (0, 0.22, 0), GIFT, bevel=0.012)
    # Горошек на боках и крышке.
    def dot(center, normal, radius=0.016):
        normal = np.asarray(normal, dtype=float)
        a = np.cross(normal, [0.0, 1.0, 0.0] if abs(normal[1]) < 0.9 else [1.0, 0.0, 0.0])
        a /= np.linalg.norm(a)
        b = np.cross(normal, a)
        middle = np.asarray(center, dtype=float) + normal * 0.002
        ring = [middle + (a * math.cos(t) + b * math.sin(t)) * radius for t in np.linspace(0, 2 * math.pi, 9)[:-1]]
        mesh.add([middle] + ring, [[0, k + 1, (k + 1) % 8 + 1] for k in range(8)], GIFT_DOTS, smooth=False,
                 outward_from=middle - normal)
    for x in (-0.1, -0.05, 0.05, 0.1):
        for y in (0.05, 0.14):
            shift = 0.025 if y > 0.1 else -0.025
            for z in (-0.13, 0.13):
                if abs(x + shift) > 0.04:
                    dot((x + shift, y, z), (0, 0, 1 if z > 0 else -1))
            for xs in (-0.15, 0.15):
                if abs(x * 0.85 + shift) > 0.04:
                    dot((xs, y, x * 0.85 + shift), (1 if xs > 0 else -1, 0, 0))
    for x in (-0.11, -0.06, 0.06, 0.11):
        for z in (-0.09, 0.09):
            dot((x, 0.25, z + (0.02 if x > 0 else -0.02)), (0, 1, 0))
    # Лента крест-накрест.
    box(mesh, (0.325, 0.255, 0.05), (0, 0.127, 0), RIBBON, bevel=0.006)
    box(mesh, (0.05, 0.255, 0.285), (0, 0.127, 0), RIBBON, bevel=0.006)
    # Бант: две петли, узелок, два хвостика.
    for side in (-1, 1):
        loop = []
        for k in range(13):
            a = 2 * math.pi * k / 12
            loop.append((side * (0.06 + 0.055 * math.cos(a)), 0.29 + 0.04 * math.sin(a) + 0.02, 0.012 * math.sin(a)))
        tube(mesh, loop, 0.014, RIBBON, segments=6)
        tube(mesh, [(0, 0.27, 0), (side * 0.05, 0.255, 0.05), (side * 0.07, 0.25, 0.1)], 0.012, RIBBON_DARK,
             segments=5)
    ball(mesh, (0.026, 0.024, 0.024), (0, 0.29, 0), RIBBON_DARK, segments=8, rings=5)
    return mesh


PARACHUTE_RED = (0.92, 0.36, 0.32)
PARACHUTE_WHITE = (1.0, 0.96, 0.90)


def parachute():
    """Парашютик посылки: купол из десяти клиньев красный–белый с волнистым
    краем и дырочкой на макушке, видный и снизу; стропы сходятся к бантику
    посылки (над коробкой parcel)."""
    mesh = Mesh()
    gores, steps = 10, 3
    count = gores * steps
    profile = [(0.52, 0.66), (0.5, 0.74), (0.44, 0.82), (0.34, 0.89), (0.2, 0.94), (0.06, 0.96)]
    rows = []
    for r, (radius, height) in enumerate(profile):
        ring = []
        for k in range(count):
            angle = 2 * math.pi * k / count
            # Волнистый край: между стропами ткань провисает.
            sag = 0.035 * math.sin(math.pi * (k % steps) / steps) if r == 0 else 0.0
            pull = 1.0 - 0.06 * math.sin(math.pi * (k % steps) / steps) if r == 0 else 1.0
            ring.append((math.cos(angle) * radius * pull, height + sag, math.sin(angle) * radius * pull))
        rows.append(ring)
    for r in range(len(rows) - 1):
        for k in range(count):
            j = (k + 1) % count
            color = PARACHUTE_RED if (k // steps) % 2 == 0 else PARACHUTE_WHITE
            quad = [rows[r][k], rows[r][j], rows[r + 1][j], rows[r + 1][k]]
            mesh.add(quad, [[0, 1, 2, 3]], color, smooth=True, outward_from=(0, 0.5, 0))
            # Изнанка (снизу купол тоже виден), чуть темнее.
            mesh.add(quad, [[0, 3, 2, 1]], tuple(c * 0.82 for c in color), smooth=True, outward_from=(0, 1.5, 0))
    for k in range(gores):
        angle = 2 * math.pi * k * steps / count
        tube(mesh, [(0.0, 0.31, 0.0), (math.cos(angle) * 0.5, 0.66, math.sin(angle) * 0.5)], 0.004, PAPER_DARK,
             segments=3)
    return mesh


CLOVER = (0.46, 0.88, 0.30)
CLOVER_DARK = (0.30, 0.66, 0.22)
CLOVER_LIGHT = (0.92, 1.0, 0.82)
CLOVER_STEM = (0.30, 0.62, 0.24)


def clover():
    """Клевер-четырёхлистник: четыре листика-сердечка (острый конец к центру,
    выемка наружу) чуть сложены по жилке, на каждом светлая «галочка»;
    изогнутый стебелёк. Ярче травы: игра увеличивает его, чтобы он был виден
    над травой."""
    mesh = Mesh()
    top = np.array([0.03, 0.42, 0.0])
    tube(mesh, [(0, 0, 0), (0.0, 0.16, 0.01), (0.02, 0.32, 0.0), top], 0.014, CLOVER_STEM, segments=6)
    length = 0.15
    heart = []
    for k in range(25):
        t = 2 * math.pi * k / 24
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        heart.append((hx / 34.0, (hy + 17.0) / 30.0))   # кончик сердечка (−17) → 0, выемка → ~0.9
    for leaf in range(4):
        angle = math.pi / 4 + leaf * math.pi / 2
        out = np.array([math.cos(angle), 0.0, math.sin(angle)])
        side = np.array([-out[2], 0.0, out[0]])

        def at(u, v):
            # Лист сложен по жилке и чуть поднимается к краю.
            return top + out * v * length + side * u * length + np.array([0, 0.012 + abs(u) * 0.02 + v * 0.02, 0])

        center = at(0.0, 0.45)
        ring = [at(u, v) for u, v in heart[:-1]]
        for k in range(len(ring)):
            a, b = ring[k], ring[(k + 1) % len(ring)]
            mesh.add([center, a, b], [[0, 1, 2]], CLOVER, smooth=True, outward_from=center - np.array([0, 1.0, 0]))
            mesh.add([center, b, a], [[0, 1, 2]], CLOVER_DARK, smooth=True,
                     outward_from=center + np.array([0, 1.0, 0]))
        # Светлая «галочка» поперёк листика.
        lift = np.array([0, 0.004, 0])
        mark = [at(-0.3, 0.62), at(0.0, 0.38), at(0.3, 0.62)]
        ribbon(mesh, [mark[0] + lift, mark[1] + lift, mark[2] + lift], [0.012, 0.014, 0.012], np.array([0, 0, 0.0]) + out,
               [CLOVER_LIGHT, CLOVER_LIGHT])
    return mesh


BIRD = (0.36, 0.40, 0.50)
BIRD_BELLY = (0.90, 0.86, 0.78)


def bird_body():
    """Птица в полёте (тело): веретено, светлое брюшко, клюв, хвост. Клюв на −Z."""
    mesh = Mesh()
    ball(mesh, (0.06, 0.055, 0.15), (0, 0, 0), BIRD, segments=8, rings=5)
    ball(mesh, (0.045, 0.03, 0.1), (0, -0.025, -0.01), BIRD_BELLY, segments=7, rings=4)
    cone(mesh, (0, 0.005, -0.14), (0, 0.0, -0.2), 0.02, (0.96, 0.66, 0.24), segments=5)
    mesh.add([(0, 0.01, 0.12), (-0.06, 0.0, 0.24), (0.06, 0.0, 0.24)], [[0, 1, 2]], BIRD, smooth=False,
             outward_from=(0, -1, 0.15))
    return mesh


def bird_wing():
    """Крыло птицы (правое; левое — отражение): от плеча вдоль +X."""
    mesh = Mesh()
    outline = [(0.0, -0.05), (0.12, -0.07), (0.26, -0.03), (0.3, 0.02), (0.16, 0.06), (0.0, 0.06)]
    vertices = [np.array([x, 0.0, z]) for x, z in outline]
    for order in ([0, 1, 2, 3, 4, 5], [5, 4, 3, 2, 1, 0]):
        part = Mesh()
        part.vertices = [np.asarray(v, dtype=float) for v in vertices]
        for k in range(1, 5):
            part.faces.append((order[0], order[k], order[k + 1], BIRD, False))
        mesh.merge(part)
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


# --- Вместо последних примитивов: стрелка, яблоко, вода, мох, листья, бабочка, земля клумбы ---

APPLE = (0.90, 0.24, 0.22)
APPLE_SHINE = (1.0, 0.55, 0.45)
STEM = (0.40, 0.26, 0.16)
LEAF = (0.36, 0.66, 0.28)
WATER_DEEP = (0.30, 0.56, 0.78)
WATER_MID = (0.40, 0.68, 0.86)
WATER_SHALLOW = (0.56, 0.80, 0.90)
WATER_FOAM = (0.86, 0.95, 1.0)
MOSS = (0.36, 0.50, 0.30)
MOSS_LIGHT = (0.48, 0.62, 0.34)
DRY_LEAVES = [(0.72, 0.52, 0.26), (0.62, 0.44, 0.24), (0.76, 0.62, 0.30), (0.56, 0.60, 0.28)]
SOIL_DARK = (0.38, 0.27, 0.19)
SOIL_LIGHT = (0.52, 0.39, 0.28)
LILY_PINK = (1.0, 0.68, 0.80)
LILY_WHITE = (1.0, 0.92, 0.95)


def apple():
    """Яблоко с хвостиком и листиком. Начало координат — в середине."""
    mesh = Mesh()
    profile = [(0.0, -0.1), (0.07, -0.095), (0.11, -0.05), (0.12, 0.02), (0.1, 0.075), (0.05, 0.09), (0.0, 0.07)]
    lathe(mesh, profile, (0, 0, 0), APPLE, segments=9)
    ball(mesh, (0.03, 0.03, 0.03), (0.06, 0.04, -0.07), APPLE_SHINE, segments=5, rings=3)
    tube(mesh, [(0, 0.06, 0), (0.01, 0.12, 0), (0.025, 0.15, 0)], 0.012, STEM, segments=4, smooth=False)
    mesh.add([(0.02, 0.13, 0.0), (0.09, 0.16, 0.03), (0.11, 0.13, 0.0), (0.07, 0.12, -0.02)], [[0, 1, 2, 3]], LEAF,
             smooth=False, outward_from=(0.06, 0.0, 0.0))
    mesh.add([(0.02, 0.13, 0.0), (0.07, 0.12, -0.02), (0.11, 0.13, 0.0), (0.09, 0.16, 0.03)], [[0, 1, 2, 3]], LEAF,
             smooth=False, outward_from=(0.06, 0.3, 0.0))
    return mesh


def water_disc(rings_colors, segments=28, wobble=0.0, seed=0.0):
    """Вода: круглая плоскость радиусом 1 с кольцами цвета от края к середине
    (у берега мельче и светлее). Толщина 0,04, верх на y = 0."""
    mesh = Mesh()
    radii = [1.0, 0.9, 0.7, 0.4, 0.0]
    vertices, colors = [], []
    for ring, radius in enumerate(radii):
        for k in range(segments):
            angle = 2 * math.pi * k / segments
            r = radius * (1.0 + wobble * math.sin(angle * 3 + seed) * (1 if radius > 0.95 else 0.4))
            vertices.append(np.array([math.cos(angle) * r, 0.0, math.sin(angle) * r]))
    for ring in range(len(radii) - 1):
        color = rings_colors[ring]
        for k in range(segments):
            j = (k + 1) % segments
            a, b = ring * segments + k, ring * segments + j
            c, d = (ring + 1) * segments + j, (ring + 1) * segments + k
            part = Mesh()
            part.vertices = [vertices[a], vertices[b], vertices[c], vertices[d]]
            part.faces = [(0, 2, 1, color, True), (0, 3, 2, color, True)]
            mesh.merge(part)
    # Бортик: короткая стенка вниз, чтобы вода не была листом бумаги.
    for k in range(segments):
        j = (k + 1) % segments
        a, b = vertices[k], vertices[j]
        part = Mesh()
        part.vertices = [a, b, b + np.array([0, -0.04, 0]), a + np.array([0, -0.04, 0])]
        part.faces = [(0, 1, 2, rings_colors[0], False), (0, 2, 3, rings_colors[0], False)]
        mesh.merge(part)
    # Блики: несколько светлых полосок на воде.
    for i, (x, z, length) in enumerate([(-0.3, -0.35, 0.3), (0.25, 0.1, 0.22), (-0.05, 0.45, 0.18)]):
        box(mesh, (length, 0.004, 0.03), (x, 0.003, z), WATER_FOAM, bevel=0.0, smooth=False)
    return mesh


def moss_disc():
    """Мох в сухой чаше: неровный диск радиусом около 1, в два тона, с кочками."""
    mesh = water_disc([MOSS, MOSS_LIGHT, MOSS, MOSS_LIGHT], segments=20, wobble=0.04, seed=1.3)
    mesh.faces = [f for f in mesh.faces if f[3] != WATER_FOAM]
    for x, z, size in [(0.4, 0.2, 0.18), (-0.3, -0.4, 0.14), (-0.5, 0.35, 0.16), (0.15, -0.6, 0.12)]:
        ball(mesh, (size, size * 0.45, size), (x, 0.0, z), MOSS_LIGHT, segments=7, rings=3)
    return mesh


def dry_leaf(variant):
    """Палый лист: заострённый, с прожилкой, чуть выгнут."""
    mesh = Mesh()
    color = DRY_LEAVES[variant % len(DRY_LEAVES)]
    outline = [(0.0, -0.11), (0.05, -0.05), (0.06, 0.02), (0.035, 0.08), (0.0, 0.11), (-0.035, 0.08), (-0.06, 0.02),
               (-0.05, -0.05)]
    vertices = [np.array([x, 0.012 * (1 - (2 * z / 0.22) ** 2) + 0.006, z]) for x, z in outline]
    vertices.append(np.array([0.0, 0.02, 0.0]))
    center = len(vertices) - 1
    faces = [[i, (i + 1) % len(outline), center] for i in range(len(outline))]
    mesh.add(vertices, faces, color, smooth=False, outward_from=(0, -1, 0))
    box(mesh, (0.008, 0.004, 0.2), (0, 0.022, 0), tuple(c * 0.8 for c in color), bevel=0.0, smooth=False)
    return mesh


def water_jet():
    """Струя фонтана: светлая колонна, сужается кверху, с «шапкой» брызг.
    Начало координат — у основания."""
    mesh = Mesh()
    lathe(mesh, [(0.0, 0.0), (0.09, 0.0), (0.06, 0.35), (0.045, 0.7), (0.0, 0.72)], (0, 0, 0), WATER_SHALLOW,
          segments=8)
    for i, angle in enumerate(np.linspace(0, 2 * math.pi, 7)[:-1]):
        direction = np.array([math.cos(angle), 0.0, math.sin(angle)])
        tube(mesh, [(0, 0.7, 0), tuple(direction * 0.18 + np.array([0, 0.78, 0])),
                    tuple(direction * 0.3 + np.array([0, 0.62, 0]))], 0.03, WATER_FOAM, segments=5)
    ball(mesh, 0.07, (0, 0.74, 0), WATER_FOAM, segments=7, rings=4)
    return mesh


def lily_flower():
    """Цветок кувшинки на воде: два ряда лепестков и жёлтая серединка."""
    mesh = Mesh()
    for row, (count, length, rise, color) in enumerate([(8, 0.12, 0.03, LILY_PINK), (6, 0.08, 0.06, LILY_WHITE)]):
        for k in range(count):
            angle = 2 * math.pi * (k + 0.5 * row) / count
            d = np.array([math.cos(angle), 0.0, math.sin(angle)])
            side = np.array([-d[2], 0.0, d[0]])
            base = np.array([0.0, 0.02 + 0.01 * row, 0.0])
            mesh.add([base + side * 0.025, base + d * length * 0.6 + side * 0.04 + np.array([0, rise * 0.6, 0]),
                      base + d * length + np.array([0, rise, 0]),
                      base + d * length * 0.6 - side * 0.04 + np.array([0, rise * 0.6, 0]), base - side * 0.025],
                     [[0, 1, 2, 3, 4]], color, smooth=False, outward_from=base - np.array([0, 0.2, 0]))
    ball(mesh, (0.03, 0.02, 0.03), (0, 0.05, 0), FLOWER_HEART, segments=6, rings=3)
    return mesh


def butterfly_wing():
    """Крыло бабочки (правое, вдоль +X): две округлые лопасти, кайма потемнее
    и светлые пятнышки. Цвет даёт игра (цвет бабочки × цвет вершин), так что
    кайма — тёмный оттенок того же цвета."""
    mesh = Mesh()
    for lobe, (cx, cz, rx, rz) in enumerate([(0.075, -0.035, 0.075, 0.06), (0.06, 0.045, 0.055, 0.045)]):
        ring = []
        for k in range(10):
            angle = 2 * math.pi * k / 10
            ring.append(np.array([cx + math.cos(angle) * rx, 0.0, cz + math.sin(angle) * rz]))
        inner = [np.array([cx, 0.0, cz]) + (v - np.array([cx, 0.0, cz])) * 0.78 for v in ring]
        center = np.array([cx, 0.0, cz])
        for k in range(10):
            j = (k + 1) % 10
            for verts, color in (([inner[k], inner[j], center], (1.0, 1.0, 1.0)),
                                 ([ring[k], ring[j], inner[j], inner[k]], (0.5, 0.42, 0.42))):
                for face_up in (True, False):
                    order = list(range(len(verts))) if face_up else list(reversed(range(len(verts))))
                    mesh.add(verts, [order], color, smooth=False)
        ball(mesh, (0.016, 0.004, 0.016), (cx + rx * 0.3, 0.003, cz), (1.0, 0.97, 0.85), segments=6, rings=2,
             smooth=False)
        ball(mesh, (0.016, 0.004, 0.016), (cx + rx * 0.3, -0.003, cz), (1.0, 0.97, 0.85), segments=6, rings=2,
             smooth=False)
    return mesh


def butterfly_body():
    """Тельце бабочки вдоль Z (голова к −Z) с усиками."""
    mesh = Mesh()
    lathe(mesh, [(0.0, -0.08), (0.016, -0.06), (0.02, 0.0), (0.014, 0.06), (0.0, 0.08)], (0, 0, 0), (0.25, 0.2, 0.2),
          segments=6, axis="z")
    ball(mesh, 0.022, (0, 0.005, -0.085), (0.25, 0.2, 0.2), segments=6, rings=3)
    for side in (-1, 1):
        tube(mesh, [(side * 0.008, 0.015, -0.1), (side * 0.03, 0.05, -0.14), (side * 0.045, 0.06, -0.16)], 0.004,
             (0.2, 0.16, 0.16), segments=3, smooth=False)
    return mesh


def soil_bed():
    """Земля клумбы: невысокая насыпь 1 × 1 м с бороздками (игра растягивает её
    под размер клумбы)."""
    mesh = Mesh()
    box(mesh, (1.0, 0.07, 1.0), (0, 0.035, 0), SOIL_DARK, bevel=0.03)
    for i in range(4):
        x = -0.36 + i * 0.24
        box(mesh, (0.13, 0.03, 0.9), (x, 0.08, 0), SOIL_LIGHT, bevel=0.012)
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
    write(compost_pile(), "compost_pile", smooth_angle=70.0, normal_mode="up")
    write(fx_leaf(), "fx_leaf", normal_mode="up")
    write(hot_air_balloon(), "hot_air_balloon")
    write(parcel(), "parcel")
    write(parachute(), "parachute")
    write(clover(), "clover", sway_from=0.3, sway=0.6)
    write(bird_body(), "bird_body")
    write(bird_wing(), "bird_wing", normal_mode="up")
    write(fx_clipping(), "fx_clipping", normal_mode="up")
    write(fx_clump(), "fx_clump", normal_mode=(0.0, 0.0, 0.0))
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
    write(apple(), "apple", sway_from="all", sway=0.2)
    write(water_disc([WATER_SHALLOW, WATER_MID, WATER_MID, WATER_DEEP]), "water_disc", smooth_angle=10.0)
    write(moss_disc(), "moss_disc")
    for variant in range(4):
        write(dry_leaf(variant), f"dry_leaf_{variant}")
    write(water_jet(), "water_jet")
    write(lily_flower(), "lily_flower")
    write(butterfly_wing(), "butterfly_wing")
    write(butterfly_body(), "butterfly_body")
    write(soil_bed(), "soil_bed")
