#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import zipfile
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('official_lite_stage', Path(__file__).with_name('stage-official-lite.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
package = Path(sys.argv[1]).resolve()
passed = []
with tempfile.TemporaryDirectory(prefix='official-lite-stage-test-') as temporary:
    root = Path(temporary)
    wrong = root / 'wrong.zip'
    wrong.write_bytes(b'not the pinned official package')
    try:
        module.stage(wrong, root / 'wrong-output')
        raise AssertionError('wrong hash accepted')
    except ValueError:
        assert not (root / 'wrong-output').exists()
        passed.append('wrong bytes refused before output creation')
    existing = root / 'existing-profile'
    existing.mkdir()
    (existing / 'keep.txt').write_bytes(b'user data must survive')
    try:
        module.stage(package, existing)
        raise AssertionError('existing profile accepted')
    except FileExistsError:
        assert (existing / 'keep.txt').read_bytes() == b'user data must survive'
        assert len(list(existing.iterdir())) == 1
        passed.append('existing profile refused and preserved')
    stage = root / 'new-bundle'
    result = module.stage(package, stage)
    with zipfile.ZipFile(package) as archive:
        for item in archive.infolist():
            if not item.is_dir():
                assert stage.joinpath(*Path(item.filename).parts).read_bytes() == archive.read(item)
        expected = {i.filename for i in archive.infolist() if not i.is_dir()}
    actual = {p.relative_to(stage).as_posix() for p in stage.rglob('*') if p.is_file()}
    assert actual == expected
    assert result['modifiedFiles'] == [] and result['addedFiles'] == []
    assert result['nativeHostCompatibilityVerified'] is False
    passed.append('every official file unchanged; no custom bootstrap, config seed or extra files')
print(json.dumps(dict(passed=passed, count=len(passed), stagedFiles=result['stagedFiles'],
    nativeHostCompatibilityVerified=False), indent=2))
