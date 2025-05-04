import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:help_desk/utils/author_utils.dart';
import 'config.dart';
import 'home_screen.dart';
import 'dio_client.dart';
import 'utils/logger.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late final Dio _dio;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    appLogger.i('LoginScreen initState');
    _initializeDio();
    _checkAuthToken();
    _loadStoredUsername();
  }

  Future<void> _initializeDio() async {
    _dio = await DioClient.getInstance(context); // Use DioClient
  }

  Future<void> _checkAuthToken() async {
    String? token = await _storage.read(key: 'auth_token');
    if (token != null && token.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  Future<void> _loadStoredUsername() async {
    String? storedUsername = await _storage.read(key: 'username');
    if (storedUsername != null) {
      setState(() {
        _usernameController.text = storedUsername;
        _rememberMe = true;
      });
    }
  }

  Future<void> _login({bool useCode = false}) async {
    if (useCode && (_codeController.text.isEmpty || _codeController.text.length != 6)) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit code.');
      return;
    }
    if (!useCode && (_usernameController.text.isEmpty || _passwordController.text.isEmpty)) {
      setState(() => _errorMessage = 'Username and password cannot be empty.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _dio.post(
        useCode ? '$API_HOST/auth/login-code' : '$API_HOST/auth/login',
        data: useCode
            ? {'code': _codeController.text}
            : {
                'username': _usernameController.text,
                'password': _passwordController.text,
              },
      );
      await _storage.write(key: 'auth_token', value: response.data['token']);
      await _storage.write(key: 'refresh_token', value: response.data['refresh_token']);
      await _storage.write(key: 'expires_in', value: response.data['expires_in'].toString());
      if (_rememberMe) {
        await _storage.write(key: 'username', value: _usernameController.text);
      } else {
        await _storage.delete(key: 'username');
      }

      try {
        // Fetch user data
        final userResponse = await _dio.get('$API_HOST/auth/me');
        final userData = userResponse.data;
        AuthorUtils.clearCache();
        await _storage.write(key: 'user_id', value: userData['user_id']);
        await _storage.write(key: 'username', value: userData['username']);
        await _storage.write(key: 'role', value: userData['role']);

        // Send FCM token in the background
        _sendFcmTokenInBackground();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } catch (e) {
        // Clear secure storage on failure
        await _storage.deleteAll();

        setState(() {
          _errorMessage = 'Failed to fetch user data. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        if (e is DioException) {
          try {
            final responseData = e.response?.data;
            if (responseData is String && responseData.isNotEmpty) {
              final decodedData = jsonDecode(responseData);
              if (decodedData is Map<String, dynamic> && decodedData.containsKey('error')) {
                _errorMessage = decodedData['error'];
              } else {
                _errorMessage = 'An error occurred. Please try again.';
              }
            } else {
              _errorMessage = 'An error occurred. Please try again.';
            }
          } catch (_) {
            _errorMessage = 'An error occurred. Please try again.';
          }
        } else {
          _errorMessage = 'An unexpected error occurred.$e';
        }
      });
    }
    setState(() => _isLoading = false);
    appLogger.i('Login attempt completed');
  }

  Future<void> _sendFcmTokenInBackground() async {
    try {
      final deviceId = await _storage.read(key: 'device_id');
      final fcmToken = await _storage.read(key: 'fcm_token');

      if (deviceId != null && fcmToken != null) {
        await _dio.post(
          '$API_HOST/auth/fcm',
          data: {
            'device_id': deviceId,
            'fcm_token': fcmToken,
          },
        );
      }
    } catch (e) {
      // Log or handle the error silently
      debugPrint('Failed to send FCM token: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A0F24), Color(0xFF1B2A49)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  elevation: 12,
                  shadowColor: Colors.black45,
                  color: const Color(0xFF162447),
                  child: Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.support_agent, size: 80, color: Colors.tealAccent),
                        const SizedBox(height: 10),
                        const Text(
                          'Welcome to Help Desk',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Login Code',
                            labelStyle: const TextStyle(color: Colors.tealAccent),
                            prefixIcon: const Icon(Icons.vpn_key, color: Colors.tealAccent),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading ? null : () => _login(useCode: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.black)
                              : const Text('Login with Code', style: TextStyle(fontSize: 18, color: Colors.black)),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            labelStyle: const TextStyle(color: Colors.tealAccent),
                            prefixIcon: const Icon(Icons.person, color: Colors.tealAccent),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(color: Colors.tealAccent),
                            prefixIcon: const Icon(Icons.lock, color: Colors.tealAccent),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.tealAccent),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _isLoading ? null : () => _login(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.black)
                              : const Text('Login', style: TextStyle(fontSize: 18, color: Colors.black)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
