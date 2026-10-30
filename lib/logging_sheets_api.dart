import 'package:googleapis/sheets/v4.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class LoggingSheetsApi extends SheetsApi {
  LoggingSheetsApi(http.Client client, Logger logger)
    : super(_LoggingClient(client, logger));
}

class _LoggingClient extends http.BaseClient {
  final http.Client _inner;
  final Logger _logger;

  _LoggingClient(this._inner, this._logger);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();

    final http.BaseRequest outgoingRequest;
    final List<int> requestBytes;
    if (request is http.Request) {
      outgoingRequest = request;
      requestBytes = request.bodyBytes;
    } else {
      requestBytes = await request.finalize().toBytes();
      outgoingRequest = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = requestBytes;
    }

    _logger.d(
      'Sheets API request -> ${request.method} ${request.url}'
      '${_formatHeaders(request.headers)}'
      ' ${requestBytes.length} bytes',
    );

    try {
      final response = await _inner.send(outgoingRequest);
      final responseBytes = await response.stream.toBytes();

      _logger.d(
        'Sheets API response <- ${response.statusCode} '
        '${request.method} ${request.url} '
        '(${stopwatch.elapsedMilliseconds} ms)'
        '${_formatHeaders(response.headers)}'
        ' ${responseBytes.length} bytes',
      );

      return http.StreamedResponse(
        Stream.value(responseBytes),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error, stackTrace) {
      _logger.e(
        'Sheets API response <- ERROR ${request.method} ${request.url} '
        '(${stopwatch.elapsedMilliseconds} ms): $error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  String _formatHeaders(Map<String, String> headers) {
    if (headers.isEmpty) {
      return '';
    }
    final safeHeaders = <String, String>{};
    for (final entry in headers.entries) {
      safeHeaders[entry.key] = entry.key.toLowerCase() == 'authorization'
          ? '<redacted>'
          : entry.value;
    }
    return '\n  headers: $safeHeaders';
  }
}
