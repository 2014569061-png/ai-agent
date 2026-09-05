// The iframe is a Flutter Web-only platform view. The conditional export keeps
// this file out of native builds.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

/// Web 端 iframe 视图。每次地址变化使用新的 view type，确保浏览器重新加载。
class PhonePreviewView extends StatefulWidget {
  const PhonePreviewView({super.key, required this.url});

  final String url;

  @override
  State<PhonePreviewView> createState() => _PhonePreviewViewState();
}

class _PhonePreviewViewState extends State<PhonePreviewView> {
  static int _nextId = 0;
  late String _viewType;

  @override
  void initState() {
    super.initState();
    _register(widget.url);
  }

  void _register(String url) {
    _viewType = 'phone-preview-iframe-${_nextId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..style.backgroundColor = 'white'
        ..setAttribute('title', '手机页面预览')
        ..setAttribute('allow', 'clipboard-read; clipboard-write; autoplay');
      return iframe;
    });
  }

  @override
  void didUpdateWidget(covariant PhonePreviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _register(widget.url);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
