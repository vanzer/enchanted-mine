#!/usr/bin/env python3
"""Validate Iris shader sources and the packaged archive.

Requires glslangValidator (or glslang) on PATH. This approximates Iris's
absolute include expansion and built-in format constants; it cannot simulate
Iris's rendering pipeline or verify the resulting image.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile, BadZipFile

ROOT = Path(__file__).resolve().parents[1]
SHADERS = ROOT / "shaders"
INCLUDE = re.compile(r'^\s*#include\s+["<]([^">]+)[">]\s*(?://.*)?$', re.MULTILINE)
OPTION = re.compile(r'^(?P<prefix>\s*(?:#define\s+|const\s+(?:int|float)\s+))(?P<name>[A-Za-z_]\w*)(?P<assign>\s*(?:=\s*)?)(?P<value>[-+\w.]+)(?P<end>\s*;?\s*//\s*\[(?P<choices>[^]\n]+)\].*)$', re.MULTILINE)
BOOLEAN = re.compile(r'^(?P<indent>[ \t]*)(?P<disabled>//[ \t]*)?#define[ \t]+(?P<name>[A-Za-z_]\w*)[ \t]*(?://[^\n]*)?$', re.MULTILINE)
VERSION = re.compile(r'^\s*#version\s+\d+.*$', re.MULTILINE)


def expand(path: Path, stack: tuple[Path, ...] = ()) -> str:
    path = path.resolve()
    if not path.is_relative_to(SHADERS.resolve()):
        raise ValueError(f"include escapes shader directory: {path}")
    if path in stack:
        raise ValueError(f"include cycle: {' -> '.join(str(p) for p in (*stack, path))}")
    if not path.is_file():
        raise ValueError(f"missing shader include: {path}")
    source = path.read_text(encoding="utf-8")
    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        target = SHADERS / name.lstrip('/') if name.startswith('/') else path.parent / name
        return '\n' + expand(target, (*stack, path)) + '\n'
    return INCLUDE.sub(replace, source)


def validate_archive() -> None:
    subprocess.run([sys.executable, str(ROOT / 'tools/package.py')], check=True, stdout=subprocess.DEVNULL)
    archive = ROOT / 'dist/EnchantedMine.zip'
    expected = {str(p.relative_to(ROOT)): p.read_bytes() for p in SHADERS.rglob('*') if p.is_file()}
    try:
        with ZipFile(archive) as z:
            names = z.namelist()
            if len(names) != len(set(names)) or set(names) != set(expected):
                raise ValueError('archive file list differs from shaders directory')
            if z.testzip() is not None:
                raise ValueError('archive has a corrupt member')
            for name, content in expected.items():
                if z.read(name) != content:
                    raise ValueError(f'archive content differs: {name}')
    except BadZipFile as exc:
        raise ValueError(f'invalid archive: {exc}') from exc
    print(f'Archive: {len(expected)} files match shader sources')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validator', help='path to glslangValidator or glslang')
    args = parser.parse_args()
    compiler = args.validator or shutil.which('glslangValidator') or shutil.which('glslang')
    if not compiler:
        parser.error('install glslangValidator or pass --validator PATH')
    entries = sorted(SHADERS.rglob('*.vsh')) + sorted(SHADERS.rglob('*.fsh'))
    # Include libraries are not independently compilable shader programs.
    entries = [p for p in entries if 'lib' not in p.relative_to(SHADERS).parts]
    if not entries:
        raise ValueError('no shader entry points found')
    pairs = {}
    for path in entries:
        pairs.setdefault(path.with_suffix(''), {})[path.suffix] = path
    missing = [str(k.relative_to(SHADERS)) for k, v in pairs.items() if set(v) != {'.vsh', '.fsh'}]
    if missing:
        raise ValueError('missing vertex or fragment stage: ' + ', '.join(missing))
    # Program-entry switches (TERRAIN, WATER) are not user options. Gather
    # bare boolean defines only from shared GLSL libraries, excluding guards.
    boolean_names = set()
    for library in (SHADERS / 'lib').rglob('*.glsl'):
        source = library.read_text(encoding='utf-8')
        for match in BOOLEAN.finditer(source):
            name = match.group('name')
            if not re.search(r'^\s*#ifndef\s+' + re.escape(name) + r'\b', source, re.MULTILINE):
                boolean_names.add(name)
    profiles = {}
    properties = SHADERS / 'shaders.properties'
    if properties.exists():
        for line in properties.read_text(encoding='utf-8').splitlines():
            if line.startswith('profile.') and '=' in line:
                key, tokens = line.split('=', 1)
                overrides = {}
                for token in tokens.split():
                    if ':' in token:
                        option, value = token.split(':', 1)
                    else:
                        option, value = token.lstrip('!'), ('false' if token.startswith('!') else 'true')
                    overrides[option] = value
                profiles[key] = overrides
    all_options = {}
    failures = []
    configurations = 0
    with tempfile.TemporaryDirectory(prefix='enchanted-glsl-') as tmp:
        temp = Path(tmp)
        for name, stages in sorted(pairs.items()):
            sources = {}
            options = {}
            for suffix in ('.vsh', '.fsh'):
                entry = stages[suffix]
                source = expand(entry)
                versions = list(VERSION.finditer(source))
                if len(versions) != 1 or source[:versions[0].start()].strip():
                    raise ValueError(f'{entry}: expected one #version as first directive')
                # Iris defines texture format tokens during shader preprocessing.
                version = versions[0]
                sources[suffix] = source[:version.end()] + '\n#define RGBA16F 34842\n' + source[version.end():]
                for option in OPTION.finditer(source):
                    values = option.group('choices').split()
                    if option.group('value') not in values:
                        raise ValueError(f"{entry}: default for {option.group('name')} is not an allowed value")
                    previous = options.setdefault(option.group('name'), values)
                    if previous != values:
                        raise ValueError(f"conflicting choices for {option.group('name')}")
            booleans = {match.group('name') for source in sources.values()
                        for match in BOOLEAN.finditer(source) if match.group('name') in boolean_names}
            for option in booleans:
                options[option] = ['false', 'true']
            all_options.update(options)
            # Check default, then the minimum and maximum allowed values of each
            # option separately. This covers code switches and loop boundaries.
            variants = [('default', {})]
            for option, values in options.items():
                for value in dict.fromkeys((values[0], values[-1])):
                    variants.append((f'{option}={value}', {option: value}))
            for profile, overrides in profiles.items():
                applicable = {key: value for key, value in overrides.items() if key in options}
                for option, value in applicable.items():
                    if value not in options[option]:
                        raise ValueError(f'{profile}: invalid value {value} for {option}')
                if applicable:
                    variants.append((profile, applicable))
            for label, overrides in variants:
                files = []
                for suffix, ext in [('.vsh', '.vert'), ('.fsh', '.frag')]:
                    def substitute(match: re.Match[str]) -> str:
                        value = overrides.get(match.group('name'), match.group('value'))
                        return match.group('prefix') + match.group('name') + match.group('assign') + value + match.group('end')
                    output = temp / (name.name + ext)
                    def substitute_boolean(match: re.Match[str]) -> str:
                        option = match.group('name')
                        if option not in overrides:
                            return match.group(0)
                        enabled = overrides[option] == 'true'
                        return match.group('indent') + ('' if enabled else '//') + '#define ' + option
                    source = OPTION.sub(substitute, sources[suffix])
                    output.write_text(BOOLEAN.sub(substitute_boolean, source), encoding='utf-8')
                    files.append(str(output))
                result = subprocess.run([compiler, '-l', *files], text=True, capture_output=True)
                configurations += 1
                if result.returncode:
                    failures.append((f'{name.relative_to(SHADERS)} ({label})', result.stdout + result.stderr))
            print(f'GLSL: {name.relative_to(SHADERS)} checked ({len(variants)} configurations)')
    print(f'GLSL: {configurations} linked configurations checked')
    for profile, overrides in profiles.items():
        unknown = set(overrides) - set(all_options)
        if unknown:
            raise ValueError(f'{profile}: unknown settings: {", ".join(sorted(unknown))}')
    if failures:
        for name, output in failures:
            print(f'GLSL: {name} FAILED\n{output}', file=sys.stderr)
        return 1
    validate_archive()
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f'Validation failed: {exc}', file=sys.stderr)
        sys.exit(1)
