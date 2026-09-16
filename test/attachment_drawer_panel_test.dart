import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/presentation/chat/widgets/attachment_drawer_panel.dart';

void main() {
  testWidgets('attachment panel renders selected image thumbnails',
      (tester) async {
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentDrawerPanel(
            attachments: [
              PlatformFile(
                name: 'preview.png',
                size: imageBytes.length,
                bytes: imageBytes,
              ),
            ],
            onCamera: () {},
            onGallery: () {},
            onFile: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });
}
