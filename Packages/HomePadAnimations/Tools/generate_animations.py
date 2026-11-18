#!/usr/bin/env python3
"""Generates the HomePad Lottie animations as Bodymovin JSON.

Usage, from Packages/HomePadAnimations:
  python3 Tools/generate_animations.py            write every file under Resources
  python3 Tools/generate_animations.py --check    exit 1 if a checked-in file differs
  python3 Tools/generate_animations.py --list     print name, frames, loop, tintable

Python 3 standard library only. The output is deterministic: numbers are rounded
to three decimals and dictionaries keep their insertion order.

Conventions that the Swift side relies on:
  - 400 x 400 canvas, 60 fps, transparent background.
  - A stroke or fill named "Tint" takes the accent color (keypath "**.Tint.Color").
  - A stroke or fill named "Ink" is the neutral outline (keypath "**.Ink.Color").
  - Any other name (for example "Stripe") is a fixed color.
  - A looping animation has equal first and last keyframe values on every
    animated property, so frame 0 and the last frame are the same picture.
  - Only features of the lottie-ios Core Animation engine are used: shape
    layers, groups, ellipses, rectangles, bezier paths, strokes, fills, trim
    paths on strokes, and layer transforms. No expressions, effects, mattes,
    masks, merge paths, repeaters, gradients, or time remapping.
"""

import argparse
import json
import math
import os
import sys

FPS = 60
SIZE = 400
WHITE = (1.0, 1.0, 1.0)

# An easing is (out tangent of this keyframe, in tangent of the next keyframe).
LINEAR = ((0.0, 0.0), (1.0, 1.0))
EASE = ((0.42, 0.0), (0.58, 1.0))
EASE_OUT = ((0.33, 1.0), (0.68, 1.0))
EASE_IN = ((0.32, 0.0), (0.67, 0.0))

CAP_BUTT = 1
CAP_ROUND = 2
JOIN_ROUND = 2

# A circle quadrant drawn as one cubic bezier has handles of this length times the radius.
KAPPA = 0.5523


class Keys(list):
    """Keyframes: (frame, value) or (frame, value, easing). The easing shapes the
    segment that leaves the keyframe and defaults to EASE."""


def num(value):
    rounded = round(float(value), 3)
    if rounded == int(rounded):
        return int(rounded)
    return rounded


def nums(value):
    if isinstance(value, (list, tuple)):
        return [num(component) for component in value]
    return num(value)


def prop(value, pad=None):
    """A Lottie property. pad appends a third component to 2D vectors, which
    layer transforms need."""
    def shape(raw):
        out = nums(raw)
        if pad is not None:
            out = out + [num(pad)]
        return out

    if not isinstance(value, Keys):
        return {"a": 0, "k": shape(value)}
    frames = []
    for index, key in enumerate(value):
        raw = shape(key[1])
        frame = {"t": num(key[0]), "s": raw if isinstance(raw, list) else [raw]}
        if index < len(value) - 1:
            easing = key[2] if len(key) > 2 else EASE
            frame["o"] = {"x": [num(easing[0][0])], "y": [num(easing[0][1])]}
            frame["i"] = {"x": [num(easing[1][0])], "y": [num(easing[1][1])]}
        frames.append(frame)
    return {"a": 1, "k": frames}


def lerp(a, b, amount):
    if isinstance(a, (list, tuple)):
        return tuple(x + (y - x) * amount for x, y in zip(a, b))
    return a + (b - a) * amount


