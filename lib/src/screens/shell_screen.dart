import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../downloads_repository.dart';
import '../file_actions.dart';
import '../file_naming.dart';
import '../link_policy.dart';
import '../settings_store.dart';
import '../transfers.dart';
import '../widgets/error_view.dart';
import '../widgets/transfer_banner.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';

/// The whole app: Sydwalt OS in a WebView, plus the native pieces a WebView
/// lacks (downloads, printing, external links, error and loading states).
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.settings, required this.downloads});

  final SettingsStore settings;
  final DownloadsRepository downloads;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  InAppWebViewController? _web;
  final TransferTracker _transfers = TransferTracker();
  final Map<String, int> _pageTransfers = {};
  // Tokens whose bytes (or failure) arrived first, so a late "started" message
  // cannot leave a progress row behind that nothing will ever clear.
  final Set<String> _settledTokens = {};
  late LinkPolicy _policy;
  late String _server;
  String? _bridgeSource;

  int _progress = 0;
  bool _firstLoadDone = false;
  ShellError? _error;
  int _unseenDownloads = 0;

  @override
  void initState() {
    super.initState();
    _server = widget.settings.serverUrl;
    _policy = LinkPolicy(_server);
    widget.settings.addListener(_onSettingsChanged);
    rootBundle.loadString('assets/bridge.js').then((s) {
      if (mounted) setState(() => _bridgeSource = s);
    });
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _transfers.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (widget.settings.serverUrl == _server) return;
    setState(() {
      _server = widget.settings.serverUrl;
      _policy = LinkPolicy(_server);
      _error = null;
      _firstLoadDone = false;
    });
    _web?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.settings.startUrl)));
  }

  /* ------------------------------------------------------------ messages */

  void _toast(String message, {SnackBarAction? action, bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: Duration(seconds: action == null ? 4 : 6),
      ),
    );
  }

  void _announceSaved(DownloadedFile file) {
    if (!mounted) return;
    setState(() => _unseenDownloads++);
    _toast(
      'Saved to Downloads: ${file.name}',
      action: SnackBarAction(label: 'Open', onPressed: () => FileActions.open(context, file)),
    );
  }

  /* --------------------------------------------------- bridge handlers */

  void _registerHandlers(InAppWebViewController c) {
    c.addJavaScriptHandler(
      handlerName: 'downloadStarted',
      callback: (args) {
        final m = _arg(args);
        final token = '${m['token'] ?? ''}';
        if (_settledTokens.remove(token)) return true;
        _pageTransfers[token] = _transfers.start('${m['name'] ?? ''}');
        return true;
      },
    );

    c.addJavaScriptHandler(
      handlerName: 'download',
      callback: (args) async {
        final m = _arg(args);
        final id = _settle('${m['token'] ?? ''}');
        try {
          final b64 = '${m['base64'] ?? ''}';
          // Decoding a multi-megabyte export off the UI thread keeps scrolling smooth.
          final bytes = b64.length > 512 * 1024 ? await compute(base64Decode, b64) : base64Decode(b64);
          final file = await widget.downloads.save(bytes, '${m['name'] ?? ''}', mime: m['mime'] as String?);
          _announceSaved(file);
          return {'ok': true, 'name': file.name};
        } catch (e) {
          _toast('Could not save ${m['name'] ?? 'the file'}: $e', error: true);
          return {'ok': false, 'error': '$e'};
        } finally {
          if (id != null) _transfers.finish(id);
        }
      },
    );

    c.addJavaScriptHandler(
      handlerName: 'downloadFailed',
      callback: (args) {
        final m = _arg(args);
        final id = _settle('${m['token'] ?? ''}');
        if (id != null) _transfers.finish(id);
        final name = '${m['name'] ?? ''}'.trim();
        _toast(
          'Download failed${name.isEmpty ? '' : ' ($name)'}: ${m['message'] ?? 'unknown error'}. Check your connection and try again.',
          error: true,
        );
        return true;
      },
    );

    c.addJavaScriptHandler(
      handlerName: 'openUrl',
      callback: (args) async {
        await _handleUrl('${_arg(args)['url'] ?? ''}');
        return true;
      },
    );

    c.addJavaScriptHandler(
      handlerName: 'print',
      callback: (args) async {
        final title = '${_arg(args)['title'] ?? 'Sydwalt OS'}';
        try {
          await c.printCurrentPage(settings: PrintJobSettings(jobName: title));
        } catch (e) {
          _toast('Printing is not available on this device: $e', error: true);
        }
        return true;
      },
    );
  }

  /// Ends tracking for a page download: returns its progress row, or records
  /// the token when the "started" message has not arrived yet.
  int? _settle(String token) {
    final id = _pageTransfers.remove(token);
    if (id == null) _settledTokens.add(token);
    return id;
  }

  Map<String, dynamic> _arg(List<dynamic> args) =>
      args.isNotEmpty && args.first is Map ? Map<String, dynamic>.from(args.first as Map) : const {};

  /* ------------------------------------------------------------ routing */

  Future<void> _handleUrl(String url) async {
    switch (_policy.classify(url)) {
      case LinkAction.inApp:
        await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      case LinkAction.downloadFile:
        await _downloadAndOpen(url);
      case LinkAction.external:
        await _openExternally(url);
      case LinkAction.ignore:
        break;
    }
  }

  Future<void> _openExternally(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (!ok) _toast('No app on this device can open $url', error: true);
  }

  /// Uploaded files (`/api/files/<id>?token=...`). The token in the URL is the
  /// file's own access key, so no sign-in header is needed here.
  Future<void> _downloadAndOpen(String url, {String? suggestedName}) async {
    final uri = Uri.parse(url);
    final id = _transfers.start(suggestedName ?? 'file');
    final client = http.Client();
    try {
      final req = http.Request('GET', uri.replace(queryParameters: {...uri.queryParameters}..remove('inline')));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw HttpExceptionWithStatus(res.statusCode);
      }
      final total = res.contentLength;
      final bytes = <int>[];
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        bytes.addAll(chunk);
        if (total != null && total > 0) _transfers.update(id, bytes.length / total);
      }
      final name =
          FileNaming.fromContentDisposition(res.headers['content-disposition']) ??
          suggestedName ??
          Uri.decodeComponent(uri.pathSegments.isEmpty ? 'file' : uri.pathSegments.last);
      final file = await widget.downloads.save(bytes, name, mime: res.headers['content-type']);
      if (!mounted) return;
      setState(() => _unseenDownloads++);
      await FileActions.open(context, file);
    } on TimeoutException {
      _toast(
        'The download timed out. Check your connection and try again.',
        error: true,
        action: SnackBarAction(label: 'Retry', onPressed: () => _downloadAndOpen(url)),
      );
    } on HttpExceptionWithStatus catch (e) {
      _toast(
        e.status == 404 || e.status == 403
            ? 'That file is no longer available, or you no longer have access to it.'
            : 'The server could not send the file (HTTP ${e.status}).',
        error: true,
      );
    } catch (e) {
      _toast(
        'Download failed: $e',
        error: true,
        action: SnackBarAction(label: 'Retry', onPressed: () => _downloadAndOpen(url)),
      );
    } finally {
      client.close();
      _transfers.finish(id);
    }
  }

  /* ------------------------------------------------------- navigation */

  Future<NavigationActionPolicy> _shouldOverride(InAppWebViewController c, NavigationAction action) async {
    final url = action.request.url?.toString();
    if (action.isForMainFrame == false || url == null) return NavigationActionPolicy.ALLOW;
    if (url.startsWith('about:')) return NavigationActionPolicy.ALLOW;
    switch (_policy.classify(url)) {
      case LinkAction.inApp:
        return NavigationActionPolicy.ALLOW;
      case LinkAction.downloadFile:
        unawaited(_downloadAndOpen(url));
        return NavigationActionPolicy.CANCEL;
      case LinkAction.external:
        unawaited(_openExternally(url));
        return NavigationActionPolicy.CANCEL;
      case LinkAction.ignore:
        return NavigationActionPolicy.CANCEL;
    }
  }

  Future<void> _goBack() async {
    final c = _web;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  void _retry() {
    setState(() => _error = null);
    final c = _web;
    if (c == null) return;
    if (_firstLoadDone) {
      c.reload();
    } else {
      c.loadUrl(urlRequest: URLRequest(url: WebUri(widget.settings.startUrl)));
    }
  }

  Future<void> _openDownloads() async {
    setState(() => _unseenDownloads = 0);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(repository: widget.downloads)));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: widget.settings, onClearWebData: _clearWebData),
      ),
    );
  }

  /// Signs out and removes everything the web app stored on this device.
  Future<void> _clearWebData() async {
    await CookieManager.instance().deleteAllCookies();
    // localStorage holds the sign-in token and the offline copy of the book.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await WebStorageManager.instance().deleteAllData();
    } else {
      await WebStorageManager.instance().removeDataModifiedSince(
        dataTypes: WebsiteDataType.ALL.toSet(),
        date: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    await _web?.clearHistory();
    await InAppWebViewController.clearAllCache();
    await widget.settings.forgetLastUrl();
    setState(() {
      _firstLoadDone = false;
      _error = null;
    });
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri('$_server/')));
  }

  /* -------------------------------------------------------------- UI */

  @override
  Widget build(BuildContext context) {
    final bridge = _bridgeSource;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 48,
          titleSpacing: 12,
          title: const Text('Sydwalt OS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: SizedBox(
              height: 2,
              child: _progress < 100 && _error == null
                  ? LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2)
                  : null,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Downloads',
              onPressed: _openDownloads,
              icon: Badge(
                isLabelVisible: _unseenDownloads > 0,
                label: Text('$_unseenDownloads'),
                child: const Icon(Icons.download_outlined),
              ),
            ),
            IconButton(tooltip: 'Reload', onPressed: _retry, icon: const Icon(Icons.refresh)),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                switch (v) {
                  case 'settings':
                    await _openSettings();
                  case 'browser':
                    final u = await _web?.getUrl();
                    await _openExternally((u ?? WebUri('$_server/')).toString());
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'browser', child: Text('Open this page in the browser')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              if (bridge != null)
                InAppWebView(
                  key: const ValueKey('sydwalt-webview'),
                  initialUrlRequest: URLRequest(url: WebUri(widget.settings.startUrl)),
                  initialUserScripts: UnmodifiableListView([
                    UserScript(source: bridge, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
                  ]),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    cacheEnabled: true,
                    useShouldOverrideUrlLoading: true,
                    useOnDownloadStart: true,
                    supportMultipleWindows: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    allowFileAccess: false,
                    allowContentAccess: true,
                    mediaPlaybackRequiresUserGesture: true,
                    applicationNameForUserAgent: AppConfig.userAgentSuffix,
                    isTextInteractionEnabled: true,
                    supportZoom: false,
                    builtInZoomControls: false,
                    displayZoomControls: false,
                    transparentBackground: false,
                    disableDefaultErrorPage: true,
                    allowsBackForwardNavigationGestures: true,
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                  ),
                  onWebViewCreated: (c) {
                    _web = c;
                    _registerHandlers(c);
                  },
                  onLoadStart: (c, url) => setState(() => _progress = 0),
                  onProgressChanged: (c, p) => setState(() => _progress = p),
                  onLoadStop: (c, url) {
                    setState(() {
                      _progress = 100;
                      if (_error == null) _firstLoadDone = true;
                    });
                  },
                  onUpdateVisitedHistory: (c, url, isReload) => widget.settings.rememberUrl(url?.toString()),
                  shouldOverrideUrlLoading: _shouldOverride,
                  onCreateWindow: (c, action) async {
                    // Fallback for windows the bridge's window.open() shim did not catch.
                    final url = action.request.url?.toString();
                    if (url != null && url.isNotEmpty && url != 'about:blank') await _handleUrl(url);
                    return false;
                  },
                  onDownloadStartRequest: (c, req) {
                    final url = req.url.toString();
                    if (url.startsWith('http')) {
                      _policy.isSameOrigin(req.url)
                          ? _downloadAndOpen(url, suggestedName: req.suggestedFilename)
                          : _openExternally(url);
                    } else {
                      _toast(
                        'This download could not be saved in the app. Use "Open this page in the browser" from the menu.',
                        error: true,
                      );
                    }
                  },
                  onReceivedError: (c, request, error) {
                    if (request.isForMainFrame == false) return;
                    if (error.type == WebResourceErrorType.CANCELLED) return;
                    setState(() => _error = ShellError.network(error.description));
                  },
                  onReceivedHttpError: (c, request, response) {
                    final status = response.statusCode ?? 0;
                    if (request.isForMainFrame != true || status < 500) return;
                    setState(() => _error = ShellError.server(status));
                  },
                  onRenderProcessGone: (c, detail) => c.reload(),
                  onWebContentProcessDidTerminate: (c) => c.reload(),
                ),
              if (!_firstLoadDone && _error == null) _StartingUp(server: _server),
              if (_error != null)
                ErrorView(
                  error: _error!,
                  server: _server,
                  onRetry: _retry,
                  onOpenDownloads: _openDownloads,
                  onOpenSettings: _openSettings,
                ),
              Positioned(left: 0, right: 0, bottom: 0, child: TransferBanner(tracker: _transfers)),
            ],
          ),
        ),
      ),
    );
  }
}

class HttpExceptionWithStatus implements Exception {
  HttpExceptionWithStatus(this.status);
  final int status;
  @override
  String toString() => 'HTTP $status';
}

/// Shown until the first page finishes loading. Fly.io suspends the server
/// when idle, so the first open of the day can take several seconds.
class _StartingUp extends StatelessWidget {
  const _StartingUp({required this.server});
  final String server;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(AppConfig.brandColor),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/icon/logo-white.png', width: 180),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                ),
                const SizedBox(height: 16),
                const Text('Connecting to Sydwalt OS…', style: TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 6),
                Text(
                  'The first open of the day can take a few seconds while the server wakes up.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
