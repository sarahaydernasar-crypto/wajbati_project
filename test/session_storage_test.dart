import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/services/api_client.dart';

void main() {
  final api = ApiClient.instance;
  const secure = FlutterSecureStorage();

  test(
    'legacy session migrates to secure storage and new sessions never use preferences',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        'wajbati.apiUrl': 'https://api.example',
        'wajbati.studentToken': 'legacy-token',
      });
      await api.init(client: MockClient((_) async => http.Response('[]', 200)));
      expect(api.studentToken, 'legacy-token');
      expect(
        await secure.read(key: 'https://api.example.wajbati.studentToken'),
        'legacy-token',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'wajbati.studentToken',
        ),
        isNull,
      );
      await api.setToken(ApiRole.student, 'new-token');
      expect(
        await secure.read(key: 'https://api.example.wajbati.studentToken'),
        'new-token',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'wajbati.studentToken',
        ),
        isNull,
      );
    },
  );

  test('changing API servers never forwards the previous session', () async {
    String? authorization;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'wajbati.apiUrl': 'https://api.example',
    });
    await api.init(
      client: MockClient((request) async {
        authorization = request.headers['Authorization'];
        return http.Response('[]', 200);
      }),
    );
    await api.setToken(ApiRole.student, 'private-token');
    await api.setBaseUrl('https://another.example');
    await api.get('/orders/mine', auth: ApiRole.student);
    expect(authorization, isNull);
    expect(api.studentToken, isNull);
  });
}