def periodic(points, period):
    """Linear keyframes over 0...period for a function that repeats every period.
    points is one cycle as (frame, value), sorted, spanning at most one period,
    with equal first and last values. Frames may fall outside 0...period."""
    first, last = points[0][0], points[-1][0]
    assert last - first <= period, "one cycle must fit in the period"
    assert points[0][1] == points[-1][1], "the cycle must close"

    def value_at(frame):
        local = first + ((frame - first) % period)
        if local >= last:
            return points[-1][1]
        for (ta, va), (tb, vb) in zip(points, points[1:]):
            if ta <= local <= tb:
                return vb if tb == ta else lerp(va, vb, (local - ta) / (tb - ta))
        raise AssertionError("unreachable")

    frames = sorted({0, period} | {round(t % period, 3) for t, _ in points})
    return Keys([(frame, value_at(frame), LINEAR) for frame in frames])


# Shape items

def transform(position=(0, 0), anchor=(0, 0), scale=(100, 100), rotation=0, opacity=100):
    return {
        "ty": "tr", "nm": "Transform",
        "p": prop(position), "a": prop(anchor), "s": prop(scale),
        "r": prop(rotation), "o": prop(opacity),
        "sk": prop(0), "sa": prop(0),
    }


def stroke(name, color, width, opacity=100, cap=CAP_ROUND):
    return {
        "ty": "st", "nm": name,
        "c": prop(tuple(color) + (1,)), "o": prop(opacity), "w": prop(width),
        "lc": cap, "lj": JOIN_ROUND, "ml": 4,
    }


def fill(name, color, opacity=100):
    return {"ty": "fl", "nm": name, "c": prop(tuple(color) + (1,)), "o": prop(opacity), "r": 1}


def ink(width, opacity=100):
    return stroke("Ink", WHITE, width, opacity)


def tint(width, opacity=100):
    return stroke("Tint", WHITE, width, opacity)


def tint_fill(opacity=100):
    return fill("Tint", WHITE, opacity)


def trim(end=100, start=0):
    return {"ty": "tm", "nm": "Trim", "s": prop(start), "e": prop(end), "o": prop(0), "m": 1}


def ellipse(center, size):
    return {"ty": "el", "nm": "Ellipse", "d": 1, "p": prop(center), "s": prop(size)}


def rect(center, size, radius):
    return {"ty": "rc", "nm": "Rect", "d": 1, "p": prop(center), "s": prop(size), "r": prop(radius)}


def path(vertices, closed=False, ins=None, outs=None):
    """A bezier path. ins and outs are tangents relative to each vertex."""
    zero = [(0, 0)] * len(vertices)
    return {
        "ty": "sh", "nm": "Path",
        "ks": {"a": 0, "k": {
            "i": [nums(t) for t in (ins or zero)],
            "o": [nums(t) for t in (outs or zero)],
            "v": [nums(v) for v in vertices],
            "c": closed,
        }},
    }


def line(start, end):
    return path([start, end])


def arc(center, radius_x, radius_y, start, end):
    """An elliptical arc. Angles are degrees clockwise from 12 o'clock."""
    cx, cy = center
    segments = max(1, math.ceil(abs(end - start) / 90))
    step = math.radians(end - start) / segments
    handle = 4 / 3 * math.tan(step / 4)

    def point(angle):
        return (cx + radius_x * math.sin(angle), cy - radius_y * math.cos(angle))

    def tangent(angle):
        return (radius_x * math.cos(angle) * handle, radius_y * math.sin(angle) * handle)

    vertices, ins, outs = [], [], []
    for index in range(segments + 1):
        angle = math.radians(start) + step * index
        tx, ty = tangent(angle)
        vertices.append(point(angle))
        ins.append((-tx, -ty) if index > 0 else (0, 0))
        outs.append((tx, ty) if index < segments else (0, 0))
    return path(vertices, ins=ins, outs=outs)


def group(name, *items, tr=None):
    return {"ty": "gr", "nm": name, "it": list(items) + [tr or transform()]}


