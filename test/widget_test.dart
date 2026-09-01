import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_agent/main.dart';

void main() {
  testWidgets('renders the mobile agent shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MobileAgentApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
