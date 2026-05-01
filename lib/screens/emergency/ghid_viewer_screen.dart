import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../theme/app_theme.dart';
import '../../services/app_settings_service.dart';

class GhidViewerScreen extends StatefulWidget {
  const GhidViewerScreen({super.key});

  @override
  State<GhidViewerScreen> createState() => _GhidViewerScreenState();
}

class _GhidViewerScreenState extends State<GhidViewerScreen> {
  late final PdfController _pdf;

  @override
  void initState() {
    super.initState();
    _pdf = PdfController(
      document: PdfDocument.openAsset('assets/ghid.pdf'),
    );
  }

  @override
  void dispose() {
    _pdf.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Guide'),
        backgroundColor: Colors.transparent,
        foregroundColor:
            isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean,
        actions: [
          PdfPageNumber(
            controller: _pdf,
            builder: (_, loadingState, page, pagesCount) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  loadingState == PdfLoadingState.success
                      ? '$page / $pagesCount'
                      : '',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? TogetherTheme.amoledTextSecondary
                        : TogetherTheme.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: PdfView(
        controller: _pdf,
        scrollDirection: Axis.vertical,
        pageSnapping: false,
        renderer: (PdfPage page) => page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        ),
        builders: PdfViewBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) => const Center(
            child: CircularProgressIndicator(),
          ),
          pageLoaderBuilder: (_) => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          errorBuilder: (_, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load guide: $error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? TogetherTheme.amoledTextSecondary
                      : TogetherTheme.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