def layer(name, groups, anchor=(200, 200), position=None, scale=(100, 100), rotation=0, opacity=100):
    """A shape layer. Shapes use canvas coordinates. The layer scales and rotates
    around anchor, and position is where that anchor sits on the canvas."""
    return {
        "ddd": 0, "ty": 4, "nm": name, "sr": 1,
        "ks": {
            "o": prop(opacity), "r": prop(rotation),
            "p": prop(anchor if position is None else position, pad=0),
            "a": prop(anchor, pad=0), "s": prop(scale, pad=100),
        },
        "ao": 0, "shapes": groups, "st": 0, "bm": 0,
    }


def composition(name, frames, layers):
    """layers is ordered front to back."""
    for index, item in enumerate(layers):
        item["ind"] = index + 1
        item["ip"] = 0
        item["op"] = frames
    return {
        "v": "5.9.0", "fr": FPS, "ip": 0, "op": frames, "w": SIZE, "h": SIZE,
        "nm": name, "ddd": 0, "assets": [], "layers": layers,
    }


# Reusable glyph parts

def display_parts(center, size, stand_height=None):
    """A square display on a short stand: (screen rect, stand path)."""
    cx, cy = center
    half = size / 2
    top = cy + half
    stand_half = size * 0.26
    height = size * 0.17 if stand_height is None else stand_height
    corner = min(height * 0.5, size * 0.07)
    handle = corner * KAPPA
    stand = path(
        [
            (cx - stand_half, top), (cx - stand_half, top + height - corner),
            (cx - stand_half + corner, top + height), (cx + stand_half - corner, top + height),
            (cx + stand_half, top + height - corner), (cx + stand_half, top),
        ],
        ins=[(0, 0), (0, 0), (-handle, 0), (0, 0), (0, handle), (0, 0)],
        outs=[(0, 0), (0, handle), (0, 0), (handle, 0), (0, 0), (0, 0)],
    )
    return rect(center, (size, size), size * 0.22), stand


def display_groups(center, size, width, stand_height=None):
    screen, stand = display_parts(center, size, stand_height)
    return [group("Screen", screen, ink(width)), group("Stand", stand, ink(width))]


def phone_groups(center, size, width):
    cx, cy = center
    w, h = size
    island_y = cy - h / 2 + w * 0.19
    return [
        group("Body", rect(center, size, w * 0.25), ink(width)),
        group("Island", line((cx - w * 0.13, island_y), (cx + w * 0.13, island_y)), ink(width * 0.75)),
    ]


def page_groups(center, size, width, line_trims=None):
    """A sheet with accent-colored text lines. line_trims gives one trim end per line."""
    cx, cy = center
    w, h = size
    left = cx - w * 0.3
    rows = [(-0.24, 0.3), (-0.04, 0.3), (0.16, 0.02)] if h > 80 else [(-0.14, 0.3), (0.12, 0.04)]
    groups = [group("Sheet", rect(center, size, w * 0.16), ink(width))]
    for index, (row, right) in enumerate(rows):
        items = [line((left, cy + h * row), (cx + w * right, cy + h * row))]
        if line_trims is not None:
            items.append(trim(end=line_trims[index]))
        items.append(tint(width * 0.8))
        groups.append(group("Line %d" % (index + 1), *items))
    return groups


# The animations

def success():
    frames = 90
    ring = layer("Ring", [
        group("Circle", ellipse((200, 200), (248, 248)), trim(end=Keys([(0, 0), (40, 100)])), tint(10)),
    ])
    check = layer(
        "Check",
        [group(
            "Mark", path([(146, 204), (184, 242), (258, 160)]),
            trim(end=Keys([(32, 0, EASE_OUT), (58, 100)])), tint(14),
        )],
        scale=Keys([(32, (88, 88), EASE_OUT), (58, (112, 112)), (78, (100, 100))]),
    )
    return composition("success", frames, [check, ring])


