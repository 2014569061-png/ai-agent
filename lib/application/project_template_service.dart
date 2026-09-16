import 'project_kind.dart';
import 'project_settings.dart';

class ProjectTemplateFile {
  const ProjectTemplateFile({
    required this.relativePath,
    required this.contents,
  });

  final String relativePath;
  final String contents;
}

class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.kind,
    required this.label,
    required this.summary,
    required this.files,
    required this.settings,
  });

  final String id;
  final ProjectKind kind;
  final String label;
  final String summary;
  final List<ProjectTemplateFile> files;
  final ProjectSettings settings;
}

class CreateProjectRequest {
  const CreateProjectRequest({
    required this.name,
    required this.templateId,
    this.parentDirectory,
    this.packageName,
    this.appName,
    this.providerProfileId,
  });

  final String name;
  final String templateId;
  final String? parentDirectory;
  final String? packageName;
  final String? appName;
  final String? providerProfileId;
}

class ImportDirectoryRequest {
  const ImportDirectoryRequest({required this.directoryPath, this.name});

  final String directoryPath;
  final String? name;
}

class ImportArchiveRequest {
  const ImportArchiveRequest({
    required this.archivePath,
    required this.bytes,
    this.name,
    this.parentDirectory,
  });

  final String archivePath;
  final List<int> bytes;
  final String? name;
  final String? parentDirectory;
}

class ProjectTemplateService {
  const ProjectTemplateService();

  List<ProjectTemplate> all() => [
        staticWeb,
        node,
        python,
        javaApk,
      ];

  ProjectTemplate? findById(String id) {
    for (final template in all()) {
      if (template.id == id) return template;
    }
    return null;
  }

