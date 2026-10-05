enum LanRuntimeRole { desktopMain, desktopStaff, androidCompanion }

enum LanBackendState { stopped, starting, ready, failed }

/// Eligibility for a future server host. Binding still needs an OS-level lock.
/// This policy does not start a listener or bypass the license gate.
class LanBackendPolicy {
  const LanBackendPolicy({
    required this.role,
    required this.enabled,
    required this.licenseAuthorized,
  });

  final LanRuntimeRole role;
  final bool enabled;
  final bool licenseAuthorized;

  bool get mayOwnBackend =>
      role == LanRuntimeRole.desktopMain && enabled && licenseAuthorized;

  bool shouldServe(LanBackendState state) =>
      mayOwnBackend && state == LanBackendState.ready;
}
