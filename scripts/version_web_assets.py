#!/usr/bin/env python3
"""Give Flutter startup scripts a content version after `flutter build web`."""

import hashlib
from pathlib import Path
import re
import sys


def version_assets(directory: Path) -> None:
    token = hashlib.sha256((directory / 'main.dart.js').read_bytes()).hexdigest()
    files = {
        'index.html': (r'src="flutter_bootstrap\.js(?:\?[^\"]*)?"',
                       f'src="flutter_bootstrap.js?v={token}"'),
        'flutter_bootstrap.js': (
            r'"mainJsPath"\s*:\s*"main\.dart\.js(?:\?[^\"]*)?"',
            f'"mainJsPath":"main.dart.js?v={token}"',
        ),
    }
    updates = {}
    for name, (pattern, replacement) in files.items():
        target = directory / name
        content, count = re.subn(pattern, lambda _: replacement, target.read_text())
        if count != 1:
            raise ValueError(f'{name}: expected one Flutter startup reference, found {count}')
        updates[target] = content
    for target, content in updates.items():
        target.write_text(content)
    print(f'Web startup asset version: {token[:12]}')


if __name__ == '__main__':
    version_assets(Path(sys.argv[1]))
