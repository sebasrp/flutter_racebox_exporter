import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_racebox_exporter/services/auth_service.dart';
import 'package:flutter_racebox_exporter/services/secure_storage_service.dart';
import 'package:flutter_racebox_exporter/models/auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService', () {
    late AuthService authService;
    late MockClient mockClient;
    late SecureStorageService storage;

    setUp(() async {
      // Initialize SharedPreferences for testing
      SharedPreferences.setMockInitialValues({});
      storage = SecureStorageService();
      await storage.init();
    });

    tearDown(() async {
      await storage.clearAuthState();
    });

    group('login', () {
      test('successful login returns AuthResponse and updates state', () async {
        final mockResponse = {
          'accessToken': 'test-access-token',
          'refreshToken': 'test-refresh-token',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'user': {
            'id': 'user-123',
            'email': 'test@example.com',
            'emailVerified': false,
          },
        };

        mockClient = MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/login');
          expect(request.method, 'POST');

          final body = jsonDecode(request.body);
          expect(body['email'], 'test@example.com');
          expect(body['password'], 'password123');

          return http.Response(jsonEncode(mockResponse), 200);
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        final result = await authService.login(
          email: 'test@example.com',
          password: 'password123',
        );

        expect(result.accessToken, 'test-access-token');
        expect(result.refreshToken, 'test-refresh-token');
        expect(result.user.email, 'test@example.com');
        expect(authService.isAuthenticated, true);
        expect(authService.currentUser?.email, 'test@example.com');
      });

      test('login with invalid credentials throws AuthError', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'invalid_credentials',
              'message': 'Invalid email or password',
            }),
            401,
          );
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        expect(
          () => authService.login(
            email: 'test@example.com',
            password: 'wrongpassword',
          ),
          throwsA(
            isA<AuthError>().having(
              (e) => e.type,
              'type',
              AuthErrorType.invalidCredentials,
            ),
          ),
        );
      });

      test('login with disabled account throws AuthError', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'account_disabled',
              'message': 'This account has been disabled',
            }),
            403,
          );
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        expect(
          () => authService.login(
            email: 'test@example.com',
            password: 'password123',
          ),
          throwsA(
            isA<AuthError>().having(
              (e) => e.type,
              'type',
              AuthErrorType.accountDisabled,
            ),
          ),
        );
      });
    });

    group('register', () {
      test('successful registration returns AuthResponse', () async {
        final mockResponse = {
          'accessToken': 'test-access-token',
          'refreshToken': 'test-refresh-token',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'user': {
            'id': 'user-123',
            'email': 'newuser@example.com',
            'emailVerified': false,
          },
        };

        mockClient = MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/register');
          expect(request.method, 'POST');

          return http.Response(jsonEncode(mockResponse), 201);
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        final result = await authService.register(
          email: 'newuser@example.com',
          password: 'password123',
        );

        expect(result.user.email, 'newuser@example.com');
        expect(authService.isAuthenticated, true);
      });

      test('register with existing email throws AuthError', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'user_exists',
              'message': 'A user with this email already exists',
            }),
            409,
          );
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        expect(
          () => authService.register(
            email: 'existing@example.com',
            password: 'password123',
          ),
          throwsA(
            isA<AuthError>().having(
              (e) => e.type,
              'type',
              AuthErrorType.userExists,
            ),
          ),
        );
      });
    });

    group('logout', () {
      test('logout clears auth state', () async {
        // First, set up an authenticated state
        final mockResponse = {
          'accessToken': 'test-access-token',
          'refreshToken': 'test-refresh-token',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'user': {
            'id': 'user-123',
            'email': 'test@example.com',
            'emailVerified': false,
          },
        };

        mockClient = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return http.Response(jsonEncode(mockResponse), 200);
          }
          if (request.url.path == '/api/v1/auth/logout') {
            return http.Response(
              jsonEncode({'message': 'Successfully logged out'}),
              200,
            );
          }
          return http.Response('Not found', 404);
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        // Login first
        await authService.login(
          email: 'test@example.com',
          password: 'password123',
        );
        expect(authService.isAuthenticated, true);

        // Then logout
        await authService.logout();
        expect(authService.isAuthenticated, false);
        expect(authService.currentUser, null);
      });
    });

    group('token refresh', () {
      test('refreshToken updates tokens', () async {
        // Set up initial auth state
        final initialState = StoredAuthState(
          accessToken: 'old-access-token',
          refreshToken: 'old-refresh-token',
          expiresAt: DateTime.now().subtract(
            const Duration(hours: 1),
          ), // Expired
          user: User(
            id: 'user-123',
            email: 'test@example.com',
            emailVerified: false,
          ),
        );
        await storage.saveAuthState(initialState);

        final refreshResponse = {
          'accessToken': 'new-access-token',
          'refreshToken': 'new-refresh-token',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'user': {
            'id': 'user-123',
            'email': 'test@example.com',
            'emailVerified': false,
          },
        };

        mockClient = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            return http.Response(jsonEncode(refreshResponse), 200);
          }
          return http.Response('Not found', 404);
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        await authService.refreshToken();

        final newToken = await storage.getAccessToken();
        expect(newToken, 'new-access-token');
      });
    });

    group('forgotPassword', () {
      test('successful request returns without error', () async {
        mockClient = MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/forgot-password');
          expect(request.method, 'POST');

          final body = jsonDecode(request.body);
          expect(body['email'], 'test@example.com');

          return http.Response(
            jsonEncode({
              'message':
                  'If an account with that email exists, a password reset link has been sent',
            }),
            200,
          );
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        // Should not throw any error
        await authService.forgotPassword(email: 'test@example.com');
      });

      test('trims email before sending request', () async {
        mockClient = MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['email'], 'test@example.com'); // Should be trimmed

          return http.Response(
            jsonEncode({'message': 'Password reset email sent'}),
            200,
          );
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        await authService.forgotPassword(email: '  test@example.com  ');
      });

      test('throws AuthError on non-200 response', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'internal_error',
              'message': 'Server error occurred',
            }),
            500,
          );
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        expect(
          () => authService.forgotPassword(email: 'test@example.com'),
          throwsA(
            isA<AuthError>().having(
              (e) => e.type,
              'type',
              AuthErrorType.serverError,
            ),
          ),
        );
      });

      test('throws AuthError on network error', () async {
        mockClient = MockClient((request) async {
          throw Exception('Network error');
        });

        authService = AuthService(httpClient: mockClient, storage: storage);
        authService.setBaseUrl('http://localhost:8080');

        expect(
          () => authService.forgotPassword(email: 'test@example.com'),
          throwsA(
            isA<AuthError>().having(
              (e) => e.type,
              'type',
              AuthErrorType.networkError,
            ),
          ),
        );
      });
    });
  });

  group('AuthModels', () {
    test('User.fromJson parses correctly', () {
      final json = {
        'id': 'user-123',
        'email': 'test@example.com',
        'emailVerified': true,
      };

      final user = User.fromJson(json);

      expect(user.id, 'user-123');
      expect(user.email, 'test@example.com');
      expect(user.emailVerified, true);
    });

    test('User.toJson serializes correctly', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        emailVerified: true,
      );

      final json = user.toJson();

      expect(json['id'], 'user-123');
      expect(json['email'], 'test@example.com');
      expect(json['emailVerified'], true);
    });

    test('AuthResponse.fromJson parses correctly', () {
      final expiresAt = DateTime.now().add(const Duration(hours: 1));
      final json = {
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'expiresAt': expiresAt.toIso8601String(),
        'user': {
          'id': 'user-123',
          'email': 'test@example.com',
          'emailVerified': false,
        },
      };

      final response = AuthResponse.fromJson(json);

      expect(response.accessToken, 'access-token');
      expect(response.refreshToken, 'refresh-token');
      expect(response.user.email, 'test@example.com');
    });

    test('AuthError.fromJson parses error codes correctly', () {
      final testCases = [
        {
          'error': 'invalid_credentials',
          'expected': AuthErrorType.invalidCredentials,
        },
        {'error': 'user_exists', 'expected': AuthErrorType.userExists},
        {'error': 'invalid_request', 'expected': AuthErrorType.invalidRequest},
        {
          'error': 'account_disabled',
          'expected': AuthErrorType.accountDisabled,
        },
        {'error': 'invalid_token', 'expected': AuthErrorType.invalidToken},
        {'error': 'internal_error', 'expected': AuthErrorType.serverError},
        {'error': 'unknown_error', 'expected': AuthErrorType.unknown},
      ];

      for (final testCase in testCases) {
        final error = AuthError.fromJson({
          'error': testCase['error'],
          'message': 'Test message',
        });
        expect(
          error.type,
          testCase['expected'],
          reason: 'Failed for ${testCase['error']}',
        );
      }
    });

    test(
      'StoredAuthState.isAccessTokenExpired returns true for expired tokens',
      () {
        final expiredState = StoredAuthState(
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
          user: User(id: '1', email: 'test@test.com', emailVerified: false),
        );

        expect(expiredState.isAccessTokenExpired, true);
      },
    );

    test(
      'StoredAuthState.isAccessTokenExpired returns true for tokens expiring soon',
      () {
        final soonExpiringState = StoredAuthState(
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(
            const Duration(minutes: 3),
          ), // Less than 5 min buffer
          user: User(id: '1', email: 'test@test.com', emailVerified: false),
        );

        expect(soonExpiringState.isAccessTokenExpired, true);
      },
    );

    test(
      'StoredAuthState.isAccessTokenExpired returns false for valid tokens',
      () {
        final validState = StoredAuthState(
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          user: User(id: '1', email: 'test@test.com', emailVerified: false),
        );

        expect(validState.isAccessTokenExpired, false);
      },
    );
  });

  group('ForgotPasswordRequest', () {
    test('toJson returns correct map', () {
      final request = ForgotPasswordRequest(email: 'test@example.com');
      final json = request.toJson();

      expect(json, {'email': 'test@example.com'});
    });
  });

  group('SecureStorageService', () {
    late SecureStorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = SecureStorageService();
      await storage.init();
    });

    tearDown(() async {
      await storage.clearAuthState();
    });

    test('saveAuthState and getAuthState work correctly', () async {
      final state = StoredAuthState(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: User(
          id: 'user-123',
          email: 'test@example.com',
          emailVerified: true,
        ),
      );

      await storage.saveAuthState(state);
      final retrieved = await storage.getAuthState();

      expect(retrieved, isNotNull);
      expect(retrieved!.accessToken, 'access-token');
      expect(retrieved.refreshToken, 'refresh-token');
      expect(retrieved.user.email, 'test@example.com');
    });

    test('isAuthenticated returns true when auth state exists', () async {
      final state = StoredAuthState(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: User(
          id: 'user-123',
          email: 'test@example.com',
          emailVerified: false,
        ),
      );

      await storage.saveAuthState(state);
      expect(await storage.isAuthenticated(), true);
    });

    test('isAuthenticated returns false when no auth state', () async {
      expect(await storage.isAuthenticated(), false);
    });

    test('clearAuthState removes all auth data', () async {
      final state = StoredAuthState(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: User(
          id: 'user-123',
          email: 'test@example.com',
          emailVerified: false,
        ),
      );

      await storage.saveAuthState(state);
      expect(await storage.isAuthenticated(), true);

      await storage.clearAuthState();
      expect(await storage.isAuthenticated(), false);
    });

    test('updateTokens updates tokens while preserving user', () async {
      final initialState = StoredAuthState(
        accessToken: 'old-access-token',
        refreshToken: 'old-refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: User(
          id: 'user-123',
          email: 'test@example.com',
          emailVerified: true,
        ),
      );

      await storage.saveAuthState(initialState);

      final newExpiresAt = DateTime.now().add(const Duration(hours: 2));
      await storage.updateTokens(
        accessToken: 'new-access-token',
        refreshToken: 'new-refresh-token',
        expiresAt: newExpiresAt,
      );

      final updated = await storage.getAuthState();
      expect(updated!.accessToken, 'new-access-token');
      expect(updated.refreshToken, 'new-refresh-token');
      expect(updated.user.email, 'test@example.com'); // User preserved
    });

    test('needsTokenRefresh returns true for expired tokens', () async {
      final expiredState = StoredAuthState(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        user: User(
          id: 'user-123',
          email: 'test@example.com',
          emailVerified: false,
        ),
      );

      await storage.saveAuthState(expiredState);
      expect(await storage.needsTokenRefresh(), true);
    });

    test('needsTokenRefresh returns false for valid tokens', () async {
      final validState = StoredAuthState(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: User(
          id: 'user-123',
          email: 'test@example.com',
          emailVerified: false,
        ),
      );

      await storage.saveAuthState(validState);
      expect(await storage.needsTokenRefresh(), false);
    });
  });
}
