import 'dart:typed_data';

/// No-op on non-web platforms.
void openUrlInNewTab(String url) {}

/// No-op on non-web platforms.
void openBytesInNewTab(Uint8List bytes, String mimeType) {}

/// No-op on non-web platforms.
void openHtmlInNewTab(String html) {}

/// No-op on non-web platforms.
void downloadBytesOnWeb(Uint8List bytes, String mimeType, String fileName) {}
