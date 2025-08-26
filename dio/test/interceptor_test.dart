import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/src/dio_mixin.dart';
import 'package:dio/src/interceptors/imply_content_type.dart';
import 'package:test/test.dart';

import 'mock/adapters.dart';

/// Custom interceptor example that tracks the number of requests.
/// Demonstrates how to create a simple interceptor by extending the base Interceptor class.
class MyInterceptor extends Interceptor {
  int requestCount = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requestCount++;
    return super.onRequest(options, handler);
  }
}

void main() {
  /// Tests that handlers throw StateError when called multiple times.
  /// This is a critical safety feature that prevents interceptors from
  /// inadvertently calling handler methods multiple times, which could
  /// lead to undefined behavior or resource leaks.
  test('Throws precise StateError for duplicate calls', () async {
    const message = 'The `handler` has already been called, '
        'make sure each handler gets called only once.';
        
    // Test case 1: Duplicate handler.next() calls in request interceptor
    final duplicateRequestCallsDio = Dio()
      ..options.baseUrl = MockAdapter.mockBase
      ..httpClientAdapter = MockAdapter()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.next(options);  // First call - valid
            handler.next(options);  // Second call - should throw StateError
          },
        ),
      );
      
    // Test case 2: Duplicate handler.resolve() calls in response interceptor  
    final duplicateResponseCalls = Dio()
      ..options.baseUrl = MockAdapter.mockBase
      ..httpClientAdapter = MockAdapter()
      ..interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            handler.resolve(response);  // First call - valid
            handler.resolve(response);  // Second call - should throw StateError
          },
        ),
      );
      
    // Test case 3: Duplicate handler.resolve() calls in error interceptor
    final duplicateErrorCalls = Dio()
      ..options.baseUrl = MockAdapter.mockBase
      ..httpClientAdapter = MockAdapter()
      ..interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            handler.resolve(Response(requestOptions: error.requestOptions));  // First call - valid
            handler.resolve(Response(requestOptions: error.requestOptions));  // Second call - should throw StateError
          },
        ),
      );
    // Verify that all three scenarios throw the expected StateError
    // with the correct message about handler being called multiple times
    await expectLater(
      duplicateRequestCallsDio.get('/test'),
      throwsA(
        allOf([
          isA<DioException>(),
          (DioException e) => e.error is StateError,
          (DioException e) => (e.error as StateError).message == message,
        ]),
      ),
    );
    await expectLater(
      duplicateResponseCalls.get('/test'),
      throwsA(
        allOf([
          isA<DioException>(),
          (DioException e) => e.error is StateError,
          (DioException e) => (e.error as StateError).message == message,
        ]),
      ),
    );
    await expectLater(
      duplicateErrorCalls.get('/'),
      throwsA(
        allOf([
          isA<DioException>(),
          (DioException e) => e.error is StateError,
          (DioException e) => (e.error as StateError).message == message,
        ]),
      ),
    );
  });

  /// Tests the InterceptorState class functionality.
  /// InterceptorState is used internally to pass data and execution state
  /// between interceptors in the processing chain.
  group('InterceptorState', () {
    /// Tests the toString() method provides useful debugging information
    /// including the type parameter, result type, and contained data.
    test('toString()', () {
      final data = DioException(requestOptions: RequestOptions());
      final state = InterceptorState<DioException>(data);
      expect(
        state.toString(),
        'InterceptorState<DioException>('
        'type: InterceptorResultType.next, '
        'data: DioException [unknown]: null'
        ')',
      );
    });
  });

  /// Tests for request interceptor functionality and behavior.
  /// Request interceptors can modify options, resolve with responses,
  /// or reject with errors before the actual network request is made.
  group('Request Interceptor', () {
    /// Tests the full interceptor chain with various handler method combinations.
    /// This comprehensive test demonstrates how different handler methods
    /// (next, resolve, reject) with different callFollowing flags affect
    /// the execution flow through multiple interceptors.
    test('interceptor chain', () async {
      final dio = Dio();
      dio.options.baseUrl = EchoAdapter.mockBase;
      dio.httpClientAdapter = EchoAdapter();
      dio.interceptors
        ..add(
          // First interceptor: Request processing with various actions
          InterceptorsWrapper(
            onRequest: (reqOpt, handler) {
              switch (reqOpt.path) {
                case '/resolve':
                  // Resolve immediately, skip network and following interceptors
                  handler.resolve(Response(requestOptions: reqOpt, data: 1));
                  break;
                case '/resolve-next':
                  // Resolve but call following response interceptors
                  handler.resolve(
                    Response(requestOptions: reqOpt, data: 2),
                    true,  // callFollowingResponseInterceptor = true
                  );
                  break;
                case '/resolve-next/always':
                  // Resolve with callFollowing to test response processing
                  handler.resolve(
                    Response(requestOptions: reqOpt, data: 2),
                    true,
                  );
                  break;
                case '/resolve-next/reject':
                  // Resolve then test error handling in response interceptor
                  handler.resolve(
                    Response(requestOptions: reqOpt, data: 2),
                    true,
                  );
                  break;
                case '/resolve-next/reject-next':
                  // Complex flow: resolve, then error handling with callFollowing
                  handler.resolve(
                    Response(requestOptions: reqOpt, data: 2),
                    true,
                  );
                  break;
                case '/reject':
                  // Reject immediately, skip network and following interceptors
                  handler
                      .reject(DioException(requestOptions: reqOpt, error: 3));
                  break;
                case '/reject-next':
                  // Reject but call following error interceptors
                  handler.reject(
                    DioException(requestOptions: reqOpt, error: 4),
                    true,  // callFollowingErrorInterceptor = true
                  );
                  break;
                case '/reject-next/reject':
                  // Reject with callFollowing to test error processing
                  handler.reject(
                    DioException(requestOptions: reqOpt, error: 5),
                    true,
                  );
                  break;
                case '/reject-next-response':
                  // Test error recovery in response interceptor
                  handler.reject(
                    DioException(requestOptions: reqOpt, error: 5),
                    true,
                  );
                  break;
                default:
                  // Continue normal processing
                  handler.next(reqOpt);
              }
            },
            // Response interceptor: Processes responses from request interceptor
            onResponse: (response, ResponseInterceptorHandler handler) {
              final options = response.requestOptions;
              switch (options.path) {
                case '/resolve':
                  // This should never execute due to immediate resolve above
                  throw 'unexpected1';
                case '/resolve-next':
                  // Modify response data and resolve
                  response.data++;
                  handler.resolve(response); //3
                  break;
                case '/resolve-next/always':
                  // Modify response and continue to next interceptor
                  response.data++;
                  handler.next(response); //3
                  break;
                case '/resolve-next/reject':
                  // Demonstrate error injection in response interceptor
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      error: '/resolve-next/reject',
                    ),
                  );
                  break;
                case '/resolve-next/reject-next':
                  handler.reject(
                    DioException(requestOptions: options, error: ''),
                    true,
                  );
                  break;
                default:
                  handler.next(response); //continue
              }
            },
            onError: (error, handler) {
              if (error.requestOptions.path == '/reject-next-response') {
                handler.resolve(
                  Response(
                    requestOptions: error.requestOptions,
                    data: 100,
                  ),
                );
              } else if (error.requestOptions.path ==
                  '/resolve-next/reject-next') {
                handler.next(error.copyWith(error: 1));
              } else {
                if (error.requestOptions.path == '/reject-next/reject') {
                  handler.reject(error);
                } else {
                  int count = error.error as int;
                  count++;
                  handler.next(error.copyWith(error: count));
                }
              }
            },
          ),
        )
        ..add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.next(options),
            onResponse: (response, handler) {
              final options = response.requestOptions;
              switch (options.path) {
                case '/resolve-next/always':
                  response.data++;
                  handler.next(response); //4
                  break;
                default:
                  handler.next(response); //continue
              }
            },
            onError: (error, handler) {
              if (error.requestOptions.path == '/resolve-next/reject-next') {
                int count = error.error as int;
                count++;
                handler.next(error.copyWith(error: count));
              } else {
                int count = error.error as int;
                count++;
                handler.next(error.copyWith(error: count));
              }
            },
          ),
        );
      Response response = await dio.get('/resolve');
      expect(response.data, 1);
      response = await dio.get('/resolve-next');

      expect(response.data, 3);

      response = await dio.get('/resolve-next/always');
      expect(response.data, 4);

      response = await dio.post('/post', data: 'xxx');
      expect(response.data, 'xxx');

      response = await dio.get('/reject-next-response');
      expect(response.data, 100);

      expect(
        dio.get('/reject').catchError((e) => throw e.error as num),
        throwsA(3),
      );

      expect(
        dio.get('/reject-next').catchError((e) => throw e.error as num),
        throwsA(6),
      );

      expect(
        dio.get('/reject-next/reject').catchError((e) => throw e.error as num),
        throwsA(5),
      );

      expect(
        dio
            .get('/resolve-next/reject')
            .catchError((e) => throw e.error as Object),
        throwsA('/resolve-next/reject'),
      );

      expect(
        dio
            .get('/resolve-next/reject-next')
            .catchError((e) => throw e.error as num),
        throwsA(2),
      );
    });

    test('unexpected error', () async {
      final dio = Dio();
      dio.options.baseUrl = EchoAdapter.mockBase;
      dio.httpClientAdapter = EchoAdapter();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (reqOpt, handler) {
            if (reqOpt.path == '/error') {
              throw 'unexpected';
            }
            handler.next(reqOpt.copyWith(path: '/xxx'));
          },
          onError: (error, handler) {
            handler.next(error.copyWith(error: 'unexpected error'));
          },
        ),
      );

      expect(
        dio.get('/error').catchError((e) => throw e.error as String),
        throwsA('unexpected error'),
      );

      expect(
        dio.get('/').then((e) => throw e.requestOptions.path),
        throwsA('/xxx'),
      );
    });

    test('request interceptor', () async {
      final dio = Dio();
      dio.options.baseUrl = MockAdapter.mockBase;
      dio.httpClientAdapter = MockAdapter();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (
            RequestOptions options,
            RequestInterceptorHandler handler,
          ) {
            switch (options.path) {
              case '/fakepath1':
                handler.resolve(
                  Response(
                    requestOptions: options,
                    data: 'fake data',
                  ),
                );
                break;
              case '/fakepath2':
                dio
                    .get('/test')
                    .then(handler.resolve)
                    .catchError((e) => handler.reject(e as DioException));
                break;
              case '/fakepath3':
                handler.reject(
                  DioException(
                    requestOptions: options,
                    error: 'test error',
                  ),
                );
                break;
              case '/fakepath4':
                handler.reject(
                  DioException(
                    requestOptions: options,
                    error: 'test error',
                  ),
                );
                break;
              case '/test?tag=1':
                dio.get('/token').then((response) {
                  options.headers['token'] = response.data['data']['token'];
                  handler.next(options);
                });
                break;
              default:
                handler.next(options); //continue
            }
          },
        ),
      );

      Response response = await dio.get('/fakepath1');
      expect(response.data, 'fake data');

      response = await dio.get('/fakepath2');
      expect(response.data['errCode'], 0);

      expect(
        dio.get('/fakepath3'),
        throwsA(
          isA<DioException>()
              .having((e) => e.message, 'message', null)
              .having((e) => e.type, 'error type', DioExceptionType.unknown),
        ),
      );
      expect(
        dio.get('/fakepath4'),
        throwsA(
          isA<DioException>()
              .having((e) => e.message, 'message', null)
              .having((e) => e.type, 'error type', DioExceptionType.unknown),
        ),
      );

      response = await dio.get('/test');
      expect(response.data['errCode'], 0);
      response = await dio.get('/test?tag=1');
      expect(response.data['errCode'], 0);
    });

    test('Caught exceptions before handler called', () async {
      final dio = Dio();
      const errorMsg = 'interceptor error';
      dio.interceptors.add(
        InterceptorsWrapper(
          // TODO(EVERYONE): Remove the ignorance once we migrated to a higher version of Dart.
          // ignore: void_checks
          onRequest: (response, handler) {
            throw UnsupportedError(errorMsg);
          },
        ),
      );
      expect(
        dio.get('https://www.cloudflare.com'),
        throwsA(
          isA<DioException>().having(
            (dioException) => dioException.error,
            'Exception',
            isA<UnsupportedError>()
                .having((e) => e.message, 'message', errorMsg),
          ),
        ),
      );
    });

    group(ImplyContentTypeInterceptor, () {
      Dio createDio() {
        final dio = Dio();
        dio.options.baseUrl = EchoAdapter.mockBase;
        dio.httpClientAdapter = EchoAdapter();
        return dio;
      }

      test('is enabled by default', () async {
        final dio = createDio();
        expect(
          dio.interceptors.whereType<ImplyContentTypeInterceptor>(),
          isNotEmpty,
        );
      });

      test('can be removed with the helper method', () async {
        final dio = createDio();
        dio.interceptors.removeImplyContentTypeInterceptor();
        expect(
          dio.interceptors.whereType<ImplyContentTypeInterceptor>(),
          isEmpty,
        );
      });

      test('ignores null data', () async {
        final dio = createDio();
        final response = await dio.get('/echo');
        expect(response.requestOptions.contentType, isNull);
      });

      test('does not override existing content type', () async {
        final dio = createDio();
        final response = await dio.get(
          '/echo',
          data: 'hello',
          options: Options(headers: {'Content-Type': 'text/plain'}),
        );
        expect(response.requestOptions.contentType, 'text/plain');
      });

      test('ignores unsupported data type', () async {
        final dio = createDio();
        final response = await dio.get('/echo', data: 42);
        expect(response.requestOptions.contentType, isNull);
      });

      test('sets application/json for String instances', () async {
        final dio = createDio();
        final response = await dio.get('/echo', data: 'hello');
        expect(response.requestOptions.contentType, 'application/json');
      });

      test('sets application/json for Map instances', () async {
        final dio = createDio();
        final response = await dio.get('/echo', data: {'hello': 'there'});
        expect(response.requestOptions.contentType, 'application/json');
      });

      test('sets application/json for List<Map> instances', () async {
        final dio = createDio();
        final response = await dio.get(
          '/echo',
          data: [
            {'hello': 'here'},
            {'hello': 'there'},
          ],
        );
        expect(response.requestOptions.contentType, 'application/json');
      });

      test('sets multipart/form-data for FormData instances', () async {
        final dio = createDio();
        final response = await dio.get(
          '/echo',
          data: FormData.fromMap({'hello': 'there'}),
        );
        expect(
          response.requestOptions.contentType?.split(';').first,
          'multipart/form-data',
        );
      });
    });
  });

  group('Response interceptor', () {
    Dio dio;
    test('Response Interceptor', () async {
      const urlNotFound = '/404/';
      const urlNotFound1 = '${urlNotFound}1';
      const urlNotFound2 = '${urlNotFound}2';
      const urlNotFound3 = '${urlNotFound}3';

      dio = Dio();
      dio.httpClientAdapter = MockAdapter();
      dio.options.baseUrl = MockAdapter.mockBase;

      dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            response.data = response.data['data'];
            handler.next(response);
          },
          onError: (DioException error, ErrorInterceptorHandler handler) {
            final response = error.response;
            if (response != null) {
              switch (response.requestOptions.path) {
                case urlNotFound:
                  return handler.next(error);
                case urlNotFound1:
                  return handler.resolve(
                    Response(
                      requestOptions: error.requestOptions,
                      data: 'fake data',
                    ),
                  );
                case urlNotFound2:
                  return handler.resolve(
                    Response(
                      data: 'fake data',
                      requestOptions: error.requestOptions,
                    ),
                  );
                case urlNotFound3:
                  return handler.next(
                    error.copyWith(
                      error: 'custom error info [${response.statusCode}]',
                    ),
                  );
              }
            }
            handler.next(error);
          },
        ),
      );
      Response response = await dio.get('/test');
      expect(response.data['path'], '/test');
      expect(
        dio
            .get(urlNotFound)
            .catchError((e) => throw (e as DioException).response!.statusCode!),
        throwsA(404),
      );
      response = await dio.get('${urlNotFound}1');
      expect(response.data, 'fake data');
      response = await dio.get('${urlNotFound}2');
      expect(response.data, 'fake data');
      expect(
        dio.get('${urlNotFound}3').catchError((e) => throw e as DioException),
        throwsA(isA<DioException>()),
      );
    });
    test('multi response interceptor', () async {
      dio = Dio();
      dio.httpClientAdapter = MockAdapter();
      dio.options.baseUrl = MockAdapter.mockBase;
      dio.interceptors
        ..add(
          InterceptorsWrapper(
            onResponse: (resp, handler) {
              resp.data = resp.data['data'];
              handler.next(resp);
            },
          ),
        )
        ..add(
          InterceptorsWrapper(
            onResponse: (resp, handler) {
              resp.data['extra_1'] = 'extra';
              handler.next(resp);
            },
          ),
        )
        ..add(
          InterceptorsWrapper(
            onResponse: (resp, handler) {
              resp.data['extra_2'] = 'extra';
              handler.next(resp);
            },
          ),
        );
      final resp = await dio.get('/test');
      expect(resp.data['path'], '/test');
      expect(resp.data['extra_1'], 'extra');
      expect(resp.data['extra_2'], 'extra');
    });
  });

  group('Error Interceptor', () {
    test('handled when request cancelled', () async {
      final cancelToken = CancelToken();
      DioException? iError, qError;
      final dio = Dio()
        ..httpClientAdapter = MockAdapter()
        ..options.baseUrl = MockAdapter.mockBase
        ..interceptors.add(
          InterceptorsWrapper(
            onError: (DioException error, ErrorInterceptorHandler handler) {
              iError = error;
              handler.next(error);
            },
          ),
        )
        ..interceptors.add(
          QueuedInterceptorsWrapper(
            onError: (DioException error, ErrorInterceptorHandler handler) {
              qError = error;
              handler.next(error);
            },
          ),
        );
      Future.delayed(const Duration(seconds: 1)).then((_) {
        cancelToken.cancel('test');
      });
      await dio
          .get('/test-timeout', cancelToken: cancelToken)
          .then((_) {}, onError: (_) {});
      expect(iError, isA<DioException>());
      expect(qError, isA<DioException>());
    });
  });

  group('QueuedInterceptor', () {
    test('requests ', () async {
      String? csrfToken;
      final dio = Dio();
      int tokenRequestCounts = 0;
      // dio instance to request token
      final tokenDio = Dio();
      dio.options.baseUrl = tokenDio.options.baseUrl = MockAdapter.mockBase;
      dio.httpClientAdapter = tokenDio.httpClientAdapter = MockAdapter();
      final myInter = MyInterceptor();
      dio.interceptors.add(myInter);
      dio.interceptors.add(
        QueuedInterceptorsWrapper(
          onRequest: (options, handler) {
            if (csrfToken == null) {
              tokenRequestCounts++;
              tokenDio.get('/token').then((d) {
                options.headers['csrfToken'] =
                    csrfToken = d.data['data']['token'] as String;
                handler.next(options);
              }).catchError((e) {
                handler.reject(e as DioException, true);
              });
            } else {
              options.headers['csrfToken'] = csrfToken;
              handler.next(options);
            }
          },
        ),
      );

      int result = 0;
      void onResult(d) {
        if (tokenRequestCounts > 0) {
          ++result;
        }
      }

      await Future.wait([
        dio.get('/test?tag=1').then(onResult),
        dio.get('/test?tag=2').then(onResult),
        dio.get('/test?tag=3').then(onResult),
      ]);
      expect(tokenRequestCounts, 1);
      expect(result, 3);
      expect(myInter.requestCount, predicate((int e) => e > 0));
      // The `ImplyContentTypeInterceptor` will be replaced.
      dio.interceptors[0] = myInter;
      dio.interceptors.clear();
      expect(dio.interceptors.isEmpty, true);
    });

    test('error', () async {
      String? csrfToken;
      final dio = Dio();
      int tokenRequestCounts = 0;
      // dio instance to request token
      final tokenDio = Dio();
      dio.options.baseUrl = tokenDio.options.baseUrl = MockAdapter.mockBase;
      dio.httpClientAdapter = tokenDio.httpClientAdapter = MockAdapter();
      dio.interceptors.add(
        QueuedInterceptorsWrapper(
          onRequest: (opt, handler) {
            opt.headers['csrfToken'] = csrfToken;
            handler.next(opt);
          },
          onError: (error, handler) {
            // Assume 401 stands for token expired
            if (error.response?.statusCode == 401) {
              final options = error.response!.requestOptions;
              // If the token has been updated, repeat directly.
              if (csrfToken != options.headers['csrfToken']) {
                options.headers['csrfToken'] = csrfToken;
                //repeat
                dio
                    .fetch(options)
                    .then(handler.resolve)
                    .catchError((e) => handler.reject(e as DioException));
                return;
              }
              // update token and repeat
              tokenRequestCounts++;
              tokenDio.get('/token').then((d) {
                //update csrfToken
                options.headers['csrfToken'] =
                    csrfToken = d.data['data']['token'] as String;
              }).then((e) {
                //repeat
                dio
                    .fetch(options)
                    .then(handler.resolve)
                    .catchError((e) => handler.reject(e as DioException));
              });
            } else {
              handler.next(error);
            }
          },
        ),
      );

      int result = 0;
      void onResult(d) {
        if (tokenRequestCounts > 0) {
          ++result;
        }
      }

      await Future.wait([
        dio.get('/test-auth?tag=1').then(onResult),
        dio.get('/test-auth?tag=2').then(onResult),
        dio.get('/test-auth?tag=3').then(onResult),
      ]);
      expect(tokenRequestCounts, 1);
      expect(result, 3);
    });
  });

  /// Tests the Interceptors list management functionality.
  /// The Interceptors class extends ListMixin and provides special handling
  /// for the default ImplyContentTypeInterceptor that is automatically added.
  test('Size of Interceptors', () {
    // Test 1: Default behavior - Dio instances start with ImplyContentTypeInterceptor
    final interceptors1 = Dio().interceptors;
    expect(interceptors1.length, equals(1));  // One default interceptor
    expect(interceptors1, isNotEmpty);
    
    // Test 2: Adding interceptors increases the count
    interceptors1.add(InterceptorsWrapper());
    expect(interceptors1.length, equals(2));  // Default + custom interceptor
    expect(interceptors1, isNotEmpty);
    
    // Test 3: clear() by default keeps ImplyContentTypeInterceptor
    interceptors1.clear();
    expect(interceptors1.length, equals(1));  // Only default interceptor remains
    expect(interceptors1.single, isA<ImplyContentTypeInterceptor>());
    
    // Test 4: clear() with keepImplyContentTypeInterceptor=false removes all
    interceptors1.clear(keepImplyContentTypeInterceptor: false);
    expect(interceptors1.length, equals(0));  // Completely empty
    expect(interceptors1, isEmpty);

    // Test 5: Creating Interceptors with initialInterceptors
    final interceptors2 = Interceptors()..add(LogInterceptor());
    expect(interceptors2.length, equals(2));  // Default + LogInterceptor
    expect(interceptors2.last, isA<LogInterceptor>());

    // Test 6: Constructor with initialInterceptors parameter
    final interceptors3 = Interceptors(initialInterceptors: [LogInterceptor()]);
    expect(interceptors3.length, equals(2));  // Default + provided interceptor
    expect(interceptors2.last, isA<LogInterceptor>());
  });

  /// Tests interceptor removal and management operations.
  /// Demonstrates how to dynamically manage interceptors in the list.
  test('Interceptor removal and management', () {
    final interceptors = Interceptors();
    final logInterceptor = LogInterceptor();
    final customInterceptor = MyInterceptor();
    
    // Add multiple interceptors
    interceptors.addAll([logInterceptor, customInterceptor]);
    expect(interceptors.length, equals(3)); // Default + 2 custom
    
    // Remove specific interceptor
    interceptors.remove(logInterceptor);
    expect(interceptors.length, equals(2));
    expect(interceptors.contains(logInterceptor), isFalse);
    expect(interceptors.contains(customInterceptor), isTrue);
    
    // Remove by type
    interceptors.removeWhere((interceptor) => interceptor is MyInterceptor);
    expect(interceptors.length, equals(1)); // Only default remains
    expect(interceptors.single, isA<ImplyContentTypeInterceptor>());
    
    // Test removeImplyContentTypeInterceptor method
    interceptors.removeImplyContentTypeInterceptor();
    expect(interceptors.length, equals(0));
    expect(interceptors.isEmpty, isTrue);
  });

  /// Tests the difference between regular and queued interceptors with concurrent requests.
  /// This demonstrates why QueuedInterceptor is important for operations that must be serialized.
  test('Regular vs Queued interceptor behavior with concurrent requests', () async {
    int regularInterceptorCount = 0;
    int queuedInterceptorCount = 0;
    
    // Setup Dio with regular interceptor
    final dioRegular = Dio()
      ..options.baseUrl = MockAdapter.mockBase
      ..httpClientAdapter = MockAdapter()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            regularInterceptorCount++;
            handler.next(options);
          },
        ),
      );

    // Setup Dio with queued interceptor  
    final dioQueued = Dio()
      ..options.baseUrl = MockAdapter.mockBase
      ..httpClientAdapter = MockAdapter()
      ..interceptors.add(
        QueuedInterceptorsWrapper(
          onRequest: (options, handler) {
            queuedInterceptorCount++;
            handler.next(options);
          },
        ),
      );

    // Make concurrent requests and ignore errors (we just want to count interceptor calls)
    const requestCount = 3;
    final futures1 = <Future>[];
    final futures2 = <Future>[];
    
    for (int i = 0; i < requestCount; i++) {
      futures1.add(dioRegular.get('/test$i').catchError((e) => Response(
        requestOptions: RequestOptions(),
        statusCode: 500,
      )));
      futures2.add(dioQueued.get('/test$i').catchError((e) => Response(
        requestOptions: RequestOptions(), 
        statusCode: 500,
      )));
    }
    
    await Future.wait(futures1);
    await Future.wait(futures2);

    // Both should process all requests, but queued interceptor processes them serially
    expect(regularInterceptorCount, equals(requestCount));
    expect(queuedInterceptorCount, equals(requestCount));
  });

  /// Tests the callFollowing parameter behavior in handler methods.
  /// Demonstrates how resolve/reject with callFollowing=true affects the interceptor chain.
  test('Handler callFollowing parameter behavior', () async {
    final responses = <String>[];
    final errors = <String>[];
    
    final dio = Dio()
      ..options.baseUrl = MockAdapter.mockBase
      ..httpClientAdapter = MockAdapter()
      ..interceptors.addAll([
        // First interceptor: resolve with callFollowing=true
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/resolve-following') {
              handler.resolve(
                Response(requestOptions: options, data: 'first'),
                true, // callFollowingResponseInterceptor = true
              );
            } else if (options.path == '/reject-following') {
              handler.reject(
                DioException(requestOptions: options, error: 'first-error'),
                true, // callFollowingErrorInterceptor = true  
              );
            } else {
              handler.next(options);
            }
          },
        ),
        // Second interceptor: should be called due to callFollowing=true
        InterceptorsWrapper(
          onResponse: (response, handler) {
            responses.add('second-response: ${response.data}');
            response.data = 'modified-${response.data}';
            handler.next(response);
          },
          onError: (error, handler) {
            errors.add('second-error: ${error.error}');
            handler.next(error.copyWith(error: 'modified-${error.error}'));
          },
        ),
        // Third interceptor: should also be called due to callFollowing chain
        InterceptorsWrapper(
          onResponse: (response, handler) {
            responses.add('third-response: ${response.data}');
            handler.next(response);
          },
          onError: (error, handler) {
            errors.add('third-error: ${error.error}');
            handler.next(error);
          },
        ),
      ]);

    // Test resolve with callFollowing=true
    final resolveResponse = await dio.get('/resolve-following');
    expect(resolveResponse.data, equals('modified-first'));
    expect(responses, contains('second-response: first'));
    expect(responses, contains('third-response: modified-first'));

    // Reset for next test
    responses.clear();
    errors.clear();

    // Test reject with callFollowing=true
    try {
      await dio.get('/reject-following');
      fail('Should have thrown DioException');
        } catch (e) {
      expect(e, isA<DioException>());
      final dioException = e as DioException;
      expect(dioException.error, equals('modified-first-error'));
      expect(errors, contains('second-error: first-error'));
      expect(errors, contains('third-error: modified-first-error'));
    }
  });
}
