import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_desk/dio_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:help_desk/ticket_details_screen.dart';
import 'package:help_desk/login_screen.dart';
import 'package:help_desk/home_screen.dart';
import 'package:help_desk/app_theme.dart';
import 'dart:async';
import 'utils/logger.dart';
import 'package:help_desk/config.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Helper function for unawaited futures
void unawaited(Future<void> future) {}

/// Top-level function to handle background messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  appLogger.d('Received background FCM message with ID: ${message.messageId}');
  // Add your background message handling logic here
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  appLogger.i('App starting');
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp();

  // Register the background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  DioClient.onForceLogout = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Help Desk App',
      theme: AppTheme.lightTheme,
      home: const AuthChecker(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/ticketDetails') {
          final args = settings.arguments as Map<String, dynamic>?;
          final ticketId = args?['ticketId'] as String?;
          if (ticketId != null) {
            return MaterialPageRoute(
              builder: (context) => TicketDetailsScreen(ticketId: ticketId),
            );
          }
        }
        return null;
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
    appLogger.i('AuthChecker initState');

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
    unawaited(fetchConfig(_dio)); // Fetch config options in the background
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
      appLogger.e('Error during device ID and FCM background initialization: $e');
      // TODO: Handle background initialization errors more gracefully
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
      appLogger.e('Error during FCM initialization: $e');
      // TODO: Handle FCM initialization errors more gracefully
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
        appLogger.d('Successfully sent FCM token to server.');
      }
    } catch (e) {
      appLogger.e('Error sending FCM token to server: $e');
      // TODO: Retry sending FCM token or notify user
    }
  }

  void _handleNotificationNavigation(RemoteMessage message) {
    if (message.data['event'] == 'ticket_update') {
      final ticketId = message.data['ticket_id'];
      if (ticketId != null && mounted) {
        Navigator.of(context).pushNamed(
          '/ticketDetails',
          arguments: {'ticketId': ticketId},
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
      appLogger.e('Error during auth token check: $e');
      // TODO: Show error message to user
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
          appLogger.d('Received notification payload: ${response.payload}');
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
      // Notification ID generated from current timestamp in seconds
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title, // Notification title
      notification.body, // Notification body
      platformChannelSpecifics,
      payload: jsonEncode(message.data), // Pass notification body as payload
    );
  }

  void _handleNotificationTap(String payload) {
    // Handle the notification tap here
    appLogger.d('User tapped notification with payload: $payload');
    // Parse the payload as JSON
    try {
      final Map<String, dynamic> data = jsonDecode(payload);

      // Check if the event is 'ticket_update' and navigate accordingly
      if (data['event'] == 'ticket_update') {
      final ticketId = data['ticket_id'];
      if (ticketId != null && mounted) {
        Navigator.of(context).pushNamed(
          '/ticketDetails',
          arguments: {'ticketId': ticketId},
        );
      }
      }
    } catch (e) {
      appLogger.e('Error parsing notification payload JSON: $e');
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
