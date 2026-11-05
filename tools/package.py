"""Build a reproducible shaderpack; reject unexpected files and symlinks."""
import os
from pathlib import Path
import tempfile
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

from shader_sources import shader_files, expand_shader


def build(root):
    root = Path(root).resolve()
    sources = shader_files(root / "shaders")
    for path in sources:
        if path.suffix in {".vsh", ".fsh", ".glsl"}:
            expand_shader(path, root / "shaders")
    files = list(sources)
    for name in ("README.md", "LICENSE"):
        path = root / name
        if path.is_symlink():
            raise ValueError(f"Symlinks are not allowed: {path}")
        if path.exists():
            if not path.is_file():
                raise ValueError(f"Expected a regular file: {path}")
            files.append(path)

    destination = root / "dist"
    if destination.is_symlink():
        raise ValueError(f"Symlinks are not allowed: {destination}")
    destination.mkdir(exist_ok=True)
    output = destination / "EnchantedMine.zip"
    if output.is_symlink():
        raise ValueError(f"Symlinks are not allowed: {output}")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination, suffix=".zip", delete=False) as handle:
            temporary = Path(handle.name)
        with ZipFile(temporary, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(files):
                info = ZipInfo(path.relative_to(root).as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = ZIP_DEFLATED
                archive.writestr(info, path.read_bytes())
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return output


if __name__ == "__main__":
    try:
        print(build(Path(__file__).resolve().parents[1]))
    except (ValueError, OSError) as error:
        raise SystemExit(f"Cannot build shaderpack: {error}") from error