def face_scan():
    frames = 120
    count = 60
    ticks, highlights = [], []
    for index in range(count):
        angle = math.radians(index * 360 / count)
        dx, dy = math.sin(angle), -math.cos(angle)

        def at(radius):
            return (200 + dx * radius, 200 + dy * radius)

        peak = index * frames / count
        glow = periodic([(peak - 8, 0), (peak, 100), (peak + 48, 0)], frames)
        ticks.append(group("Tick %02d" % index, line(at(170), at(184)), ink(4, 32)))
        highlights.append(group("Tick %02d" % index, line(at(166), at(192)), tint(5, glow)))
    return composition("face-scan", frames, [layer("Highlight", highlights), layer("Ticks", ticks)])


def beam_incoming():
    frames = 150
    center = (200, 176)
    page = layer(
        "Page",
        page_groups(center, (80, 104), 6, line_trims=[
            Keys([(56 + 8 * index, 0, EASE_OUT), (78 + 8 * index, 100)]) for index in range(3)
        ]),
        anchor=center,
        position=Keys([(8, (200, 232), EASE_OUT), (52, center)]),
        scale=Keys([(8, (70, 70), EASE_OUT), (52, (100, 100))]),
        opacity=Keys([(8, 0, EASE_OUT), (30, 100)]),
    )
    rings = []
    for index in range(3):
        start = 46 + 14 * index
        rings.append(group(
            "Ring %d" % (index + 1),
            ellipse(center, Keys([(start, (140, 140), EASE_OUT), (start + 60, (206, 206))])),
            tint(4, Keys([(start, 0, LINEAR), (start + 8, 70, EASE_OUT), (start + 60, 0)])),
        ))
    display = layer("Display", display_groups(center, 220, 8), anchor=center)
    return composition("beam-incoming", frames, [page, layer("Ripples", rings, anchor=center), display])


def beam_sending():
    frames = 180
    phone_center, display_center = (112, 268), (290, 112)
    arc_center, radius_x, radius_y = (204, 150), 92, 38
    depart, arrive = 40, 120

    def on_arc(amount):
        angle = math.radians(270 + 90 * amount)
        return (arc_center[0] + radius_x * math.sin(angle), arc_center[1] - radius_y * math.cos(angle))

    def smooth(amount):
        return amount * amount * (3 - 2 * amount)

    def frame_at(progress):
        low, high = 0.0, 1.0
        for _ in range(40):
            middle = (low + high) / 2
            if smooth(middle) < progress:
                low = middle
            else:
                high = middle
        return depart + (arrive - depart) * low

    samples = 16
    travel = Keys([
        (depart + (arrive - depart) * step / samples, on_arc(smooth(step / samples)), LINEAR)
        for step in range(samples + 1)
    ])
    # The page is transparent by now, so it can slide back to the phone unseen.
    travel.append((frames, on_arc(0)))
    page = layer(
        "Page", page_groups(on_arc(0), (36, 46), 5),
        anchor=on_arc(0), position=travel,
        scale=Keys([
            (30, (60, 60), EASE_OUT), (46, (100, 100)), (108, (100, 100), EASE_IN), (122, (70, 70)),
            (frames, (60, 60)),
        ]),
        opacity=Keys([(0, 0), (30, 0, EASE_OUT), (44, 100), (108, 100, EASE_IN), (122, 0), (frames, 0)]),
    )

    dots = []
    dot_count = 7
    for index in range(dot_count):
        amount = 0.07 + index * 0.143
        appear = round(frame_at(min(1.0, amount + 0.23))) + 2 * index
        dots.append(group(
            "Dot %d" % (index + 1), ellipse(on_arc(amount), (7, 7)),
            tint_fill(Keys([
                (0, 100), (6 + 2 * index, 100), (22 + 2 * index, 0),
                (appear, 0), (appear + 10, 100), (frames, 100),
            ])),
        ))

    display = layer(
        "Display", display_groups(display_center, 128, 7, stand_height=22), anchor=display_center,
        scale=Keys([(0, (100, 100)), (116, (100, 100)), (130, (106, 106)), (148, (100, 100)), (frames, (100, 100))]),
    )
    phone = layer(
        "Phone", phone_groups(phone_center, (96, 172), 7), anchor=phone_center,
        scale=Keys([(0, (100, 100)), (26, (100, 100)), (36, (96, 96)), (50, (100, 100)), (frames, (100, 100))]),
    )
    return composition("beam-sending", frames, [page, layer("Arc", dots), display, phone])


