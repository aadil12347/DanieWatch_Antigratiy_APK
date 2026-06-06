import 'lib/services/peachify_extractor.dart';

void main() async {
  print('Testing PeachifyExtractorService...');
  final service = PeachifyExtractorService();
  
  try {
    final streams = await service.extractStreams(tmdbId: 1304313, mediaType: 'movie');
    
    print('Found \${streams.length} streams in total.');
    
    for (var stream in streams) {
      print('Provider: \${stream.providerName} | Dub: \${stream.dub} | Type: \${stream.type} | URL: \${stream.url}');
    }
  } catch(e) {
    print('Error: \$e');
  }
}
