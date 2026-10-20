/// Decides what the shell does with a URL the web app navigates to or opens.
///
/// Pure logic with no plugin calls, so it is fully unit tested.
enum LinkAction {
  /// A page of Sydwalt OS itself: load it inside the WebView.
  inApp,

  /// An uploaded file served by the app (`/api/files/<id>?token=...`):
  /// download it natively, save it to Downloads and open it with the
  /// device's viewer. Android's WebView cannot display PDFs inline, so this
  /// is how "Open in a new tab" and "Preview" links work in the app.
  downloadFile,

  /// Another website, an email address or a phone number: hand it to the
  /// operating system (browser, mail app, dialler).
  external,

  /// Nothing sensible to do (javascript:, about:blank, malformed input).
  ignore,
}

class LinkPolicy {
  LinkPolicy(String serverUrl) : server = Uri.parse(normaliseServerUrl(serverUrl));

  final Uri server;

  static const _externalSchemes = {'mailto', 'tel', 'sms', 'whatsapp', 'geo'};

  /// Trims, adds https:// when no scheme was typed, and drops any trailing
  /// slash, path, query or fragment so the result is a bare origin.
  static String normaliseServerUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return s;
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null).toString();
  }

  /// Returns null when [input] is acceptable as a server address, otherwise a
  /// sentence explaining what to fix, for display under the Settings field.
  static String? validateServerUrl(String input) {
    final s = input.trim();
    if (s.isEmpty) return 'Enter the address of the Sydwalt OS server.';
    final u = Uri.tryParse(normaliseServerUrl(s));
    if (u == null || u.host.isEmpty || !u.host.contains('.') && u.host != 'localhost') {
      return 'That does not look like a web address, for example sydwalt-os.fly.dev.';
    }
    if (u.scheme != 'https' && u.scheme != 'http') {
      return 'The address must start with https://';
    }
    if (u.scheme == 'http' && !_isLocal(u.host)) {
      return 'Use https:// so sign-in details are encrypted. Plain http:// is only allowed for local testing.';
    }
    return null;
  }

  static bool _isLocal(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '10.0.2.2' ||
      host.startsWith('192.168.') ||
      host.startsWith('10.');

  bool isSameOrigin(Uri u) => u.scheme == server.scheme && u.host == server.host && u.port == server.port;

  LinkAction classify(String? raw) {
    if (raw == null || raw.trim().isEmpty) return LinkAction.ignore;
    final u = Uri.tryParse(raw.trim());
    if (u == null) return LinkAction.ignore;
    final scheme = u.scheme.toLowerCase();
    if (_externalSchemes.contains(scheme)) return LinkAction.external;
    if (scheme != 'http' && scheme != 'https') return LinkAction.ignore;
    if (!isSameOrigin(u)) return LinkAction.external;
    if (u.path.startsWith('/api/files/')) return LinkAction.downloadFile;
    return LinkAction.inApp;
  }

  /// The URL to reopen on the next launch, or null when [raw] should not be
  /// remembered (another site, an API call, a file).
  String? restorableUrl(String? raw) {
    if (raw == null) return null;
    final u = Uri.tryParse(raw);
    if (u == null || classify(raw) != LinkAction.inApp) return null;
    if (u.path.startsWith('/api/')) return null;
    return u.toString();
  }
}
