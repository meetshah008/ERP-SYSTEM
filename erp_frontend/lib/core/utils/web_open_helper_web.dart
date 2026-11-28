import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void openUrlInNewTab(String url) {
  web.window.open(url, '_blank');
}

void openBytesInNewTab(Uint8List bytes, String mimeType) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final blobUrl = web.URL.createObjectURL(blob);
  web.window.open(blobUrl, '_blank');
}

void openHtmlInNewTab(String html) {
  final blob = web.Blob(
    [html.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
}

void downloadBytesOnWeb(Uint8List bytes, String mimeType, String fileName) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = fileName;
  a.click();
  web.URL.revokeObjectURL(url);
}