def presence_pulse():
    frames = 180
    rings = []
    ring_count = 3
    growth = [(step / 8, 44 + 256 * (1 - (1 - step / 8) ** 2)) for step in range(9)]
    for index in range(ring_count):
        offset = -index * frames / ring_count
        # The ring shrinks back while it is fully transparent, so the loop has no jump.
        sizes = [(offset + phase * 0.94 * frames, (size, size)) for phase, size in growth]
        sizes.append((offset + frames, (44, 44)))
        fade = [(offset, 0), (offset + 0.12 * frames, 42), (offset + 0.9 * frames, 0), (offset + frames, 0)]
        rings.append(group(
            "Ring %d" % (index + 1),
            ellipse((200, 200), periodic(sizes, frames)),
            tint(3, periodic(fade, frames)),
        ))
    dot = layer("Dot", [group(
        "Core", ellipse((200, 200), Keys([(0, (30, 30)), (90, (36, 36)), (frames, (30, 30))])), tint_fill(),
    )])
    return composition("presence-pulse", frames, [dot, layer("Rings", rings)])


def timer_done():
    frames = 150
    body = path(
        [(118, 262), (146, 226), (146, 176), (200, 120), (254, 176), (254, 226), (282, 262)],
        closed=True,
        ins=[(0, 0), (0, 16), (0, 0), (-30, 0), (0, -30), (0, 0), (-18, -10)],
        outs=[(18, -10), (0, 0), (0, -30), (30, 0), (0, 0), (0, 16), (0, 0)],
    )
    clapper = path([(184, 262), (216, 262)], ins=[(0, 0), (0, 26)], outs=[(0, 26), (0, 0)])
    bell = layer(
        "Bell",
        [
            group("Body", body, tint(8)),
            group("Clapper", clapper, tint(8)),
            group("Knob", line((200, 120), (200, 106)), tint(8)),
        ],
        anchor=(200, 104),
        rotation=Keys([
            (0, 0), (12, 16), (32, -14), (52, 11), (72, -8), (92, 5), (110, -2), (124, 0), (frames, 0),
        ]),
    )
    chimes = []
    for side, direction in (("Left", -1), ("Right", 1)):
        for rank, (radius, spread, delay) in enumerate(((118, 15, 0), (146, 19, 8))):
            middle = 62 * direction
            chimes.append(group(
                "%s %d" % (side, rank + 1),
                arc((200, 196), radius, radius, middle - spread, middle + spread),
                tint(7, Keys([
                    (0, 0), (6 + delay, 0), (18 + delay, 100), (40 + delay, 30),
                    (56 + delay, 100), (88 + delay, 0), (frames, 0),
                ])),
            ))
    return composition("timer-done", frames, [bell, layer("Chime", chimes)])


def pairing():
    frames = 180
    phone_center, display_center, link_center = (112, 201), (296, 190), (194, 200)

    def slide(center, distance):
        apart = (center[0] + distance, center[1])
        return Keys([(0, center), (40, center), (80, apart), (96, apart), (140, center), (frames, center)])

    capsule = transform(position=link_center, rotation=-45)
    link = layer(
        "Link",
        [
            group("Loop 1", rect((-11, 0), (38, 22), 11), tint(6), tr=capsule),
            group("Loop 2", rect((11, 0), (38, 22), 11), tint(6), tr=capsule),
        ],
        anchor=link_center,
        scale=Keys([
            (0, (100, 100)), (30, (100, 100), EASE_IN), (44, (60, 60)), (136, (60, 60), EASE_OUT),
            (152, (112, 112)), (166, (100, 100)), (frames, (100, 100)),
        ]),
        opacity=Keys([(0, 100), (30, 100), (44, 0), (136, 0), (148, 100), (frames, 100)]),
    )
    phone = layer(
        "Phone", phone_groups(phone_center, (84, 150), 7),
        anchor=phone_center, position=slide(phone_center, -28),
    )
    display = layer(
        "Display", display_groups(display_center, 124, 7, stand_height=24),
        anchor=display_center, position=slide(display_center, 28),
    )
    return composition("pairing", frames, [link, phone, display])


