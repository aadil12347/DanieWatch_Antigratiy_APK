import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/clients/tmdb_client.dart';
import '../../domain/models/manifest_item.dart';
import 'manifest_provider.dart';

// ─── Actor Info Model ────────────────────────────────────────────────────────

class ActorInfo {
  final int id;
  final String name;
  final String? profileUrl;
  final int? age;
  final String? gender;
  final String? country;
  final String? biography;
  final String? knownFor;
  final String? birthday;
  final String? deathday;

  const ActorInfo({
    required this.id,
    required this.name,
    this.profileUrl,
    this.age,
    this.gender,
    this.country,
    this.biography,
    this.knownFor,
    this.birthday,
    this.deathday,
  });
}

// ─── Helper: Calculate age from birthday string ──────────────────────────────

int? _calculateAge(String? birthday, String? deathday) {
  if (birthday == null || birthday.isEmpty) return null;
  try {
    final birth = DateTime.parse(birthday);
    final end = deathday != null && deathday.isNotEmpty
        ? DateTime.parse(deathday)
        : DateTime.now();
    int age = end.year - birth.year;
    if (end.month < birth.month ||
        (end.month == birth.month && end.day < birth.day)) {
      age--;
    }
    return age;
  } catch (_) {
    return null;
  }
}

// ─── Helper: Map TMDB gender int to readable string ──────────────────────────

String? _mapGender(dynamic genderValue) {
  if (genderValue == null) return null;
  final g = genderValue is int ? genderValue : int.tryParse(genderValue.toString());
  switch (g) {
    case 1:
      return 'Female';
    case 2:
      return 'Male';
    case 3:
      return 'Non-Binary';
    default:
      return null;
  }
}

// ─── Helper: Extract country from place_of_birth ─────────────────────────────

String? _extractCountry(String? placeOfBirth) {
  if (placeOfBirth == null || placeOfBirth.isEmpty) return null;
  // TMDB format: "City, State, Country" — take last segment
  final parts = placeOfBirth.split(',').map((s) => s.trim()).toList();
  return parts.isNotEmpty ? parts.last : placeOfBirth;
}

// ─── Provider: Fetch actor info from TMDB ────────────────────────────────────

final actorInfoProvider = FutureProvider.family<ActorInfo?, int>(
  (ref, actorId) async {
    final data = await TmdbClient.instance.getPersonDetails(actorId);
    if (data == null) return null;

    final birthday = data['birthday']?.toString();
    final deathday = data['deathday']?.toString();
    final profilePath = data['profile_path']?.toString();

    return ActorInfo(
      id: actorId,
      name: data['name']?.toString() ?? 'Unknown',
      profileUrl: profilePath != null && profilePath.isNotEmpty
          ? 'https://image.tmdb.org/t/p/w185$profilePath'
          : null,
      age: _calculateAge(birthday, deathday),
      gender: _mapGender(data['gender']),
      country: _extractCountry(data['place_of_birth']?.toString()),
      biography: data['biography']?.toString(),
      knownFor: data['known_for_department']?.toString(),
      birthday: birthday,
      deathday: deathday,
    );
  },
);

// ─── Provider: Fetch actor filmography filtered to manifest index ────────────

final actorFilmographyProvider = FutureProvider.family<List<ManifestItem>, int>(
  (ref, actorId) async {
    // 1. Fetch all combined credits from TMDB
    final credits = await TmdbClient.instance.getPersonCombinedCredits(actorId);

    // 2. Get the manifest index (all items in the app's JSON)
    final manifestIndex = ref.watch(manifestIndexProvider);
    if (manifestIndex.isEmpty) return [];

    // 3. Cross-reference: only keep credits that exist in the manifest
    final List<ManifestItem> result = [];
    final seen = <String>{}; // Avoid duplicates

    for (final credit in credits) {
      final id = credit['id'];
      if (id == null) continue;
      final tmdbId = id is int ? id : int.tryParse(id.toString());
      if (tmdbId == null) continue;

      final mediaType = credit['media_type']?.toString() ?? 'movie';
      final normalizedType = (mediaType == 'tv' || mediaType == 'series') ? 'tv' : 'movie';

      final key = '$tmdbId-$normalizedType';
      if (seen.contains(key)) continue;

      if (manifestIndex.containsKey(key)) {
        result.add(manifestIndex[key]!);
        seen.add(key);
      }
    }

    // Sort by vote count descending (most popular first)
    result.sort((a, b) => b.voteCount.compareTo(a.voteCount));
    return result;
  },
);
