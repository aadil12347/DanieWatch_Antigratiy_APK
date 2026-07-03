/// Rich quality metadata parser for stream titles/filenames.
///
/// Ported from CSX's CineStreamUtils.kt SpecOption system.
/// Parses: source quality, codec, bit depth, audio format, HDR, language
/// and generates display strings with emoji indicators.

/// A specification option that matches terms in a title string.
class SpecOption {
  final List<String> searchTerms;
  final String label;
  late final RegExp regex;

  SpecOption(this.searchTerms, this.label) {
    final escapedTerms =
        searchTerms.map((t) => RegExp.escape(t)).join('|');
    regex = RegExp(
      '(?<=^|\\W)(?:$escapedTerms)(?=[^a-zA-Z0-9_+]|\$)',
      caseSensitive: false,
    );
  }

  SpecOption.single(String term, this.label) : searchTerms = [term] {
    final escaped = RegExp.escape(term);
    regex = RegExp(
      '(?<=^|\\W)(?:$escaped)(?=[^a-zA-Z0-9_+]|\$)',
      caseSensitive: false,
    );
  }
}

/// All spec options organized by category.
/// Ported from CSX's SPEC_OPTIONS map.
final Map<String, List<SpecOption>> specOptions = {
  'quality': [
    SpecOption.single('UHD BluRay', '4K UHD BluRay 💿'),
    SpecOption.single('BluRay', 'BluRay 💿'),
    SpecOption.single('BluRay REMUX', 'BluRay REMUX 💾'),
    SpecOption.single('BDRip', 'BDRip 💿'),
    SpecOption.single('BRRip', 'BRRip 💿'),
    SpecOption.single('DVDRip', 'DVDRip 📀'),
    SpecOption.single('WEB-DL', 'WEB-DL ☁️'),
    SpecOption.single('WEBRip', 'WEBRip 🌐'),
    SpecOption.single('HDRip', 'HDRip ✨'),
    SpecOption.single('HDTV', 'HDTV 📺'),
    SpecOption.single('CAM', 'CAM 📹'),
    SpecOption.single('TeleSync', 'TeleSync 📹'),
    SpecOption.single('TS', 'TS 🚫'),
    SpecOption.single('SCR', 'SCR 📼'),
    SpecOption.single('DVDScr', 'DVDScr 📼'),
  ],
  'codec': [
    SpecOption.single('av1', 'AV1 🚀'),
    SpecOption(['x265', 'h.265', 'hevc'], 'HEVC ⚡'),
    SpecOption.single('vp9', 'VP9 🧪'),
    SpecOption(['x264', 'h.264', 'H264', 'avc'], 'H.264 📦'),
    SpecOption.single('mpeg-2', 'MPEG-2 🎞️'),
    SpecOption.single('xvid', 'XviD 🧩'),
  ],
  'bitdepth': [
    SpecOption.single('10bit', '10bit 🎨'),
    SpecOption.single('8bit', '8bit 🖍️'),
    SpecOption.single('3D', '3D 👓'),
    SpecOption.single('IMAX', 'IMAX 🏟️'),
  ],
  'audio': [
    SpecOption.single('TrueHD', 'Dolby TrueHD 🔊'),
    SpecOption.single('Atmos', 'Dolby Atmos 🌌'),
    SpecOption(['DDP5.1', 'DDP 5.1'], 'DD+ 5.1 🔉'),
    SpecOption.single('7.1', '7.1 Ch 🔊'),
    SpecOption.single('5.1', '5.1 Ch 🔉'),
    SpecOption.single('DTS-HD MA', 'DTS-HD MA 🔊'),
    SpecOption.single('DTS-HD', 'DTS-HD 🔊'),
    SpecOption(['E-AC3', 'DD+', 'Dolby Digital Plus'], 'DD+ 🔉'),
    SpecOption.single('AC3', 'AC3 🔈'),
    SpecOption.single('DTS', 'DTS 🔈'),
    SpecOption.single('AAC', 'AAC 🎧'),
    SpecOption.single('OPUS', 'Opus 🎙️'),
    SpecOption.single('FLAC', 'FLAC 🎹'),
    SpecOption.single('MP3', 'MP3 🎵'),
  ],
  'hdr': [
    SpecOption(['DV', 'DoVi', 'DOLBYVISION', 'Dolby Vision'], 'Dolby Vision 👁️'),
    SpecOption.single('HDR10+', 'HDR10+ 🔆'),
    SpecOption.single('HDR10', 'HDR10 🔆'),
    SpecOption.single('HLG', 'HLG 📡'),
    SpecOption.single('HDR', 'HDR 🔆'),
    SpecOption.single('SDR', 'SDR 🔅'),
  ],
  'language': [
    SpecOption(['HIN', 'Hindi'], 'Hindi 🇮🇳'),
    SpecOption.single('Tamil', 'Tamil 🇮🇳'),
    SpecOption.single('Telugu', 'Telugu 🇮🇳'),
    SpecOption.single('Malayalam', 'Malayalam 🇮🇳'),
    SpecOption.single('Kannada', 'Kannada 🇮🇳'),
    SpecOption.single('Bengali', 'Bengali 🇮🇳'),
    SpecOption.single('Punjabi', 'Punjabi 🇮🇳'),
    SpecOption(['ENG', 'English'], 'English 🇺🇸'),
    SpecOption(['KOR', 'Korean'], 'Korean 🇰🇷'),
    SpecOption(['JPN', 'Japanese'], 'Japanese 🇯🇵'),
    SpecOption(['CHN', 'Chinese'], 'Chinese 🇨🇳'),
    SpecOption.single('Spanish', 'Spanish 🇪🇸'),
    SpecOption.single('French', 'French 🇫🇷'),
    SpecOption.single('German', 'German 🇩🇪'),
    SpecOption(['Multi-Audio', 'Multi Audio', 'Multi.Audio'], 'Multi Audio 🌍'),
    SpecOption(['Dual.Audio', 'Dual Audio', 'Dual'], 'Dual Audio 🌗'),
    SpecOption(['Multi-Sub', 'MultiSub', 'Multi Sub'], 'Multi Subs 💬'),
    SpecOption.single('ESub', 'English Subs 🇺🇸'),
  ],
};

