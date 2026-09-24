"""Windows-only regression checks; no Flutter build, real APK deletion or device use.
Run: python tool/test_build_apk.py
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / 'tool' / 'build-apk-tools.ps1'
BATCH = ROOT / 'build-apk.bat'

@unittest.skipUnless(os.name == 'nt', 'requires Windows PowerShell and cmd.exe')
class BuildApkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="apk-test space's-")
        self.root = Path(self.temp.name)
        self.dist = self.root / 'dist'
        self.dist.mkdir()
        (self.root / 'pubspec.yaml').write_text('version: 0.9.0+94\n', encoding='utf-8')
        # Preflight enforces Flutter's minimum toolchain versions, so every
        # isolated project needs the files those versions are read from.
        (self.root / 'android' / 'gradle' / 'wrapper').mkdir(parents=True)
        (self.root / 'android' / 'settings.gradle.kts').write_text(
            'plugins {\n'
            '    id("com.android.application") version "8.13.0" apply false\n'
            '    id("org.jetbrains.kotlin.android") version "2.2.20" apply false\n'
            '}\n', encoding='utf-8')
        (self.root / 'android' / 'gradle' / 'wrapper' / 'gradle-wrapper.properties').write_text(
            'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-all.zip\n', encoding='utf-8')
        self.apk = self.root / 'source.apk'
        self.apk.write_bytes(b'isolated fixture, not an installable APK')
        self.result = self.root / 'publish.env'

    def tearDown(self):
        self.temp.cleanup()

    def helper(self, action='Publish', *args, result=None):
        command = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(HELPER), '-Action', action, '-ProjectRoot', str(self.root)]
        if action == 'Publish':
            command += ['-ApkPath', str(self.apk), '-ResultFile', str(result or self.result)]
        return subprocess.run(command + list(args), capture_output=True, text=True, errors='replace', timeout=45)

    def pair(self, version, stamp, data=b'history'):
        p = self.dist / f'nexus-agent-{version}-{stamp}.apk'
        p.write_bytes(data)
        Path(str(p)+'.sha256').write_text(hashlib.sha256(data).hexdigest()+'\n')
        return p

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_publish_retention_preserves_rollback_and_unknown(self):
        rollback = self.pair('0.8.9_93', '20260918-071233')
        for i in range(5):
            self.pair('0.9.0_94', f'20260920-01000{i}')
        unknown = self.dist / 'important.apk'
        unknown.write_bytes(b'keep unknown')
        invalid = self.pair('0.9.0_94', '20260919-000000')
        Path(str(invalid)+'.sha256').write_text('0'*64)
        self.assert_ok(self.helper('Publish', '-Keep', '3'))
        self.assertTrue(rollback.exists())
        self.assertTrue(unknown.exists())
        self.assertTrue(invalid.exists())
        recognized = [p for p in self.dist.glob('nexus-agent-*.apk') if p.name != 'nexus-agent-latest.apk' and p != invalid]
        self.assertEqual(len(recognized), 3)
        latest = self.dist / 'nexus-agent-latest.apk'
        self.assertEqual(latest.read_bytes(), self.apk.read_bytes())
        self.assertEqual(Path(str(latest)+'.sha256').read_text().strip(), hashlib.sha256(self.apk.read_bytes()).hexdigest())

    def test_keep_all_and_unique_names(self):
        for _ in range(4):
            self.assert_ok(self.helper('Publish', '-KeepAll'))
        self.assertEqual(len(list(self.dist.glob('*.apk'))), 5)
        self.assertEqual(len(list(self.dist.glob('.publish-*'))), 0)

    def test_publish_failure_restores_previous_latest_and_does_not_prune(self):
        self.assert_ok(self.helper())
        latest = self.dist / 'nexus-agent-latest.apk'
        before = latest.read_bytes()
        sidecar = Path(str(latest)+'.sha256').read_bytes()
        history = self.pair('0.8.9_93', '20200101-000000')
        self.apk.write_bytes(b'new package')
        failed = self.helper(result=self.root / 'missing-parent' / 'publish.env')
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(latest.read_bytes(), before)
        self.assertEqual(Path(str(latest)+'.sha256').read_bytes(), sidecar)
        self.assertTrue(history.exists())
        self.assertEqual(len(list(self.dist.glob('.publish-*'))), 0)

    def test_empty_apk_refused(self):
        self.apk.write_bytes(b'')
        self.assertNotEqual(self.helper().returncode, 0)
        self.assertFalse((self.dist / 'nexus-agent-latest.apk').exists())

    def test_preflight_configured_keystore_and_version_mismatch(self):
        android = self.root / 'android'
        (android / 'app').mkdir(parents=True)
        (android / 'app' / 'custom-release.jks').write_bytes(b'fixture')
        (android / 'key.properties').write_text('storeFile=custom-release.jks\nstorePassword=DO_NOT_PRINT\nkeyPassword=DO_NOT_PRINT\nkeyAlias=fixture\n')
        sdk = self.root / 'sdk'
        (sdk / 'platforms' / 'android-37').mkdir(parents=True)
        (sdk / 'platforms' / 'android-37' / 'android.jar').write_bytes(b'fixture')
        (sdk / 'build-tools').mkdir()
        (android / 'local.properties').write_text('sdk.dir='+sdk.as_posix()+'\n')
        gradle = android / 'app' / 'build.gradle.kts'
        gradle.write_text('versionName = "0.9.0"\ncompileSdk = 37\n')
        result = self.helper('Preflight')
        self.assert_ok(result)
        self.assertNotIn('DO_NOT_PRINT', result.stdout + result.stderr)
        (sdk / 'platforms' / 'android-37').rename(sdk / 'platforms' / 'android-37.0')
        self.assert_ok(self.helper('Preflight'))
        gradle.write_text('versionName = "0.8.9"\ncompileSdk = 37\n')
        self.assertNotEqual(self.helper('Preflight').returncode, 0)

    def test_batch_end_to_end_with_fake_flutter_and_failure(self):
        # Exercise real cmd/PowerShell orchestration, but no Flutter/Gradle or device work.
        shutil.copy2(BATCH, self.root / 'build-apk.bat')
        (self.root / 'tool').mkdir()
        shutil.copy2(HELPER, self.root / 'tool' / HELPER.name)
        android = self.root / 'android'
        (android / 'app').mkdir(parents=True)
        (android / 'app' / 'custom.jks').write_bytes(b'fixture')
        (android / 'key.properties').write_text('storeFile=custom.jks\nstorePassword=fixture\nkeyPassword=fixture\nkeyAlias=fixture\n')
        (android / 'app' / 'build.gradle.kts').write_text('versionName = "0.9.0"\ncompileSdk = 37\n')
        (android / 'gradlew.bat').write_text('@exit /b 99\n')
        sdk = self.root / 'sdk'
        (sdk / 'platforms' / 'android-37.0').mkdir(parents=True)
        (sdk / 'platforms' / 'android-37.0' / 'android.jar').write_bytes(b'fixture')
        (sdk / 'build-tools').mkdir()
        (android / 'local.properties').write_text('sdk.dir='+sdk.as_posix()+'\n')
        (self.root / 'pubspec.lock').write_text('fixture')
        fake = self.root / 'fake-flutter.bat'
        fake.write_text('@echo off\nif "%1"=="pub" exit /b 0\nif "%FAKE_BUILD_EXIT%"=="7" exit /b 7\nif not exist "build\\app\\outputs\\flutter-apk" mkdir "build\\app\\outputs\\flutter-apk"\necho fake signed APK fixture> "build\\app\\outputs\\flutter-apk\\app-release.apk"\nexit /b 0\n')
        env = {**os.environ, 'CI':'true', 'FLUTTER_BIN':str(fake)}
        command = ['cmd.exe','/d','/c','call',str(self.root / 'build-apk.bat'),'--online','--keep-all','--no-pause','--no-open']
        good = subprocess.run(command, env=env, capture_output=True, text=True, errors='replace', timeout=60)
        self.assert_ok(good)
        latest = self.dist / 'nexus-agent-latest.apk'
        before = latest.read_bytes()
        self.assertTrue(list((self.root / 'artifacts' / 'build-apk').glob('*.log')))
        self.assertFalse((self.root / 'artifacts' / 'build-apk' / '.lock').exists())
        failed = subprocess.run(command, env={**env,'FAKE_BUILD_EXIT':'7'}, capture_output=True, text=True, errors='replace', timeout=60)
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(latest.read_bytes(), before)
        self.assertEqual(len(list(self.dist.glob('*.apk'))), 2)
        self.assertFalse((self.root / 'artifacts' / 'build-apk' / '.lock').exists())

    def test_fast_build_does_not_publish_or_touch_dist(self):
        # --fast must produce a local-only APK: no publication, no retention,
        # no replacement of the stable latest package.
        shutil.copy2(BATCH, self.root / 'build-apk.bat')
        (self.root / 'tool').mkdir()
        shutil.copy2(HELPER, self.root / 'tool' / HELPER.name)
        android = self.root / 'android'
        (android / 'app').mkdir(parents=True)
        (android / 'app' / 'custom.jks').write_bytes(b'fixture')
        (android / 'key.properties').write_text('storeFile=custom.jks\nstorePassword=fixture\nkeyPassword=fixture\nkeyAlias=fixture\n')
        (android / 'app' / 'build.gradle.kts').write_text('versionName = "0.9.0"\ncompileSdk = 37\n')
        (android / 'gradlew.bat').write_text('@exit /b 99\n')
        sdk = self.root / 'sdk'
        (sdk / 'platforms' / 'android-37.0').mkdir(parents=True)
        (sdk / 'platforms' / 'android-37.0' / 'android.jar').write_bytes(b'fixture')
        (sdk / 'build-tools').mkdir()
        (android / 'local.properties').write_text('sdk.dir='+sdk.as_posix()+'\n')
        (self.root / 'pubspec.lock').write_text('fixture')
        fake = self.root / 'fake-flutter.bat'
        fake.write_text('@echo off\nif "%1"=="pub" exit /b 0\nif not exist "build\\app\\outputs\\flutter-apk" mkdir "build\\app\\outputs\\flutter-apk"\necho fake fast APK fixture> "build\\app\\outputs\\flutter-apk\\app-release.apk"\nexit /b 0\n')
        sentinel = self.dist / 'nexus-agent-latest.apk'
        sentinel.write_bytes(b'stable release fixture')
        Path(str(sentinel)+'.sha256').write_text('stable')
        env = {**os.environ, 'CI':'true', 'FLUTTER_BIN':str(fake)}
        command = ['cmd.exe','/d','/c','call',str(self.root / 'build-apk.bat'),'--fast','--online','--no-pause','--no-open']
        result = subprocess.run(command, env=env, capture_output=True, text=True, errors='replace', timeout=60)
        self.assert_ok(result)
        self.assertIn('local-only build', result.stdout)
        self.assertEqual(sentinel.read_bytes(), b'stable release fixture')
        self.assertEqual(Path(str(sentinel)+'.sha256').read_text(), 'stable')
        self.assertEqual(list(self.dist.glob('*.apk')), [sentinel])
        self.assertFalse((self.root / 'artifacts' / 'build-apk' / '.lock').exists())

    def test_batch_help_and_early_validation_do_not_build(self):
        for args, expected in [(['--help'], 0), (['--bad-option'], 1), (['--offline','--online'], 1), (['--clean'], 1), (['--keep','1'], 1), (['--keep','abc'], 1), (['--keep'], 1)]:
            with self.subTest(args=args):
                result = subprocess.run(['cmd.exe','/d','/c','call',str(BATCH),*args], env={**os.environ,'CI':'true'}, capture_output=True, text=True, errors='replace', timeout=30)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

if __name__ == '__main__':
    unittest.main(verbosity=2)
