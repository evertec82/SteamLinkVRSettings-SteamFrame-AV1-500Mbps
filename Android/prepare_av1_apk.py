"""Prepare an unsigned, exact-build Android VR AV1 candidate from the user's APK.

Does not install anything. Requires zipalign and apksigner before installation.
Only the VR MediaCodec MIME selector changes; Remote Play is untouched.
"""
import argparse, copy, hashlib, json, pathlib, zipfile

APK_SHA = '7eb6e4b36dbdd420501be66e6577320b19e2576a36e872d3c31279860a4c1c47'
SCENE_PATH = 'lib/arm64-v8a/libvrlink_scene.so'
SCENE_SHA = '62529b46042c3616a9206188fb8e04c47a5374fdc50b914ba0c1a8fa101a1884'
PATCHED_SHA = '2d812a41644144cc22fe2805422de2ae75c31017752d1760cc8b6a241f116bc5'
MIME_OFFSET = 0x93b11


def digest(data):
    return hashlib.sha256(data).hexdigest()


def patch_scene(data):
    if digest(data) != SCENE_SHA:
        raise ValueError('Unknown VR scene library; this recipe requires the audited exact build')
    if data[:6] != b'\x7fELF\x02\x01' or int.from_bytes(data[18:20], 'little') != 183:
        raise ValueError('Expected AArch64 ELF64 library')
    if data.count(b'video/hevc\0') != 1 or data[MIME_OFFSET:MIME_OFFSET+11] != b'video/hevc\0':
        raise ValueError('VR decoder selector layout changed')
    patched = data[:MIME_OFFSET] + b'video/av01\0' + data[MIME_OFFSET+11:]
    if digest(patched) != PATCHED_SHA:
        raise ValueError('Patched scene fingerprint differs')
    return patched


def is_signature(name):
    upper = name.upper()
    return upper.startswith('META-INF/') and (upper.endswith(('.SF', '.RSA', '.DSA', '.EC')) or upper == 'META-INF/MANIFEST.MF')


def prepare(source, output):
    source, output = pathlib.Path(source), pathlib.Path(output)
    if source.resolve() == output.resolve() or output.exists():
        raise ValueError('Choose a new output APK; the original is never overwritten')
    if digest(source.read_bytes()) != APK_SHA:
        raise ValueError('Unknown APK build; refusing a guessed binary patch')
    with zipfile.ZipFile(source) as original:
        entries = original.infolist()
        if len({entry.filename for entry in entries}) != len(entries):
            raise ValueError('Duplicate APK entries are unsupported')
        patched = patch_scene(original.read(SCENE_PATH))
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(output.name + '.tmp')
        try:
            with zipfile.ZipFile(temporary, 'w') as result:
                for entry in entries:
                    if not is_signature(entry.filename):
                        data = patched if entry.filename == SCENE_PATH else original.read(entry)
                        result.writestr(copy.copy(entry), data)
            with zipfile.ZipFile(temporary) as result:
                if result.testzip() is not None:
                    raise ValueError('Candidate APK failed ZIP integrity check')
                for entry in entries:
                    if entry.filename == SCENE_PATH:
                        if digest(result.read(entry.filename)) != PATCHED_SHA:
                            raise ValueError('Candidate scene did not verify')
                    elif not is_signature(entry.filename) and original.read(entry) != result.read(entry.filename):
                        raise ValueError('Unexpected change outside VR decoder selector')
            temporary.rename(output)
        finally:
            temporary.unlink(missing_ok=True)
    return {'original_apk_sha256': APK_SHA, 'candidate_apk_sha256': digest(output.read_bytes()),
            'original_scene_sha256': SCENE_SHA, 'candidate_scene_sha256': PATCHED_SHA,
            'changed_entry': SCENE_PATH, 'changed_bytes': 4, 'mime': 'video/av01',
            'signed': False, 'installed': False, 'hardware_validated': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    args = parser.parse_args()
    report = prepare(args.apk, args.output)
    args.output.with_suffix('.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
