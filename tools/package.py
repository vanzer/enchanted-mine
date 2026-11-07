"""Build a shaderpack ZIP without changing source files."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
root = Path(__file__).resolve().parents[1]
out = root / "dist" / "EnchantedMine.zip"
out.parent.mkdir(exist_ok=True)
with ZipFile(out, "w", ZIP_DEFLATED) as archive:
    for path in sorted((root / "shaders").rglob("*")):
        if path.is_file():
            # Stable timestamps and permissions make the published ZIP reproducible.
            entry = ZipInfo(path.relative_to(root).as_posix(), (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, path.read_bytes(), compress_type=ZIP_DEFLATED)
print(out)