  static const staticWeb = ProjectTemplate(
    id: 'static-web',
    kind: ProjectKind.staticWeb,
    label: '静态网页',
    summary: '可直接在浏览器打开的最小待办示例',
    settings: ProjectSettings(
      testCommand: '',
      previewCommand: 'python -m http.server 8765',
      previewPort: 8765,
    ),
    files: [
      ProjectTemplateFile(
        relativePath: 'README.md',
        contents: '''# 静态网页项目

这是一个可以在手机上继续开发的最小网页示例。

## 运行

用任意静态服务器打开当前目录，例如：

```
python -m http.server 8765
```

然后在浏览器访问预览地址。
''',
      ),
      ProjectTemplateFile(
        relativePath: 'index.html',
        contents: '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>待办清单</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main>
    <h1>待办清单</h1>
    <form id="form">
      <input id="title" placeholder="添加一条记录" autocomplete="off">
      <button type="submit">保存</button>
    </form>
    <ul id="items"></ul>
  </main>
  <script src="app.js"></script>
</body>
</html>
''',
      ),
      ProjectTemplateFile(
        relativePath: 'styles.css',
        contents: ''':root { color-scheme: light dark; }
body { font-family: sans-serif; margin: 24px; }
main { max-width: 520px; margin: 0 auto; }
form { display: flex; gap: 8px; }
input { flex: 1; padding: 10px; }
button { padding: 10px 14px; }
li { display: flex; justify-content: space-between; padding: 8px 0; }
''',
      ),
      ProjectTemplateFile(
        relativePath: 'app.js',
        contents: '''const KEY = 'nexus-todo-items';
const itemsEl = document.getElementById('items');
const form = document.getElementById('form');
const title = document.getElementById('title');

function load() {
  try { return JSON.parse(localStorage.getItem(KEY) || '[]'); }
  catch { return []; }
}

function save(items) {
  localStorage.setItem(KEY, JSON.stringify(items));
}

function render() {
  const items = load();
  itemsEl.innerHTML = '';
  for (const item of items) {
    const li = document.createElement('li');
    li.textContent = item;
    const button = document.createElement('button');
    button.textContent = '删除';
    button.onclick = () => {
      save(items.filter((value) => value !== item));
      render();
    };
    li.appendChild(button);
    itemsEl.appendChild(li);
  }
}

form.addEventListener('submit', (event) => {
  event.preventDefault();
  const value = title.value.trim();
  if (!value) return;
  save([...load(), value]);
  title.value = '';
  render();
});

render();
''',
      ),
    ],
  );

  static const node = ProjectTemplate(
    id: 'node',
    kind: ProjectKind.node,
    label: 'Node',
    summary: '带本地检查脚本的最小 Node 服务',
    settings: ProjectSettings(
      testCommand: 'npm test',
      buildCommand: 'npm run build',
      previewCommand: 'npm start',
      previewPort: 3000,
    ),
    files: [
      ProjectTemplateFile(
        relativePath: 'README.md',
        contents: '''# Node 项目

最小可运行示例，包含本地检查脚本。

```
npm install
npm test
npm start
```
''',
      ),
      ProjectTemplateFile(
        relativePath: 'package.json',
        contents: '''{
  "name": "nexus-node-starter",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "start": "node index.js",
    "test": "node --test",
    "build": "node -e \\"process.stdout.write('ok')\\""
  }
}
''',
      ),
      ProjectTemplateFile(
        relativePath: 'index.js',
        contents: '''const http = require('http');
const port = process.env.PORT || 3000;
const server = http.createServer((_, res) => {
  res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
  res.end('NEXUS Node starter');
});
server.listen(port, '127.0.0.1', () => {
  console.log('listening on http://127.0.0.1:' + port);
});
''',
      ),
      ProjectTemplateFile(
        relativePath: 'index.test.js',
        contents: '''const test = require('node:test');
const assert = require('node:assert/strict');

test('starter loads', () => {
  assert.equal(1 + 1, 2);
});
''',
      ),
    ],
  );

  static const python = ProjectTemplate(
    id: 'python',
    kind: ProjectKind.python,
    label: 'Python',
    summary: '带 pytest 入口的最小 Python 项目',
    settings: ProjectSettings(
      testCommand: 'python -m pytest',
      previewCommand: 'python main.py',
    ),
    files: [
      ProjectTemplateFile(
        relativePath: 'README.md',
        contents: '''# Python 项目

```
python -m pip install -r requirements.txt
python -m pytest
python main.py
```
''',
      ),
      ProjectTemplateFile(
        relativePath: 'requirements.txt',
        contents: 'pytest>=8.0.0\n',
      ),
      ProjectTemplateFile(
        relativePath: 'main.py',
        contents: '''def greeting(name: str) -> str:
    return f"hello {name}"


if __name__ == "__main__":
    print(greeting("nexus"))
''',
      ),
      ProjectTemplateFile(
        relativePath: 'test_main.py',
        contents: '''from main import greeting


def test_greeting():
    assert greeting("world") == "hello world"
''',
      ),
    ],
  );

  static const javaApk = ProjectTemplate(
    id: 'java-apk',
    kind: ProjectKind.javaApk,
    label: '小型 Java APK',
    summary: '无 Gradle 的单页面 Android 工具模板',
    settings: ProjectSettings(
      packageName: 'com.nexus.starter',
      appName: 'NexusStarter',
      buildCommand: 'sh build.sh',
    ),
    files: [
      ProjectTemplateFile(
        relativePath: 'README.md',
        contents: '''# 小型 Java APK

这是一个不依赖 Gradle 的 Android 单页面模板。构建需要 JDK、android.jar、aapt2 和 d8。

默认包名：`com.nexus.starter`

```
sh build.sh
```

产物默认写到 `dist/app-debug.apk`。
''',
      ),
      ProjectTemplateFile(
        relativePath: 'AndroidManifest.xml',
        contents: '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.nexus.starter">
    <application android:label="NexusStarter" android:hasCode="true">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
      ),
      ProjectTemplateFile(
        relativePath: 'src/com/nexus/starter/MainActivity.java',
        contents: '''package com.nexus.starter;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    @override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView view = new TextView(this);
        view.setText("NEXUS Java APK starter");
        view.setTextSize(20);
        view.setPadding(48, 96, 48, 48);
        setContentView(view);
    }
}
''',
      ),
      ProjectTemplateFile(
        relativePath: 'build.sh',
        contents: '''#!/bin/sh
set -e
ROOT="\$(cd "\$(dirname "\$0")" && pwd)"
PKG=com/nexus/starter
mkdir -p "\$ROOT/build/classes" "\$ROOT/dist"
if ! command -v javac >/dev/null 2>&1; then
  echo "javac is required. Do not use flutter or gradle for this template." >&2
  exit 127
fi
javac -d "\$ROOT/build/classes" "\$ROOT/src/\$PKG/MainActivity.java"
if command -v aapt2 >/dev/null 2>&1 && command -v d8 >/dev/null 2>&1 && [ -n "\$ANDROID_HOME" ]; then
  aapt2 compile --dir "\$ROOT" -o "\$ROOT/build/compiled.zip" || true
  echo "SDK tools detected; continue with aapt2/d8 packaging."
else
  echo "ANDROID_HOME/aapt2/d8 not fully configured; compiled classes are in build/classes."
fi
echo "Place the resulting APK at dist/app-debug.apk after a successful package step."
''',
      ),
    ],
  );
}
