import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

void main() {
  // Test AES GCM decryption
  final keyHex = 'a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b';
  
  // We need a test payload from python output to verify
  // For now we'll just check if it compiles and runs without error on the imports
  print("Encrypt package imported successfully.");
}
