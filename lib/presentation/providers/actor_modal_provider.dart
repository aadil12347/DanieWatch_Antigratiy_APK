import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the actor detail modal that morphs from the bottom navbar.
class ActorModalState {
  final bool isOpen;
  final int? actorId;
  final String? actorName;
  final String? characterName;
  final String? profilePath;

  const ActorModalState({
    this.isOpen = false,
    this.actorId,
    this.actorName,
    this.characterName,
    this.profilePath,
  });
}

final actorModalProvider = StateProvider<ActorModalState>(
  (_) => const ActorModalState(),
);
