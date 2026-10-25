// Standalone diagnostic for Flutter Windows AXTree failures (upstream #190357).
// No application imports, storage, services, theme, ListView or Tooltip.
// Run separately; never use as the application entry point for a release.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Retained by the root widget for this diagnostic process's lifetime only.
  runApp(_SliderAxRepro(semanticsHandle: binding.ensureSemantics()));
}

class _SliderAxRepro extends StatelessWidget {
  const _SliderAxRepro({required this.semanticsHandle});

  final SemanticsHandle semanticsHandle;

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _SliderScreen(pushed: false),
      );
}

class _SliderScreen extends StatefulWidget {
  const _SliderScreen({required this.pushed});

  final bool pushed;

  @override
  State<_SliderScreen> createState() => _SliderScreenState();
}

class _SliderScreenState extends State<_SliderScreen> {
  double value = 0.3;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.pushed
                    ? 'Pushed route slider'
                    : 'Home route slider'),
                Slider(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
                FilledButton(
                  onPressed: () {
                    if (widget.pushed) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const _SliderScreen(pushed: true),
                      ));
                    }
                  },
                  child: Text(widget.pushed ? 'Back' : 'Push slider route'),
                ),
              ],
            ),
          ),
        ),
      );
}
