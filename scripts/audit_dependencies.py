"""Check pinned pub archives and publish the advisory evidence; never install code."""
import concurrent.futures
import datetime
import json
from pathlib import Path
import re
import urllib.request


def read_json(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)


def check(package):
    name, version, sha = package
    root = 'https://pub.dev/api/packages/' + name
    release = read_json(root + '/versions/' + version)
    advisories = read_json(root + '/advisories')
    if release['archive_sha256'] != sha:
        raise RuntimeError('Archive hash mismatch for ' + name)
    active = [item for item in advisories['advisories'] if not item.get('withdrawn')]
    if active:
        raise RuntimeError('Manual advisory assessment required for ' + name + ': ' + json.dumps(active))
    spec = release['pubspec']
    return {'name': name, 'version': version, 'archiveSha256': sha,
            'repository': spec.get('repository'), 'homepage': spec.get('homepage'),
            'advisories': advisories, 'metadataUrl': root + '/versions/' + version}


lock = Path('pubspec.lock').read_text()
packages = []
for name, block in re.findall(r'^  ([a-zA-Z0-9_]+):\n(.*?)(?=^  [a-zA-Z0-9_]+:|^sdks:|\Z)', lock, re.S | re.M):
    if 'source: hosted' not in block:
        continue
    version = re.search(r'    version: "([^"]+)"', block).group(1)
    sha = re.search(r'      sha256: "?([a-f0-9]+)', block).group(1)
    packages.append((name, version, sha))
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
    results = list(executor.map(check, packages))
Path('evidence').mkdir(exist_ok=True)
Path('evidence/dependencies.json').write_text(json.dumps({
    'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'packages': results,
    'installNotes': 'Metadata and advisories checked against pub.dev; package resolution is performed separately. No install scripts are run by this audit. Windows plugin CMake files inspected: local compilation only; screen_retriever example-only GoogleTest FetchContent is disabled in this app.'
}, indent=2) + '\n')
print(f'Verified {len(results)} pinned pub archives; no active advisories reported.')
