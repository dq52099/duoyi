"""Bind an existing verified native asset cache; never copy or clear it.

Call under the project's verification guard before launching Java. Include the
returned files in the runner's checks before and after each command. Java still
creates and removes its own small per-process scratch directory under tmpRoot.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'evidence/theme-widget-resume-20261109-v898/native-asset-cache-683.json'
MANIFEST_SHA256 = '4cff465e33fa12d3938c8e148a3929dcdc0e8eef11ab86fbc700a1dd295c64f6'


def _plain(path):
    path = Path(path).absolute()
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise RuntimeError('Native cache symlink refused: ' + str(path))
    if not path.is_relative_to(ROOT / 'evidence') or not path.exists():
        raise RuntimeError('Existing repository native cache required')
    return path


def bind_existing_cache(expected, fingerprint):
    """Return tmpRoot after pinning jars, archive identity and every cache file."""
    manifest = _plain(MANIFEST)
    raw = manifest.read_bytes()
    if hashlib.sha256(raw).hexdigest() != MANIFEST_SHA256:
        raise RuntimeError('Reviewed native asset cache manifest changed')
    data = json.loads(raw)
    if data['schema'] != 1:
        raise RuntimeError('Unsupported native cache manifest')
    tmp = _plain(data['tmpRoot'])
    cache = _plain(data['cacheRoot'])
    if cache != tmp / 'robolectric-nativeruntime-assets':
        raise RuntimeError('Native cache root mismatch')
    for name, record in data['jars'].items():
        path = _plain(name)
        if (expected.get(name) != record['fingerprint'] or
                fingerprint(path) != record['fingerprint'] or
                path.stat().st_mtime_ns // 1000000 != record['mtimeMilliseconds']):
            raise RuntimeError('Native loader/archive identity changed: ' + name)
    archive = Path(data['archive'])
    identity = f'{archive}:{archive.stat().st_size}:{archive.stat().st_mtime_ns // 1000000}'
    key = hashlib.sha256(identity.encode()).hexdigest()[:32]
    if key != data['archiveKey']:
        raise RuntimeError('Native cache archive key changed')
    actual = set()
    for path in cache.rglob('*'):
        _plain(path)
        if path.is_file():
            actual.add(str(path))
    if actual != set(data['files']):
        raise RuntimeError('Native cache file inventory changed')
    for kind in ('fonts', 'icu', 'hyphen-data'):
        marker = cache / (kind + '-' + key) / '.complete'
        if marker.read_bytes() != b'':
            raise RuntimeError('Native cache completion marker changed')
    for name, value in data['files'].items():
        if fingerprint(Path(name)) != value:
            raise RuntimeError('Native cache bytes changed: ' + name)
        if name in expected and expected[name] != value:
            raise RuntimeError('Conflicting native cache fingerprint')
        expected[name] = value
    expected[str(manifest)] = fingerprint(manifest)
    expected[str(Path(__file__).resolve())] = fingerprint(Path(__file__))
    return tmp
