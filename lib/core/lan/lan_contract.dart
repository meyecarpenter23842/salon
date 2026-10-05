/// Wire primitives shared by desktop and Android. No storage or UI dependency.
class LanContract {
  static const apiVersion = 1;
  static const basePath = '/api/staff/v1';
  static const healthPath = '$basePath/health';

  static String sessionPath(String sessionId) {
    validateIdentity(sessionId, 'sessionId');
    return '$basePath/billing-sessions/${Uri.encodeComponent(sessionId)}';
  }

  static void validateIdentity(String value, String field) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
      throw FormatException('Invalid $field');
    }
  }
}

enum LanErrorCode {
  invalidRequest(400, 'invalid_request'),
  unauthenticated(401, 'unauthenticated'),
  forbidden(403, 'forbidden'),
  notFound(404, 'not_found'),
  revisionConflict(409, 'revision_conflict'),
  commandConflict(409, 'command_conflict'),
  alreadyPaid(409, 'already_paid'),
  businessRule(422, 'business_rule'),
  rateLimited(429, 'rate_limited'),
  unavailable(503, 'unavailable'),
  internal(500, 'internal');

  const LanErrorCode(this.httpStatus, this.wireName);
  final int httpStatus;
  final String wireName;
}

/// Error payload intentionally cannot carry exception text, SQL or local paths.
class LanFailure {
  const LanFailure(this.code, {required this.requestId});

  final LanErrorCode code;
  final String requestId;

  Map<String, Object> toJson() {
    LanContract.validateIdentity(requestId, 'requestId');
    return {
      'apiVersion': LanContract.apiVersion,
      'requestId': requestId,
      'error': {'code': code.wireName},
    };
  }
}

/// A precondition, not authorization. Actor identity comes from device auth.
class LanCommand {
  LanCommand({
    required this.commandId,
    required this.sessionId,
    required this.expectedRevision,
  }) {
    LanContract.validateIdentity(commandId, 'commandId');
    LanContract.validateIdentity(sessionId, 'sessionId');
    if (expectedRevision < 0) {
      throw const FormatException('Invalid expectedRevision');
    }
  }

  factory LanCommand.fromJson(Map<String, Object?> json) {
    final commandId = json['commandId'];
    final sessionId = json['sessionId'];
    final revision = json['expectedRevision'];
    if (commandId is! String || sessionId is! String || revision is! int) {
      throw const FormatException('Invalid command envelope');
    }
    return LanCommand(
      commandId: commandId,
      sessionId: sessionId,
      expectedRevision: revision,
    );
  }

  final String commandId;
  final String sessionId;
  final int expectedRevision;

  Map<String, Object> toJson() => {
    'commandId': commandId,
    'sessionId': sessionId,
    'expectedRevision': expectedRevision,
  };
}

/// Liveness only: contains no business data, identifiers, schema or secrets.
class LanHealth {
  const LanHealth();

  Map<String, Object> toJson() => {
    'apiVersion': LanContract.apiVersion,
    'status': 'ok',
  };
}
