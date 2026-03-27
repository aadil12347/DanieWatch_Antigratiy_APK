import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const url =
      'https://amrjkvvmvhqoqqkxntna.supabase.co/storage/v1/object/public/manifests/db_manifest_v1.json';
  final res = await http.get(Uri.parse(url));
  print(res.statusCode);
  if (res.statusCode == 200) {
    print('OK: ${res.body.length}');
    final json = jsonDecode(res.body);
    print("version: ${json['version'].runtimeType}");
    print("generated_at: ${json['generated_at'].runtimeType}");
    print("total_count: ${json['total_count'].runtimeType}");
  }
}
