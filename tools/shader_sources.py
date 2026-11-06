"""Local shader source validation shared by the packager and GPU checks."""
from pathlib import Path
import re
import stat

ALLOWED_SUFFIXES = {".vsh", ".fsh", ".glsl", ".properties", ".lang"}
INCLUDE = re.compile(r'^\s*#include\s+"([^"\n]+)"\s*$', re.M)
MAX_INCLUDE_EXPANSIONS = 4096
MAX_SOURCE_BYTES = 4 * 1024 * 1024


def regular_source(path, root):
    path, root = Path(path).absolute(), Path(root).absolute()
    try:
        relative = path.relative_to(root)
    except ValueError:
        raise ValueError(f"Source escapes shader root: {path}") from None
    current = root
    for part in ("", *relative.parts):
        if part:
            if part in {".", ".."} or part.startswith(".") or "\\" in part:
                raise ValueError(f"Unexpected shader path: {path}")
            current /= part
        if current.is_symlink():
            raise ValueError(f"Symlinks are not allowed: {current}")
    if path.suffix not in ALLOWED_SUFFIXES or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"Unexpected shader file: {path}")
    return path


def shader_files(root):
    root = Path(root).absolute()
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"Expected a shader directory without symlinks: {root}")
    files = []

    def visit(directory):
        for path in sorted(directory.iterdir()):
            if path.is_symlink() or path.name.startswith("."):
                raise ValueError(f"Unexpected shader path: {path}")
            if path.is_dir():
                visit(path)
            else:
                files.append(regular_source(path, root))

    visit(root)
    if not files:
        raise ValueError("Shader directory is empty")
    vertices = {path.with_suffix("") for path in files if path.suffix == ".vsh" and path.parent == root}
    fragments = {path.with_suffix("") for path in files if path.suffix == ".fsh" and path.parent == root}
    if not vertices or vertices != fragments:
        raise ValueError("Each top-level shader program needs a vertex and fragment pair")
    return files


def expand_shader(path, root, settings=None):
    expansions = 0
    remaining_bytes = MAX_SOURCE_BYTES

    def expand(current, stack=()):
        nonlocal expansions, remaining_bytes
        current = regular_source(current, root)
        if current in stack or len(stack) >= 64:
            raise ValueError(f"Cyclic or excessively deep shader include: {current}")
        expansions += 1
        if expansions > MAX_INCLUDE_EXPANSIONS or current.stat().st_size > remaining_bytes:
            raise ValueError(f"Shader include expansion budget exceeded: {current}")
        content = current.read_bytes()
        remaining_bytes -= len(content)
        if remaining_bytes < 0:
            raise ValueError(f"Shader include expansion budget exceeded: {current}")

        def include(match):
            name = match[1]
            if "\\" in name or any(part in {"", ".", ".."} for part in name.lstrip("/").split("/")):
                raise ValueError(f"Invalid shader include: {name}")
            target = Path(root) / name[1:] if name.startswith("/") else current.parent / name
            return expand(target, (*stack, current))

        return INCLUDE.sub(include, content.decode("utf-8"))

    source = expand(path)
    for name, value in (settings or {}).items():
        source = re.sub(r"(#define\s+" + re.escape(name) + r")\s+\S+",
                        lambda match: match[1] + " " + str(value), source)
    return source
