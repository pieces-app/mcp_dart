/// dart:io HTTP Adapter Implementation
/// 
/// Wraps dart:io HttpRequest and HttpResponse to work with the HttpAdapter interface.
library;

import 'dart:async';
import 'dart:io';

import 'http_adapter.dart';

/// Adapter for dart:io HttpRequest
/// 
/// This is a straightforward delegation to the native dart:io classes.
/// Used when running the MCP server with dart:io's HttpServer.
class DartIoHttpAdapter implements HttpAdapter {
  final HttpRequest _request;
  late final DartIoHttpResponseAdapter _responseAdapter;
  
  DartIoHttpAdapter(this._request) {
    _responseAdapter = DartIoHttpResponseAdapter(_request.response);
  }
  
  @override
  String get method => _request.method;
  
  @override
  String? getHeader(String name) {
    return _request.headers.value(name);
  }
  
  @override
  ContentType? get contentType {
    return _request.headers.contentType;
  }
  
  @override
  Stream<List<int>> get bodyStream => _request;
  
  @override
  HttpResponseAdapter get response => _responseAdapter;
}

/// Adapter for dart:io HttpResponse
/// 
/// Straightforward delegation to native HttpResponse methods.
class DartIoHttpResponseAdapter implements HttpResponseAdapter {
  final HttpResponse _response;
  
  DartIoHttpResponseAdapter(this._response);
  
  @override
  set bufferOutput(bool value) {
    _response.bufferOutput = value;
  }
  
  @override
  set statusCode(int code) {
    _response.statusCode = code;
  }
  
  @override
  void setHeader(String name, String value) {
    _response.headers.set(name, value);
  }
  
  @override
  void write(String data) {
    _response.write(data);
  }
  
  @override
  Future<void> flush() {
    return _response.flush();
  }
  
  @override
  Future<void> close() {
    return _response.close();
  }
  
  @override
  Future<void> get done => _response.done;
}

