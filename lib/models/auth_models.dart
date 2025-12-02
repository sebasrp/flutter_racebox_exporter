/// User information returned from the API
class User {
  final String id;
  final String email;
  final bool emailVerified;

  User({required this.id, required this.email, required this.emailVerified});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      emailVerified: json['emailVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'email': email, 'emailVerified': emailVerified};
  }
}

/// Authentication response from login/register endpoints
class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final User user;

  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toIso8601String(),
      'user': user.toJson(),
    };
  }
}

/// Request body for login
class LoginRequest {
  final String email;
  final String password;

  LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {'email': email, 'password': password};
  }
}

/// Request body for registration
class RegisterRequest {
  final String email;
  final String password;

  RegisterRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {'email': email, 'password': password};
  }
}

/// Request body for token refresh
class RefreshTokenRequest {
  final String refreshToken;

  RefreshTokenRequest({required this.refreshToken});

  Map<String, dynamic> toJson() {
    return {'refreshToken': refreshToken};
  }
}

/// Authentication error types
enum AuthErrorType {
  invalidCredentials,
  userExists,
  invalidRequest,
  accountDisabled,
  invalidToken,
  networkError,
  serverError,
  unknown,
}

/// Authentication error with type and message
class AuthError implements Exception {
  final AuthErrorType type;
  final String message;

  AuthError({required this.type, required this.message});

  factory AuthError.fromJson(Map<String, dynamic> json) {
    final errorCode = json['error'] as String? ?? 'unknown';
    final message = json['message'] as String? ?? 'An error occurred';

    AuthErrorType type;
    switch (errorCode) {
      case 'invalid_credentials':
        type = AuthErrorType.invalidCredentials;
        break;
      case 'user_exists':
        type = AuthErrorType.userExists;
        break;
      case 'invalid_request':
        type = AuthErrorType.invalidRequest;
        break;
      case 'account_disabled':
        type = AuthErrorType.accountDisabled;
        break;
      case 'invalid_token':
        type = AuthErrorType.invalidToken;
        break;
      case 'internal_error':
        type = AuthErrorType.serverError;
        break;
      default:
        type = AuthErrorType.unknown;
    }

    return AuthError(type: type, message: message);
  }

  @override
  String toString() => message;
}

/// Stored authentication state
class StoredAuthState {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final User user;

  StoredAuthState({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory StoredAuthState.fromJson(Map<String, dynamic> json) {
    return StoredAuthState(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toIso8601String(),
      'user': user.toJson(),
    };
  }

  /// Check if the access token is expired or about to expire
  bool get isAccessTokenExpired {
    // Consider token expired if it expires within 5 minutes
    return DateTime.now().isAfter(
      expiresAt.subtract(const Duration(minutes: 5)),
    );
  }
}