/// Category processing order (matches CSX's CATEGORY_ORDER).
const List<String> _categoryOrder = [
  'quality', 'codec', 'bitdepth', 'audio', 'hdr', 'language',
];

/// Size regex to extract file size from title.
final RegExp _sizeRegex =
    RegExp(r'(\d+(?:\.\d+)?\s?(?:MB|GB))', caseSensitive: false);

/// Parse a title/filename and return rich quality tags string.
///
/// Ported from CSX's `getSimplifiedTitle()`.
///
/// Example input: "Movie.2024.1080p.WEB-DL.x265.DDP5.1.Hindi.English-Group"
/// Example output: "WEB-DL ☁️ | HEVC ⚡ | DD+ 5.1 🔉 | Hindi 🇮🇳 | English 🇺🇸"
String getQualityTags(String title) {
  var remainingTitle = title;
  final matchedLabels = <String>[];

  for (final category in _categoryOrder) {
    final options = specOptions[category] ?? [];
    for (final spec in options) {
      if (spec.regex.hasMatch(remainingTitle)) {
        matchedLabels.add(spec.label);
        remainingTitle = remainingTitle.replaceAll(spec.regex, ' ');
      }
    }
  }

  // Extract file size
  final sizeMatch = _sizeRegex.firstMatch(title);
  final size = sizeMatch?.group(1)?.toUpperCase();

  final parts = <String>[
    if (matchedLabels.isNotEmpty) matchedLabels.toSet().join(' | '),
    if (size != null) '$size 💾',
  ];

  return parts.join(' | ');
}

/// Parse only the language tags from a title.
List<String> getLanguageTags(String title) {
  final languages = <String>[];
  final options = specOptions['language'] ?? [];
  for (final spec in options) {
    if (spec.regex.hasMatch(title)) {
      languages.add(spec.label);
    }
  }
  return languages;
}

/// Parse only the source quality tag (WEB-DL, BluRay, HDRip, etc).
String? getSourceQualityTag(String title) {
  final options = specOptions['quality'] ?? [];
  for (final spec in options) {
    if (spec.regex.hasMatch(title)) {
      return spec.label;
    }
  }
  return null;
}

/// Parse file size from title string.
String? getFileSize(String title) {
  return _sizeRegex.firstMatch(title)?.group(1)?.toUpperCase();
}
