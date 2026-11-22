#!/usr/bin/env python3
"""Generate mask-aware painted ground models for paintable items.

The vanilla ground renderer does not apply a TINT mask to HandWeapon items that
have no world static model. This script copies the item's normal model and
rewrites its `world` attachment so the world-static renderer uses the same pose
as the vanilla weapon fallback.

The transformed attachment is:

    W' = W * R^-1        R = rotateXYZ(0, pi, pi/2)   (the engine's bWeaponFix)

The resulting model is named <prefix><Model>WorldPaint. The default prefix is
`TS_` (TeaStain); use `--prefix` to pick your own. Register the generated name
explicitly via the `worldPainted` option in TS_PaintStuff.registerPaintable; the
framework does not derive the name.

Examples:
    python3 scripts/gen_world_models.py Base.Crowbar Base.Screwdriver \
        --prefix TS_ \
        --mod-dir ../zomboid_paintableStuff_tools/paintableStuff_tools/Contents/mods/paintableStuffTools/42 \
        --out ../zomboid_paintableStuff_tools/paintableStuff_tools/Contents/mods/paintableStuffTools/42/media/scripts/tsPSToolsWorldModels.txt

    python3 scripts/gen_world_models.py Base.Pistol2 Base.Revolver_Short \
        --prefix ABC_ \
        --mod-dir ../zomboid_paintableStuff_weapons/paintableStuff_weapons/Contents/mods/paintableStuffWeapons/42 \
        --out ../zomboid_paintableStuff_weapons/paintableStuff_weapons/Contents/mods/paintableStuffWeapons/42/media/scripts/tsPSWeaponsWorldModels.txt

The output filename must be unique. If the same name is used in multiple mods, they will overwrite each other.

For model variants supplied by another mod (for example Visible Magazine Reloads' empty-magazine
models), pass its model script with --extra-model-script and the model names with --extra-model:

    python3 scripts/gen_world_models.py Base.AssaultRifle ... \
        --prefix TS_ \
        --extra-model-script /path/to/PZMagReload/42/media/scripts/PZMagReload_models.txt \
        --extra-model PZRA_M16_NoMag \
        --mod-dir ... --out ...
"""

from __future__ import annotations

import argparse
import math
import os
import re
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


Mat4 = list[list[float]]


