import pathlib, tempfile, unittest, zipfile
from unittest.mock import patch
import prepare_av1_apk as recipe


class AndroidAv1RecipeTests(unittest.TestCase):
    def test_unknown_binary_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Unknown VR scene'):
            recipe.patch_scene(b'video/hevc\0')

    def test_selector_patch_keeps_size_and_surrounding_bytes(self):
        data = bytearray(b'\0' * (recipe.MIME_OFFSET + 40))
        data[:6] = b'\x7fELF\x02\x01'
        data[18:20] = (183).to_bytes(2, 'little')
        data[recipe.MIME_OFFSET:recipe.MIME_OFFSET+11] = b'video/hevc\0'
        expected = bytes(data).replace(b'video/hevc\0', b'video/av01\0')
        with patch.object(recipe, 'SCENE_SHA', recipe.digest(data)), patch.object(recipe, 'PATCHED_SHA', recipe.digest(expected)):
            result = recipe.patch_scene(bytes(data))
            self.assertEqual(result, expected)
            self.assertEqual(len(result), len(data))
            self.assertEqual(sum(a != b for a, b in zip(result, data)), 4)
            data[recipe.MIME_OFFSET] = 0
            with patch.object(recipe, 'SCENE_SHA', recipe.digest(data)):
                with self.assertRaisesRegex(ValueError, 'selector layout'):
                    recipe.patch_scene(bytes(data))

    def test_original_and_existing_output_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as root:
            original = pathlib.Path(root) / 'original.apk'
            original.write_bytes(b'original')
            for destination in (original, pathlib.Path(root) / 'existing.apk'):
                destination.write_bytes(b'original')
                with self.assertRaisesRegex(ValueError, 'new output'):
                    recipe.prepare(original, destination)
                self.assertEqual(destination.read_bytes(), b'original')

    def test_repacked_apk_preserves_entries_and_drops_stale_signatures(self):
        with tempfile.TemporaryDirectory() as root:
            original = pathlib.Path(root) / 'original.apk'
            output = pathlib.Path(root) / 'candidate.apk'
            with zipfile.ZipFile(original, 'w') as archive:
                archive.writestr(recipe.SCENE_PATH, b'original-scene')
                archive.writestr('classes.dex', b'unchanged')
                archive.writestr('META-INF/CERT.RSA', b'stale-signature')
            with patch.object(recipe, 'APK_SHA', recipe.digest(original.read_bytes())), patch.object(recipe, 'PATCHED_SHA', recipe.digest(b'patched-scene')), patch.object(recipe, 'patch_scene', return_value=b'patched-scene'):
                report = recipe.prepare(original, output)
            self.assertFalse(report['hardware_validated'])
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read('classes.dex'), b'unchanged')
                self.assertEqual(archive.read(recipe.SCENE_PATH), b'patched-scene')
                self.assertNotIn('META-INF/CERT.RSA', archive.namelist())
    def test_signature_filter_preserves_application_metadata(self):
        for name in ('META-INF/CERT.RSA', 'META-INF/CERT.SF', 'META-INF/MANIFEST.MF'):
            self.assertTrue(recipe.is_signature(name))
        self.assertFalse(recipe.is_signature('META-INF/services/provider'))
        self.assertFalse(recipe.is_signature('AndroidManifest.xml'))


if __name__ == '__main__':
    unittest.main()
