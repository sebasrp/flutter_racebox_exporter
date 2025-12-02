import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_models.dart';

/// Service for securely storing authentication tokens
///
/// Note: For production, consider using flutter_secure_storage for native platforms.
/// This implementation uses SharedPreferences which is suitable for development
/// and works across all platforms including web.
class SecureStorageService {
  static const String _authStateKey = 'auth_state';
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  SharedPreferences? _prefs;

  /// Initialize the storage service
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Ensure prefs is initialized
  Future<SharedPreferences> _getPrefs() async {
    if (_prefs == null) {
      await init();
    }
    return _prefs!;
  }

  /// Save authentication state
  Future<void> saveAuthState(StoredAuthState state) async {
    final prefs = await _getPrefs();
    final jsonString = jsonEncode(state.toJson());
    await prefs.setString(_authStateKey, jsonString);

    if (kDebugMode) {
      print(
        '[SecureStorageService] Auth state saved for user: ${state.user.email}',
      );
    }
  }

  /// Get stored authentication state
  Future<StoredAuthState?> getAuthState() async {
    final prefs = await _getPrefs();
    final jsonString = prefs.getString(_authStateKey);

    if (jsonString == null) {
      return null;
    }

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return StoredAuthState.fromJson(json);
    } catch (e) {
      if (kDebugMode) {
        print('[SecureStorageService] Error parsing auth state: $e');
      }
      // Clear corrupted data
      await clearAuthState();
      return null;
    }
  }

  /// Update tokens after refresh
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) async {
    final currentState = await getAuthState();
    if (currentState == null) {
      throw Exception('No auth state to update');
    }

    final newState = StoredAuthState(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      user: currentState.user,
    );

    await saveAuthState(newState);
  }

  /// Get access token
  Future<String?> getAccessToken() async {
    final state = await getAuthState();
    return state?.accessToken;
  }

  /// Get refresh token
  Future<String?> getRefreshToken() async {
    final state = await getAuthState();
    return state?.refreshToken;
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final state = await getAuthState();
    return state != null;
  }

  /// Check if access token needs refresh
  Future<bool> needsTokenRefresh() async {
    final state = await getAuthState();
    if (state == null) {
      return false;
    }
    return state.isAccessTokenExpired;
  }

  /// Clear all authentication data
  Future<void> clearAuthState() async {
    final prefs = await _getPrefs();
    await prefs.remove(_authStateKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);

    if (kDebugMode) {
      print('[SecureStorageService] Auth state cleared');
    }
  }

  /// Get stored user
  Future<User?> getUser() async {
    final state = await getAuthState();
    return state?.user;
  }
}
