/// HTTP Adapter Interface for mcp_dart
/// 
/// This allows StreamableHTTPServerTransport to work with both dart:io HttpRequest
/// and shelf Request/Response, enabling the server to run in different environments.
library;

import 'dart:async';
import 'dart:io' show ContentType;

/// Abstract HTTP request adapter
/// 
/// Implementations wrap different HTTP frameworks (dart:io, shelf, etc.)
/// to provide a unified interface for the MCP transport layer.
abstract class HttpAdapter {
  /// HTTP method (GET, POST, DELETE, OPTIONS, etc.)
  String get method;
  
  /// Get a header value by name (case-insensitive)
  /// Returns null if header doesn't exist
  String? getHeader(String name);
  
  /// Get the Content-Type header parsed as ContentType
  /// Returns null if header doesn't exist or can't be parsed
  ContentType? get contentType;
  
  /// Get the request body as a stream of bytes
  Stream<List<int>> get bodyStream;
  
  /// Get the response adapter for this request
  HttpResponseAdapter get response;
}

/// Abstract HTTP response adapter
/// 
/// Implementations wrap different HTTP response mechanisms to provide
/// a unified interface for writing responses.
abstract class HttpResponseAdapter {
  /// Control output buffering
  /// 
  /// Note: Some adapters may ignore this (e.g., shelf)
  /// as they handle buffering differently.
  set bufferOutput(bool value);
  
  /// Set the HTTP status code
  /// 
  /// Must be called before writing any data.
  set statusCode(int code);
  
  /// Set a response header
  /// 
  /// Must be called before writing any data.
  /// Later calls with the same name will override earlier values.
  void setHeader(String name, String value);
  
  /// Write data to the response
  /// 
  /// Data will be encoded as UTF-8 if it's a String.
  void write(String data);
  
  /// Flush any buffered data to the client
  /// 
  /// For streaming responses, this ensures data is sent immediately.
  /// Returns a Future that completes when data has been flushed.
  Future<void> flush();
  
  /// Close the response
  /// 
  /// After calling close(), no more data can be written.
  /// Returns a Future that completes when the response is fully closed.
  Future<void> close();
  
  /// Future that completes when the response is fully closed
  /// 
  /// This can be used to detect client disconnections.
  Future<void> get done;
}

