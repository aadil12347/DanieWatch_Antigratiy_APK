import 'package:daniewatch_app/services/extraction/site_post_extractor.dart';

void main() async {
  final url = 'https://vcloud.fit/zwo5kbpl7rt_t5l';
  print('Resolving stream for $url...');
  try {
    final res = await SitePostExtractor.instance.resolveVcloudStream(url);
    print('fslv2Url: ${res.fslv2Url}');
    print('fslUrl: ${res.fslUrl}');
    print('fastDlUrl: ${res.fastDlUrl}');
    print('tenGbpsUrl: ${res.tenGbpsUrl}');
    print('pixeldrainUrl: ${res.pixeldrainUrl}');
    print('fileSize: ${res.fileSize}');
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}