STRIPES = ("61BB46", "FDB827", "F5821F", "E03A3E", "963D97", "009DDC")


def hex_color(text):
    return tuple(int(text[index:index + 2], 16) / 255 for index in (0, 2, 4))


def hello():
    frames = 210
    center, size, inset = (200, 172), 232, 22
    left, top = center[0] - size / 2 + inset, center[1] - size / 2 + inset
    span = size - 2 * inset
    band = span / len(STRIPES)
    stripes = []
    for index, color in enumerate(STRIPES):
        y = top + band * (index + 0.5)
        start = 12 + 8 * index
        stripes.append(group(
            "Stripe %d" % (index + 1), line((left, y), (left + span, y)),
            trim(end=Keys([(start, 0, EASE_OUT), (start + 44, 100)])),
            # Slightly taller than the band so neighbors overlap and no seam shows.
            stroke("Stripe", hex_color(color), band + 0.6, cap=CAP_BUTT),
        ))
    screen, stand = display_parts(center, size)
    outline = layer("Display", [
        group("Screen", screen, trim(end=Keys([(84, 0), (150, 100)])), ink(8)),
        group("Stand", stand, trim(end=Keys([(140, 0), (178, 100)])), ink(8)),
    ], anchor=center)
    return composition("hello", frames, [outline, layer("Stripes", stripes, anchor=center)])


def listening():
    frames = 120
    heights = [
        [(0, 44), (24, 96), (52, 56), (84, 120), (frames, 44)],
        [(0, 110), (30, 60), (62, 150), (92, 84), (frames, 110)],
        [(0, 70), (20, 170), (48, 96), (78, 190), (104, 120), (frames, 70)],
        [(0, 130), (28, 70), (58, 140), (90, 60), (frames, 130)],
        [(0, 56), (34, 108), (66, 48), (96, 90), (frames, 56)],
    ]
    bars = []
    for index, keys in enumerate(heights):
        x = 200 + (index - 2) * 40
        bars.append(group(
            "Bar %d" % (index + 1),
            rect((x, 200), Keys([(frame, (18, height)) for frame, height in keys]), 9),
            tint_fill(),
        ))
    return composition("listening", frames, [layer("Bars", bars)])


def locked():
    frames = 90
    shackle = path(
        [(162, 184), (162, 150), (200, 112), (238, 150), (238, 184)],
        ins=[(0, 0), (0, 0), (-21, 0), (0, -21), (0, 0)],
        outs=[(0, 0), (0, -21), (21, 0), (0, 0), (0, 0)],
    )
    shackle_layer = layer(
        "Shackle", [group("Bar", shackle, tint(8))], anchor=(200, 184),
        position=Keys([(0, (200, 160)), (12, (200, 160), EASE_IN), (34, (200, 188)), (48, (200, 184))]),
    )
    body = layer(
        "Body", [group("Case", rect((200, 236), (136, 108), 24), tint(8))], anchor=(200, 236),
        scale=Keys([(30, (100, 100)), (40, (95, 95)), (58, (100, 100))]),
    )
    keyhole = layer(
        "Keyhole",
        [
            group("Hole", ellipse((200, 228), (18, 18)), tint_fill()),
            group("Slot", line((200, 232), (200, 250)), tint(7)),
        ],
        anchor=(200, 236),
        scale=Keys([(40, (40, 40), EASE_OUT), (58, (115, 115)), (72, (100, 100))]),
        opacity=Keys([(40, 0, EASE_OUT), (52, 100)]),
    )
    return composition("locked", frames, [keyhole, shackle_layer, body])


