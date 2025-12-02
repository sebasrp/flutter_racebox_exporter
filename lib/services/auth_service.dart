import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/environment_config.dart';
import '../models/auth_models.dart';
import 'secure_storage_service.dart';

/// Service for handling authentication with the AVT backend
class AuthService extends ChangeNotifier {
  final http.Client _httpClient;
  final SecureStorageService _storage;

  String _baseUrl = EnvironmentConfig.getTestingUrl();

  User? _currentUser;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;

  AuthService({http.Client? httpClient, SecureStorageService? storage})
    : _httpClient = httpClient ?? http.Client(),
      _storage = storage ?? SecureStorageService();

  // Getters
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  String get baseUrl => _baseUrl;

  /// Initialize the auth service and restore session if available
  Future<void> initialize() async {
    if (_isInitialized) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _storage.init();

      // Try to restore session
      final authState = await _storage.getAuthState();
      if (authState != null) {
        // Check if token needs refresh
        if (authState.isAccessTokenExpired) {
          await _refreshToken(authState.refreshToken);
        } else {
          _currentUser = authState.user;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[AuthService] Initialization error: $e');
      }
      // Clear any corrupted state
      await _storage.clearAuthState();
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set the base URL for API calls
  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Register a new user
  Future<AuthResponse> register({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/api/v1/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          RegisterRequest(email: email, password: password).toJson(),
        ),
      );

      final responseData = _parseResponse(response);

      if (response.statusCode == 201) {
        final authResponse = AuthResponse.fromJson(responseData);
        await _saveAuthState(authResponse);
        _currentUser = authResponse.user;
        notifyListeners();
        return authResponse;
      } else {
        throw AuthError.fromJson(responseData);
      }
    } on AuthError {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('[AuthService] Register error: $e');
      }
      throw AuthError(
        type: AuthErrorType.networkError,
        message: 'Failed to connect to server: $e',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with email and password
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          LoginRequest(email: email, password: password).toJson(),
        ),
      );

      final responseData = _parseResponse(response);

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(responseData);
        await _saveAuthState(authResponse);
        _currentUser = authResponse.user;
        notifyListeners();
        return authResponse;
      } else {
        throw AuthError.fromJson(responseData);
      }
    } on AuthError {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('[AuthService] Login error: $e');
      }
      throw AuthError(
        type: AuthErrorType.networkError,
        message: 'Failed to connect to server: $e',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh the access token using the refresh token
  Future<void> refreshToken() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) {
      throw AuthError(
        type: AuthErrorType.invalidToken,
        message: 'No refresh token available',
      );
    }
    await _refreshToken(refreshToken);
  }

  /// Internal method to refresh token
  Future<void> _refreshToken(String refreshToken) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/api/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          RefreshTokenRequest(refreshToken: refreshToken).toJson(),
        ),
      );

      final responseData = _parseResponse(response);

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(responseData);
        await _saveAuthState(authResponse);
        _currentUser = authResponse.user;
        notifyListeners();
      } else {
        // Token refresh failed, clear auth state
        await logout();
        throw AuthError.fromJson(responseData);
      }
    } catch (e) {
      if (e is AuthError) rethrow;

      if (kDebugMode) {
        print('[AuthService] Token refresh error: $e');
      }
      // Don't logout on network errors, just throw
      throw AuthError(
        type: AuthErrorType.networkError,
        message: 'Failed to refresh token: $e',
      );
    }
  }

  /// Logout the current user
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      final accessToken = await _storage.getAccessToken();

      if (accessToken != null) {
        // Try to logout on server (best effort)
        try {
          await _httpClient.post(
            Uri.parse('$_baseUrl/api/v1/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
          );
        } catch (e) {
          if (kDebugMode) {
            print('[AuthService] Server logout failed (continuing anyway): $e');
          }
        }
      }
    } finally {
      // Always clear local state
      await _storage.clearAuthState();
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get the current access token (refreshing if needed)
  Future<String?> getValidAccessToken() async {
    final authState = await _storage.getAuthState();
    if (authState == null) {
      return null;
    }

    if (authState.isAccessTokenExpired) {
      try {
        await _refreshToken(authState.refreshToken);
        return await _storage.getAccessToken();
      } catch (e) {
        if (kDebugMode) {
          print('[AuthService] Failed to refresh token: $e');
        }
        return null;
      }
    }

    return authState.accessToken;
  }

  /// Save authentication state to storage
  Future<void> _saveAuthState(AuthResponse response) async {
    final state = StoredAuthState(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      expiresAt: response.expiresAt,
      user: response.user,
    );
    await _storage.saveAuthState(state);
  }

  /// Parse HTTP response and handle errors
  Map<String, dynamic> _parseResponse(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('[AuthService] Failed to parse response: ${response.body}');
      }
      throw AuthError(
        type: AuthErrorType.serverError,
        message: 'Invalid server response',
      );
    }
  }

  /// Clear any error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Dispose resources
  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
