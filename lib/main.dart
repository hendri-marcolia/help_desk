import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_desk/config.dart';
import 'package:help_desk/dio_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:help_desk/ticket_details_screen.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'app_theme.dart';
import 'dart:async';

// Helper function for unawaited futures
void unawaited(Future<void> future) {}

/// Top-level function to handle background messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
  // Add your background message handling logic here
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.notification.isDenied.then((value) {
        if (value) {
          Permission.notification.request();
        }
      });
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp();

  // Register the background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Help Desk App',
      theme: AppTheme.lightTheme,
      home: const AuthChecker(), // Use AuthChecker to determine the initial screen
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});

  @override
  _AuthCheckerState createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isLoading = true;
  String? _authToken;
  String? _deviceId;
  late final Dio _dio;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  @override
  void initState() {
    super.initState();

    // Delay initialization until after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    // First check auth status as it's critical for navigation
    await _checkAuthStatus();
    
    // Initialize Dio early as it's needed for other operations
    _dio = await DioClient.getInstance(context);
    
    // Run device ID and FCM initialization in parallel
    // These are not critical for initial rendering
    unawaited(_initializeDeviceIdAndFCM());
  }

  // Separate method to run non-critical initializations in parallel
  Future<void> _initializeDeviceIdAndFCM() async {
    try {
      // Get device ID
      if (Theme.of(context).platform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      }
      
      if (_deviceId != null) {
        await _storage.write(key: 'device_id', value: _deviceId);
        // Initialize FCM only after we have device ID
        await _initializeFCM();
      }
    } catch (e) {
      print('Error in background initialization: $e');
    }
  }

  Future<void> _initializeFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    try {
      // Get FCM token and store it
      String? token = await messaging.getToken();
      if (token != null) {
        await _storage.write(key: 'fcm_token', value: token);
        // Send token to server in the background
        unawaited(_sendFcmTokenToServer(token));
      }

      // Set up token refresh listener
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await _storage.write(key: 'fcm_token', value: newToken);
        unawaited(_sendFcmTokenToServer(newToken));
      });

      // Set up message handlers
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationNavigation);
      
      // Check for initial message (app opened from terminated state)
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationNavigation(initialMessage);
      }
    } catch (e) {
      print('Error initializing FCM: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (message.notification != null) {
      _showNotification(message);
    }
  }

  Future<void> _sendFcmTokenToServer(String fcmToken) async {
    try {
      final deviceId = await _storage.read(key: 'device_id');
      if (deviceId != null) {
        await _dio.post(
          '$API_HOST/auth/fcm',
          data: {
            'device_id': deviceId,
            'fcm_token': fcmToken,
          },
        );
        print('FCM token sent to server successfully.');
      }
    } catch (e) {
      print('Failed to send FCM token to server: $e');
    }
  }

  void _handleNotificationNavigation(RemoteMessage message) {
    if (message.data['event'] == 'ticket_update') {
      final ticketId = message.data['ticket_id'];
      if (ticketId != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TicketDetailsScreen(
              ticketId: ticketId,
            ),
          ),
        );
      }
    }
  }

  Future<void> _checkAuthStatus() async {
    try {
      String? token = await _storage.read(key: 'auth_token');
      setState(() {
        _authToken = token;
        _isLoading = false;
      });
    } catch (e) {
      print('Error checking auth status: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showNotification(RemoteMessage message) async {
    // Use flutter_local_notifications to display notifications
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    dynamic notification = message.notification;

    // Initialize the plugin with a callback for notification taps
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          print('Notification payload: ${response.payload}');
          _handleNotificationTap(response.payload!);
        }
      },
    );

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'default_channel_id', // Channel ID
      'Default Channel', // Channel name
      channelDescription: 'This is the default notification channel',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique Notification ID based on timestamp
      notification.title, // Notification title
      notification.body, // Notification body
      platformChannelSpecifics,
      payload: jsonEncode(message.data), // Pass notification body as payload
    );
  }

  void _handleNotificationTap(String payload) {
    // Handle the notification tap here
    print('Notification tapped with payload: $payload');
    // Parse the payload as JSON
    try {
      final Map<String, dynamic> data = jsonDecode(payload);

      // Check if the event is 'ticket_update' and navigate accordingly
      if (data['event'] == 'ticket_update') {
      final ticketId = data['ticket_id'];
      if (ticketId != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TicketDetailsScreen(
              ticketId: ticketId,
            ),
          ),
        );
      }
      }
    } catch (e) {
      print('Error parsing notification payload: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _authToken != null ? const HomeScreen() : const LoginScreen();
  }
}