def guest():
    frames = 180
    shoulders = path(
        [(132, 272), (200, 206), (268, 272)],
        ins=[(0, 0), (-40, 0), (0, -38)],
        outs=[(0, -38), (40, 0), (0, 0)],
    )
    person = layer("Person", [
        group("Head", ellipse((200, 158), (64, 64)), ink(8)),
        group("Shoulders", shoulders, ink(8)),
    ])
    segments = [
        group("Segment %d" % (index + 1), arc((200, 200), 172, 172, index * 90 + 12, index * 90 + 78), tint(5))
        for index in range(4)
    ]
    ring = layer(
        "Ring", segments,
        scale=Keys([(0, (100, 100)), (90, (105, 105)), (frames, (100, 100))]),
        opacity=Keys([(0, 45), (90, 90), (frames, 45)]),
    )
    return composition("guest", frames, [person, ring])


# name, builder, loops, has parts named "Tint"
CATALOG = (
    ("success", success, False, True),
    ("face-scan", face_scan, True, True),
    ("beam-incoming", beam_incoming, False, True),
    ("beam-sending", beam_sending, True, True),
    ("presence-pulse", presence_pulse, True, True),
    ("timer-done", timer_done, True, True),
    ("pairing", pairing, True, True),
    ("hello", hello, False, False),
    ("listening", listening, True, True),
    ("locked", locked, False, True),
    ("guest", guest, True, True),
)


def validate(node, frames, where):
    """Keyframes must be ordered and inside the composition, or players disagree on the result."""
    if isinstance(node, dict):
        if "nm" in node:
            where = where + "/" + node["nm"]
        if node.get("a") == 1:
            times = [key["t"] for key in node["k"]]
            assert times == sorted(set(times)), "%s: keyframes out of order: %s" % (where, times)
            assert 0 <= times[0] and times[-1] <= frames, "%s: keyframes outside 0...%d" % (where, frames)
        for value in node.values():
            validate(value, frames, where)
    elif isinstance(node, list):
        for value in node:
            validate(value, frames, where)


def render(builder):
    document = builder()
    validate(document["layers"], document["op"], document["nm"])
    return json.dumps(document, separators=(",", ":"), ensure_ascii=True) + "\n"


def main(arguments):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    here = os.path.dirname(os.path.abspath(__file__))
    default_output = os.path.join(here, "..", "Sources", "HomePadAnimationsCore", "Resources")
    parser.add_argument("--output", default=default_output, help="directory for the JSON files")
    parser.add_argument("--check", action="store_true", help="compare with the files on disk, write nothing")
    parser.add_argument("--list", action="store_true", help="print the catalog, write nothing")
    options = parser.parse_args(arguments)
    output = os.path.normpath(options.output)

    if options.list:
        for name, builder, loops, tintable in CATALOG:
            print("%-16s %4d frames  %-5s %s" % (
                name, builder()["op"], "loop" if loops else "once", "tint" if tintable else "fixed",
            ))
        return 0

    stale = []
    for name, builder, _, _ in CATALOG:
        target = os.path.join(output, name + ".json")
        text = render(builder)
        if options.check:
            try:
                with open(target, "r", encoding="utf-8") as handle:
                    current = handle.read()
            except FileNotFoundError:
                current = None
            if current != text:
                stale.append(name)
            continue
        os.makedirs(output, exist_ok=True)
        with open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("wrote %s (%d bytes)" % (os.path.relpath(target), len(text)))

    if options.check:
        if stale:
            print("out of date: " + ", ".join(stale), file=sys.stderr)
            print("run: python3 Tools/generate_animations.py", file=sys.stderr)
            return 1
        print("all %d animations match the generator" % len(CATALOG))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