def identity() -> Mat4:
    return [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


def mul(a: Mat4, b: Mat4) -> Mat4:
    out = [[0.0] * 4 for _ in range(4)]
    for r in range(4):
        for c in range(4):
            out[r][c] = sum(a[r][k] * b[k][c] for k in range(4))
    return out


def translate(x: float, y: float, z: float) -> Mat4:
    m = identity()
    m[0][3] = x
    m[1][3] = y
    m[2][3] = z
    return m


def scale(sx: float, sy: float, sz: float) -> Mat4:
    m = identity()
    m[0][0] = sx
    m[1][1] = sy
    m[2][2] = sz
    return m


def rotate_x(angle: float) -> Mat4:
    c, s = math.cos(angle), math.sin(angle)
    m = identity()
    m[1][1] = c
    m[1][2] = -s
    m[2][1] = s
    m[2][2] = c
    return m


def rotate_y(angle: float) -> Mat4:
    c, s = math.cos(angle), math.sin(angle)
    m = identity()
    m[0][0] = c
    m[0][2] = s
    m[2][0] = -s
    m[2][2] = c
    return m


def rotate_z(angle: float) -> Mat4:
    c, s = math.cos(angle), math.sin(angle)
    m = identity()
    m[0][0] = c
    m[0][1] = -s
    m[1][0] = s
    m[1][1] = c
    return m


def rotate_xyz(ax: float, ay: float, az: float) -> Mat4:
    return mul(mul(rotate_x(ax), rotate_y(ay)), rotate_z(az))


def rotate_xyz_degrees(ax: float, ay: float, az: float) -> Mat4:
    return rotate_xyz(math.radians(ax), math.radians(ay), math.radians(az))


def inverse_rigid(m: Mat4) -> Mat4:
    """Inverse of a rotation/translation matrix (no scale)."""
    r = [[m[r][c] for c in range(3)] for r in range(3)]
    t = [m[0][3], m[1][3], m[2][3]]
    rt = [[r[c][row] for c in range(3)] for row in range(3)]
    inv = identity()
    for row in range(3):
        for col in range(3):
            inv[row][col] = rt[row][col]
    for row in range(3):
        inv[row][3] = -sum(rt[row][k] * t[k] for k in range(3))
    return inv


def euler_xyz_degrees(m: Mat4) -> tuple[float, float, float]:
    cy = math.hypot(m[0][0], m[0][1])
    y = math.atan2(m[0][2], cy)
    if cy > 1e-9:
        x = math.atan2(-m[1][2], m[2][2])
        z = math.atan2(-m[0][1], m[0][0])
    else:
        x = math.atan2(m[2][1], m[1][1])
        z = 0.0
    return math.degrees(x), math.degrees(y), math.degrees(z)


R_FIX = rotate_xyz(0.0, math.pi, math.pi / 2.0)
R_FIX_INV = inverse_rigid(R_FIX)

# -- Parsing --

@dataclass
class Block:
    keyword: str
    name: str
    start: int
    end: int
    body: str


def find_blocks(text: str, keyword: str) -> list[Block]:
    pattern = re.compile(r"\b" + re.escape(keyword) + r"\s+([^\s{]+)\s*\{")
    blocks: list[Block] = []
    for match in pattern.finditer(text):
        name = match.group(1).strip()
        open_index = text.index("{", match.start())
        depth = 1
        index = open_index + 1
        while depth and index < len(text):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        if depth:
            raise ValueError(f"unclosed block for {keyword} {name}")
        blocks.append(Block(keyword, name, open_index, index - 1, text[open_index + 1 : index - 1]))
    return blocks


def find_field(body: str, field: str) -> str | None:
    match = re.search(r"(?im)^\s*" + re.escape(field) + r"\s*=\s*([^\n,}]+)", body)
    return match.group(1).strip() if match else None


def find_attachment(body: str, attachment_id: str) -> Block | None:
    for block in find_blocks(body, "attachment"):
        if block.name.lower() == attachment_id.lower():
            return block
    return None


def parse_xyz(value: str | None, default: tuple[float, float, float]) -> tuple[float, float, float]:
    if not value:
        return default
    parts = value.replace(",", " ").split()
    if len(parts) != 3:
        return default
    return float(parts[0]), float(parts[1]), float(parts[2])


def format_number(value: float) -> str:
    value = round(value, 6)
    if abs(value) < 1e-9:
        value = 0.0
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return text if text not in ("", "-0") else "0"


def format_xyz(values: Iterable[float]) -> str:
    return " ".join(format_number(v) for v in values)


# -- Game data --

@dataclass
class ModelInfo:
    name: str
    module: str
    body: str


@dataclass
class ItemInfo:
    name: str
    module: str
    models: list[str]
    world_static_model: str | None


class GameData:
    def __init__(self, game_dir: Path, extra_model_scripts: list[Path] | None = None) -> None:
        self.game_dir = game_dir
        self.models: dict[str, ModelInfo] = {}
        self.items: dict[str, ItemInfo] = {}
        self._load_models()
        for path in extra_model_scripts or []:
            self._load_models_file(path)
        self._load_items()

    def _script_files(self, folder: str) -> list[Path]:
        base = self.game_dir / "media" / "scripts" / "generated" / folder
        return sorted(base.glob("*.txt"))

    def _load_models_file(self, path: Path) -> None:
        text = path.read_text(encoding="utf-8", errors="ignore")
        modules = find_blocks(text, "module")
        for module_block in modules:
            for model_block in find_blocks(module_block.body, "model"):
                if model_block.name in self.models:
                    continue
                self.models[model_block.name] = ModelInfo(
                    model_block.name,
                    module_block.name,
                    textwrap.dedent(model_block.body).strip("\n"),
                )

    def _load_models(self) -> None:
        for path in self._script_files(""):
            if path.name.startswith("models"):
                self._load_models_file(path)

    def _load_items(self) -> None:
        for path in self._script_files("items"):
            text = path.read_text(encoding="utf-8", errors="ignore")
            modules = find_blocks(text, "module")
            for module_block in modules:
                for item_block in find_blocks(module_block.body, "item"):
                    if item_block.name in self.items:
                        continue
                    body = item_block.body
                    by_index = find_field(body, "WeaponSpritesByIndex")
                    if by_index:
                        models = [part.strip() for part in by_index.split(";") if part.strip()]
                    else:
                        models = []
                        for field in ("WeaponSprite", "StaticModel"):
                            value = find_field(body, field)
                            if value:
                                models = [value]
                                break
                    self.items[item_block.name] = ItemInfo(
                        item_block.name,
                        module_block.name,
                        models,
                        find_field(body, "WorldStaticModel"),
                    )

    def resolve_item(self, full_type: str) -> ItemInfo:
        name = full_type.split(".", 1)[1] if "." in full_type else full_type
        item = self.items.get(name)
        if item is None:
            raise KeyError(f"item not found: {full_type}")
        return item

# -- Model rewriting --

def compensate_world_attachment(body: str) -> tuple[str, list[str]]:
    """Replace/add the world attachment and return (body, warnings)."""
    warnings: list[str] = []
    world = find_attachment(body, "world")

    if world is not None:
        offset = parse_xyz(find_field(world.body, "offset"), (0.0, 0.0, 0.0))
        rotation = parse_xyz(find_field(world.body, "rotate"), (0.0, 0.0, 0.0))
        scale_value = parse_xyz(find_field(world.body, "scale"), (1.0, 1.0, 1.0))
        if abs(scale_value[0] - scale_value[1]) > 1e-9 or abs(scale_value[1] - scale_value[2]) > 1e-9:
            warnings.append("non-uniform world attachment scale; pose may be off")

        w = mul(mul(translate(*offset), rotate_xyz_degrees(*rotation)), scale(*scale_value))
        w_prime = mul(w, R_FIX_INV)
        new_rotation = euler_xyz_degrees(w_prime)
        new_block = (
            "attachment world\n"
            "{\n"
            f"    offset = {format_xyz(offset)},\n"
            f"    rotate = {format_xyz(new_rotation)},\n"
            "}"
        )
        if abs(scale_value[0] - 1.0) > 1e-9 or abs(scale_value[1] - 1.0) > 1e-9 or abs(scale_value[2] - 1.0) > 1e-9:
            new_block = new_block[:-1] + f"    scale = {format_xyz(scale_value)},\n" + "}"
    else:
        new_rotation = euler_xyz_degrees(R_FIX_INV)
        new_block = (
            "attachment world\n"
            "{\n"
            "    offset = 0 0 0,\n"
            f"    rotate = {format_xyz(new_rotation)},\n"
            "}"
        )
        warnings.append("model had no world attachment; added a compensating one")

    lines = body.splitlines()
    indent = "    "
    for line in lines:
        if line.strip():
            indent = line[: len(line) - len(line.lstrip())]
            break
    replacement = "\n".join(indent + line if line else line for line in new_block.splitlines())

    if world is not None:
        match = re.search(r"(?im)^[ \t]*attachment\s+world\s*\{", body)
        if not match:
            raise ValueError("world attachment was found but its text could not be located")
        start = match.start()
        end = world.end + 1
        body = body[:start] + replacement + body[end:]
    else:
        body = "\n" + replacement + "\n" + body.lstrip("\n")

    return body, warnings


def model_texture(body: str) -> str:
    texture = find_field(body, "texture")
    if texture:
        return texture
    mesh = find_field(body, "mesh")
    if not mesh:
        raise ValueError("model has neither texture nor mesh")
    return mesh


def mask_exists(game_dir: Path, mod_dir: Path | None, texture: str) -> bool:
    texture = texture[:-4] if texture.lower().endswith(".png") else texture
    relative = Path("media") / "textures" / (texture + "TINT.png")
    candidates = [game_dir / relative]
    if mod_dir is not None:
        candidates.insert(0, mod_dir / relative)
    return any(path.is_file() for path in candidates)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate painted ground models for paintable items.")
    parser.add_argument("items", nargs="+", help="Item full types, e.g. Base.Crowbar")
    parser.add_argument("--game-dir", default=os.environ.get("ZOMBOID_DIR"), help="Project Zomboid media root (defaults to ZOMBOID_DIR)")
    parser.add_argument("--mod-dir", default=None, help="Version dir of the consumer mod (contains media/), used for mask checks")
    parser.add_argument("--out", default="-", help="Output model script (default: stdout)")
    parser.add_argument("--module", default="Base", help="Output module (default: Base)")
    parser.add_argument(
        "--prefix",
        default="TS_",
        help="Generated model name prefix (default: TS_ for TeaStain; use your own, e.g. ABC_)",
    )
    parser.add_argument(
        "--extra-model-script",
        action="append",
        default=[],
        metavar="PATH",
        help="additional model script to read (repeatable), e.g. another mod's model file",
    )
    parser.add_argument(
        "--extra-model",
        action="append",
        default=[],
        metavar="NAME",
        help="additional model name to generate a world-paint model for (repeatable)",
    )
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9_]*", args.prefix):
        parser.error("--prefix may only contain letters, digits and underscores")

    if not args.game_dir:
        parser.error("--game-dir is required (or set ZOMBOID_DIR)")

    game_dir = Path(args.game_dir).expanduser().resolve()
    mod_dir = Path(args.mod_dir).expanduser().resolve() if args.mod_dir else None
    if not (game_dir / "media" / "scripts" / "generated").is_dir():
        parser.error(f"not a Project Zomboid media root: {game_dir}")

    extra_model_scripts = [Path(path).expanduser().resolve() for path in args.extra_model_script]
    for path in extra_model_scripts:
        if not path.is_file():
            parser.error(f"extra model script not found: {path}")

    game = GameData(game_dir, extra_model_scripts)
    modules: dict[str, list[str]] = {}
    seen_models: set[str] = set()
    failures = 0

    print(f"Game: {game_dir}", file=sys.stderr)
    if mod_dir:
        print(f"Mod:  {mod_dir}", file=sys.stderr)
    for path in extra_model_scripts:
        print(f"Extra model script: {path}", file=sys.stderr)
    print("", file=sys.stderr)

    def generate_model(label: str, model_name: str) -> bool:
        model = game.models.get(model_name)
        if model is None:
            print(f"ERROR {label}: model not found: {model_name}", file=sys.stderr)
            return False

        generated_name = f"{args.prefix}{model_name}WorldPaint"
        if generated_name in seen_models:
            return True
        seen_models.add(generated_name)

        body, warnings = compensate_world_attachment(model.body)
        texture = model_texture(body)
        has_mask = mask_exists(game_dir, mod_dir, texture)
        module = args.module or model.module
        modules.setdefault(module, []).append(
            f"    model {generated_name}\n"
            "    {\n"
            + textwrap.indent(textwrap.dedent(body).strip("\n"), "        ")
            + "\n    }"
        )

        status = "mask OK" if has_mask else "MISSING MASK"
        print(
            f"{label:24} {model_name:26} -> {generated_name:32} "
            f"texture={texture:42} {status}",
            file=sys.stderr,
        )
        for warning in warnings:
            print(f"    warning: {warning}", file=sys.stderr)
        return True

    for full_type in args.items:
        try:
            item = game.resolve_item(full_type)
        except KeyError as error:
            print(f"ERROR {full_type}: {error}", file=sys.stderr)
            failures += 1
            continue

        if item.world_static_model:
            print(f"SKIP  {full_type}: already has WorldStaticModel = {item.world_static_model}", file=sys.stderr)
            continue

        if not item.models:
            print(f"ERROR {full_type}: no WeaponSprite/WeaponSpritesByIndex/StaticModel", file=sys.stderr)
            failures += 1
            continue

        for model_name in item.models:
            if not generate_model(full_type, model_name):
                failures += 1

    for model_name in args.extra_model:
        if not generate_model(f"extra:{model_name}", model_name):
            failures += 1

    if failures:
        print(f"\n{failures} item(s) failed; output not written.", file=sys.stderr)
        return 1

    chunks = ["/* Generated by scripts/gen_world_models.py. Do not edit by hand. */\n"]
    for module, blocks in modules.items():
        chunks.append(f"module {module}\n{{\n")
        chunks.append("\n\n".join(blocks))
        chunks.append("\n}\n")
    output = "\n".join(chunks)

    if args.out == "-":
        sys.stdout.write(output)
    else:
        out_path = Path(args.out).expanduser()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output, encoding="utf-8")
        print(f"\nWrote {out_path}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
