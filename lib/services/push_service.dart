import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Optional mobile push. No Firebase project is required to run the app.
class PushService {
  PushService._();
  static final instance = PushService._();
  static const enabled = bool.fromEnvironment('ENABLE_PUSH');
  bool ready = false;
  bool _registering = false;
  bool _signingOut = false;
  Completer<void>? _registration;
  String? _deviceToken;
  String? _registeredSession;
  final _openedOrders = StreamController<String>.broadcast();
  final _updates = StreamController<void>.broadcast();
  Stream<String> get openedOrders => _openedOrders.stream;
  Stream<void> get updates => _updates.stream;
  String? pendingOrderId;

  Future<void> init() async {
    if (!enabled ||
        kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    try {
      const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
      const appId = String.fromEnvironment('FIREBASE_APP_ID');
      const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
      const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
      if ([projectId, appId, apiKey, senderId].any((s) => s.isEmpty)) {
        debugPrint('Push disabled: Firebase configuration is incomplete.');
        return;
      }
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: senderId,
          projectId: projectId,
          iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
        ),
      );
      FirebaseMessaging.onMessage.listen((_) => _updates.add(null));
      FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _deviceToken = token;
        _registeredSession = null;
        unawaited(registerDevice());
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openMessage(initial);
      ready = true;
    } catch (e) {
      debugPrint('Push initialization failed: $e');
    }
  }

  void _openMessage(RemoteMessage message) {
    final id = message.data['order_id'];
    if (id is! String || !RegExp(r'^\d{6}$').hasMatch(id)) return;
    pendingOrderId = id;
    _openedOrders.add(id);
  }

  Future<void> registerDevice() async {
    final api = ApiClient.instance;
    final session = api.studentToken;
    if (!ready ||
        session == null ||
        _registeredSession == session ||
        _registering ||
        _signingOut) {
      return;
    }
    _registering = true;
    _registration = Completer<void>();
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      if (_signingOut) return;
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        return;
      }
      _deviceToken ??= await FirebaseMessaging.instance.getToken();
      if (_deviceToken == null || api.studentToken != session) return;
      final registeredToken = _deviceToken;
      await api.post(
        '/devices',
        auth: ApiRole.student,
        body: {
          'token': _deviceToken,
          'platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        },
      );
      if (api.studentToken == session && _deviceToken == registeredToken) {
        _registeredSession = session;
      }
    } catch (e) {
      // A later refresh retries without blocking login or checkout.
      debugPrint('Device registration failed: $e');
    } finally {
      _registering = false;
      _registration?.complete();
    }
  }

  Future<void> unregisterDevice() async {
    _signingOut = true;
    _registeredSession = null;
    pendingOrderId = null;
    if (!ready || (_deviceToken == null && !_registering)) {
      _signingOut = false;
      return;
    }
    try {
      await _registration?.future;
      if (_deviceToken != null && ApiClient.instance.studentToken != null) {
        await ApiClient.instance.post(
          '/devices/unregister',
          auth: ApiRole.student,
          body: {'token': _deviceToken},
        );
      }
    } catch (e) {
      debugPrint('Device unregister failed: $e');
    } finally {
      // Stop delivery to the old token even if the API is temporarily offline.
      try {
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
      _deviceToken = null;
      _signingOut = false;
    }
  }
}
