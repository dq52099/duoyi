#!/usr/bin/env python3
"""Give Flutter web shell, icon, and startup assets content versions after `flutter build web`."""

import hashlib
import json
from pathlib import Path
import re
import sys


def _sha256_file(path: Path) -> str:
    if not path.is_file():
        raise FileNotFoundError(f'Missing web asset: {path}')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _replace_matches(
    content: str,
    pattern: str,
    replacement_fn,
    label: str,
    *,
    min_count: int = 1,
    max_count: int | None = 1,
) -> str:
    updated, count = re.subn(pattern, replacement_fn, content)
    if count < min_count or (max_count is not None and count > max_count):
        expected = (
            f'at least {min_count}'
            if max_count is None
            else str(min_count)
            if min_count == max_count
            else f'{min_count}..{max_count}'
        )
        raise ValueError(f'{label}: expected {expected} match(es), found {count}')
    return updated


def _version_manifest(directory: Path) -> str:
    manifest_path = directory / 'manifest.json'
    data = json.loads(manifest_path.read_text(encoding='utf-8'))
    icons = data.get('icons')
    if not isinstance(icons, list) or not icons:
        raise ValueError('manifest.json: expected non-empty icons array')
    for icon in icons:
        src = icon.get('src')
        if not isinstance(src, str) or not src:
            raise ValueError('manifest.json: icon entry missing src')
        base_src = src.split('?', 1)[0]
        icon_token = _sha256_file(directory / base_src)
        icon['src'] = f'{base_src}?v={icon_token}'
    manifest_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=4) + '\n',
        encoding='utf-8',
    )
    return _sha256_file(manifest_path)


def version_assets(directory: Path) -> None:
    main_token = _sha256_file(directory / 'main.dart.js')
    manifest_token = _version_manifest(directory)
    favicon_png_token = _sha256_file(directory / 'favicon.png')
    favicon_ico_token = _sha256_file(directory / 'favicon.ico')
    icon_192_token = _sha256_file(directory / 'icons/Icon-192.png')
    apple_touch_token = _sha256_file(directory / 'icons/apple-touch-icon.png')
    resume_guard_token = _sha256_file(directory / 'web_resume_guard.js')

    index_path = directory / 'index.html'
    index_html = index_path.read_text(encoding='utf-8')
    index_html = _replace_matches(
        index_html,
        r'href="icons/apple-touch-icon\.png(?:\?[^"]*)?"',
        lambda _: f'href="icons/apple-touch-icon.png?v={apple_touch_token}"',
        'index.html apple-touch-icon',
    )
    index_html = _replace_matches(
        index_html,
        r'href="favicon\.png(?:\?[^"]*)?"',
        lambda _: f'href="favicon.png?v={favicon_png_token}"',
        'index.html favicon.png',
    )
    index_html = _replace_matches(
        index_html,
        r'href="favicon\.ico(?:\?[^"]*)?"',
        lambda _: f'href="favicon.ico?v={favicon_ico_token}"',
        'index.html favicon.ico',
    )
    index_html = _replace_matches(
        index_html,
        r'(href|src)="icons/Icon-192\.png(?:\?[^"]*)?"',
        lambda match: f'{match.group(1)}="icons/Icon-192.png?v={icon_192_token}"',
        'index.html icons/Icon-192.png',
        min_count=2,
        max_count=None,
    )
    index_html = _replace_matches(
        index_html,
        r'href="manifest\.json(?:\?[^"]*)?"',
        lambda _: f'href="manifest.json?v={manifest_token}"',
        'index.html manifest.json',
    )
    index_html = _replace_matches(
        index_html,
        r'src="web_resume_guard\.js(?:\?[^"]*)?"',
        lambda _: f'src="web_resume_guard.js?v={resume_guard_token}"',
        'index.html web_resume_guard.js',
    )
    index_html = _replace_matches(
        index_html,
        r'src="flutter_bootstrap\.js(?:\?[^"]*)?"',
        lambda _: f'src="flutter_bootstrap.js?v={main_token}"',
        'index.html flutter_bootstrap.js',
    )

    bootstrap_path = directory / 'flutter_bootstrap.js'
    bootstrap_js = _replace_matches(
        bootstrap_path.read_text(encoding='utf-8'),
        r'"mainJsPath"\s*:\s*"main\.dart\.js(?:\?[^"]*)?"',
        lambda _: f'"mainJsPath":"main.dart.js?v={main_token}"',
        'flutter_bootstrap.js mainJsPath',
    )

    index_path.write_text(index_html, encoding='utf-8')
    bootstrap_path.write_text(bootstrap_js, encoding='utf-8')
    print(
        f'Web assets versioned: app={main_token[:12]} '
        f'favicon_png={favicon_png_token[:12]} favicon_ico={favicon_ico_token[:12]}'
    )


if __name__ == '__main__':
    version_assets(Path(sys.argv[1]))
