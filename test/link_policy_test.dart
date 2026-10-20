import 'package:flutter_test/flutter_test.dart';
import 'package:sydwalt_os/src/link_policy.dart';

void main() {
  final policy = LinkPolicy('https://sydwalt-os-3f9ywa.fly.dev');
  const base = 'https://sydwalt-os-3f9ywa.fly.dev';

  group('classify', () {
    test('pages of the app stay in the WebView, including hash routes', () {
      expect(policy.classify('$base/'), LinkAction.inApp);
      expect(policy.classify('$base/index.html#/respond/a1'), LinkAction.inApp);
      expect(policy.classify('$base/#/projects'), LinkAction.inApp);
    });

    test('uploaded files are downloaded natively', () {
      expect(policy.classify('$base/api/files/f_123?token=abc'), LinkAction.downloadFile);
      expect(policy.classify('$base/api/files/f_123?token=abc&inline=1'), LinkAction.downloadFile);
    });

    test('other sites and contact links go to the operating system', () {
      expect(policy.classify('https://www.google.com/maps'), LinkAction.external);
      expect(policy.classify('mailto:someone@sydwalt.co.za'), LinkAction.external);
      expect(policy.classify('tel:+27110000000'), LinkAction.external);
    });

    test('a look-alike host or another port is not the app', () {
      expect(policy.classify('https://sydwalt-os-3f9ywa.fly.dev.evil.example/'), LinkAction.external);
      expect(policy.classify('http://sydwalt-os-3f9ywa.fly.dev/'), LinkAction.external);
      expect(policy.classify('https://sydwalt-os-3f9ywa.fly.dev:8443/'), LinkAction.external);
    });

    test('script and empty URLs are ignored', () {
      expect(policy.classify('javascript:alert(1)'), LinkAction.ignore);
      expect(policy.classify(''), LinkAction.ignore);
      expect(policy.classify(null), LinkAction.ignore);
      expect(policy.classify('blob:https://x/123'), LinkAction.ignore);
    });
  });

  group('normaliseServerUrl', () {
    test('adds https and strips paths and trailing slashes', () {
      expect(LinkPolicy.normaliseServerUrl(' sydwalt-os.fly.dev/ '), 'https://sydwalt-os.fly.dev');
      expect(LinkPolicy.normaliseServerUrl('https://sydwalt-os.fly.dev/index.html#/x'), 'https://sydwalt-os.fly.dev');
      expect(LinkPolicy.normaliseServerUrl('http://localhost:8080/'), 'http://localhost:8080');
    });
  });

  group('validateServerUrl', () {
    test('accepts real addresses', () {
      expect(LinkPolicy.validateServerUrl('sydwalt-os.fly.dev'), isNull);
      expect(LinkPolicy.validateServerUrl('https://os.sydwalt.co.za'), isNull);
      expect(LinkPolicy.validateServerUrl('http://10.0.2.2:8080'), isNull);
    });

    test('rejects empty, malformed and unencrypted public addresses', () {
      expect(LinkPolicy.validateServerUrl(''), isNotNull);
      expect(LinkPolicy.validateServerUrl('not a url'), isNotNull);
      expect(LinkPolicy.validateServerUrl('ftp://example.com'), isNotNull);
      expect(LinkPolicy.validateServerUrl('http://sydwalt-os.fly.dev'), contains('https://'));
    });
  });

  group('restorableUrl', () {
    test('remembers app pages only', () {
      expect(policy.restorableUrl('$base/#/minutes'), '$base/#/minutes');
      expect(policy.restorableUrl('$base/api/db'), isNull);
      expect(policy.restorableUrl('$base/api/files/x?token=y'), isNull);
      expect(policy.restorableUrl('https://example.com/'), isNull);
      expect(policy.restorableUrl(null), isNull);
    });
  });
}
