import 'dart:io';

import '../lib/services/vcloud_extractor.dart';

void main() async {
  final url = 'https://vcloud.zip/oh55kmlbiydogqr';
  print('Extracting $url...');
  try {
    final extractor = VcloudExtractorService();
    final result = await extractor.extractVcloud(url);
    print('\nResolved Server Map:');
    result.forEach((key, value) {
      print('$key: $value');
    });
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
