import 'package:supabase/supabase.dart';
import 'dart:convert';
import 'dart:io';

void main() async {
  final client = SupabaseClient(
    'https://amrjkvvmvhqoqqkxntna.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFtcmprdnZtdmhxb3Fxa3hudG5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwMzUzOTksImV4cCI6MjA4MjYxMTM5OX0.CQ4VlMVG5m80JdJdvOqZ4-11Ewq3kvmplxAcXuM3tOw',
  );

  final outfile = File('inspect_db_output.txt');
  final sink = outfile.openWrite();

  try {
    sink.writeln('--- Fetching Movies ---');
    final movies = await client.from('entries').select('id, type, title, content').eq('type', 'movie').limit(2);
    for (var m in movies) {
      sink.writeln('Movie ID: ${m['id']} - Title: ${m['title']}');
      JsonEncoder encoder = const JsonEncoder.withIndent('  ');
      var contentData = m['content'];
      if (contentData is String) {
        try {
          contentData = jsonDecode(contentData);
        } catch (_) {}
      }
      sink.writeln('Content:\n${encoder.convert(contentData)}');
      sink.writeln('---------------------------');
    }

    sink.writeln('\n--- Fetching Series ---');
    final series = await client.from('entries').select('id, type, title, content').eq('type', 'series').limit(2);
    for (var s in series) {
      sink.writeln('Series ID: ${s['id']} - Title: ${s['title']}');
      JsonEncoder encoder = const JsonEncoder.withIndent('  ');
      var contentData = s['content'];
      if (contentData is String) {
        try {
          contentData = jsonDecode(contentData);
        } catch (_) {}
      }
      sink.writeln('Content:\n${encoder.convert(contentData)}');
      sink.writeln('---------------------------');
    }
  } catch (e) {
    sink.writeln('Error: $e');
  } finally {
    await sink.close();
    exit(0);
  }
}
