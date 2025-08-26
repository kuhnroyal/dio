# Dio Interceptors

Interceptors in Dio provide a powerful mechanism to transform, monitor, and control HTTP requests and responses during their lifecycle. This document provides a comprehensive guide to understanding and using interceptors in Dio.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Core Classes](#core-classes)
- [Interceptor Types](#interceptor-types)
- [Handler Classes](#handler-classes)
- [State Management](#state-management)
- [Built-in Interceptors](#built-in-interceptors)
- [Usage Examples](#usage-examples)
- [Advanced Patterns](#advanced-patterns)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

Dio's interceptor system follows a middleware pattern where interceptors are executed in a First-In-First-Out (FIFO) order. Each interceptor can:

- Modify request options before sending
- Transform responses after receiving
- Handle errors during the request lifecycle
- Control the flow by resolving, rejecting, or continuing to the next interceptor

The interceptor system supports two execution models:
1. **Parallel Execution** - Basic interceptors run in parallel for concurrent requests
2. **Queue-based Execution** - Queued interceptors process requests serially

## Core Classes

### Interceptor (Base Class)

The base class for all interceptors. Provides three lifecycle methods:

```dart
class Interceptor {
  /// Called when the request is about to be sent
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.next(options);
  }

  /// Called when the response is about to be resolved  
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    handler.next(response);
  }

  /// Called when an exception occurred during the request
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}
```

**Key Points:**
- Interceptors are called once per request/response cycle
- Redirects do not trigger additional interceptor calls
- Must call one of the handler methods (`next`, `resolve`, or `reject`)

### InterceptorState<T>

State object passed between interceptors containing data and execution type:

```dart
class InterceptorState<T> {
  final T data;                           // The request/response/error data
  final InterceptorResultType type;       // How the interceptor handled the data
}
```

### InterceptorResultType

Enum defining how interceptors can handle the request lifecycle:

```dart
enum InterceptorResultType {
  next,                    // Continue to next interceptor
  resolve,                 // Complete request with success
  resolveCallFollowing,    // Resolve but call following response interceptors
  reject,                  // Complete request with error
  rejectCallFollowing,     // Reject but call following error interceptors
}
```

## Interceptor Types

### 1. Basic Interceptor

Standard interceptor that processes requests in parallel:

```dart
class CustomInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Add custom header
    options.headers['X-Custom-Header'] = 'Custom-Value';
    super.onRequest(options, handler);
  }
}
```

### 2. QueuedInterceptor

Queue-based interceptor that processes requests serially. Useful for:
- Authentication flows requiring token refresh
- Rate limiting
- Request ordering dependencies

```dart
class AuthInterceptor extends QueuedInterceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (needsTokenRefresh()) {
      // Refresh token and then proceed
      refreshToken().then((_) => handler.next(options));
    } else {
      handler.next(options);
    }
  }
}
```

### 3. InterceptorsWrapper

Helper class for creating interceptors with callback functions:

```dart
dio.interceptors.add(
  InterceptorsWrapper(
    onRequest: (options, handler) {
      print('Request: ${options.uri}');
      handler.next(options);
    },
    onResponse: (response, handler) {
      print('Response: ${response.statusCode}');  
      handler.next(response);
    },
    onError: (error, handler) {
      print('Error: ${error.message}');
      handler.next(error);
    },
  ),
);
```

### 4. QueuedInterceptorsWrapper

Helper class for creating queued interceptors with callback functions:

```dart
dio.interceptors.add(
  QueuedInterceptorsWrapper(
    onRequest: (options, handler) async {
      // Async operations in queue
      await someAsyncOperation();
      handler.next(options);
    },
  ),
);
```

## Handler Classes

Each interceptor lifecycle method receives a handler for controlling execution flow:

### RequestInterceptorHandler

Handles request transformation and flow control:

```dart
void next(RequestOptions requestOptions)           // Continue to next interceptor
void resolve(Response response, [bool callFollowing = false])  // Complete with success
void reject(DioException error, [bool callFollowing = false])   // Complete with error
```

### ResponseInterceptorHandler

Handles response transformation:

```dart
void next(Response response)                       // Continue to next interceptor
void resolve(Response response)                    // Complete with success
void reject(DioException error, [bool callFollowing = false])   // Complete with error
```

### ErrorInterceptorHandler

Handles error transformation and recovery:

```dart
void next(DioException error)                      // Continue to next interceptor
void resolve(Response response)                    // Recover with success response
void reject(DioException error)                    // Continue with error
```

**Important:** Each handler can only be called once. Calling a handler multiple times throws a `StateError`.

## State Management

The interceptor system maintains state through `InterceptorState` objects that track:

- **Data**: The current request options, response, or error
- **Type**: How the interceptor chose to handle the data
- **Flow Control**: Whether execution should continue or terminate

## Built-in Interceptors

### ImplyContentTypeInterceptor

Automatically sets the `Content-Type` header based on request data:

- `FormData` → `multipart/form-data`
- `Map`, `List<Map>`, `String` → `application/json`
- Other types → warning logged, no content-type set

**Features:**
- Added by default to all Dio instances
- Can be removed with `dio.interceptors.removeImplyContentTypeInterceptor()`
- Only sets content-type when not already specified

### LogInterceptor

Logs request and response details for debugging:

```dart
dio.interceptors.add(
  LogInterceptor(
    request: true,          // Log request options
    requestHeader: true,    // Log request headers
    requestBody: false,     // Log request body
    responseHeader: true,   // Log response headers
    responseBody: false,    // Log response body
    error: true,           // Log errors
    logPrint: print,       // Custom log function
  ),
);
```

**Best Practice:** Add `LogInterceptor` last to capture all modifications by other interceptors.

## Usage Examples

### Basic Request Modification

```dart
class HeaderInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Bearer $token';
    options.headers['Accept'] = 'application/json';
    handler.next(options);
  }
}
```

### Response Transformation

```dart
class ResponseTransformer extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.data is Map) {
      // Wrap response in standard format
      response.data = {
        'success': true,
        'data': response.data,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
    handler.next(response);
  }
}
```

### Error Recovery

```dart
class RetryInterceptor extends Interceptor {
  final int maxRetries;
  final Map<RequestOptions, int> _requestRetries = {};

  RetryInterceptor({this.maxRetries = 3});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final requestOptions = err.requestOptions;
    final retries = _requestRetries[requestOptions] ?? 0;

    if (retries < maxRetries && _shouldRetry(err)) {
      _requestRetries[requestOptions] = retries + 1;
      
      // Retry the request
      final dio = Dio();
      dio.fetch(requestOptions).then(
        (response) => handler.resolve(response),
        onError: (error) => handler.reject(error as DioException),
      );
    } else {
      _requestRetries.remove(requestOptions);
      handler.next(err);
    }
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
           err.type == DioExceptionType.receiveTimeout ||
           (err.response?.statusCode ?? 0) >= 500;
  }
}
```

### Authentication with Token Refresh

```dart
class AuthInterceptor extends QueuedInterceptor {
  String? _accessToken;
  String? _refreshToken;
  bool _isRefreshing = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_accessToken != null) {
      options.headers['Authorization'] = 'Bearer $_accessToken';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      
      _refreshAccessToken().then((_) {
        _isRefreshing = false;
        // Retry the original request
        final requestOptions = err.requestOptions;
        requestOptions.headers['Authorization'] = 'Bearer $_accessToken';
        
        final dio = Dio();
        dio.fetch(requestOptions).then(
          (response) => handler.resolve(response),
          onError: (error) => handler.reject(error as DioException),
        );
      }).catchError((error) {
        _isRefreshing = false;
        handler.next(err);
      });
    } else {
      handler.next(err);
    }
  }

  Future<void> _refreshAccessToken() async {
    // Implement token refresh logic
  }
}
```

## Advanced Patterns

### Conditional Interceptor Execution

```dart
class ConditionalInterceptor extends Interceptor {
  final bool Function(RequestOptions) condition;
  final Interceptor targetInterceptor;

  ConditionalInterceptor({
    required this.condition,
    required this.targetInterceptor,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (condition(options)) {
      targetInterceptor.onRequest(options, handler);
    } else {
      handler.next(options);
    }
  }
}
```

### Interceptor Chain Composition

```dart
class InterceptorChain extends Interceptor {
  final List<Interceptor> interceptors;

  InterceptorChain(this.interceptors);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _executeChain(0, options, handler);
  }

  void _executeChain(int index, RequestOptions options, RequestInterceptorHandler handler) {
    if (index >= interceptors.length) {
      handler.next(options);
      return;
    }

    final interceptor = interceptors[index];
    final nextHandler = RequestInterceptorHandler();
    
    interceptor.onRequest(options, nextHandler);
    
    nextHandler.future.then((state) {
      if (state.type == InterceptorResultType.next) {
        _executeChain(index + 1, state.data, handler);
      } else {
        // Handle resolve/reject cases
      }
    });
  }
}
```

### Caching Interceptor

```dart
class CacheInterceptor extends Interceptor {
  final Map<String, Response> _cache = {};
  final Duration maxAge;

  CacheInterceptor({this.maxAge = const Duration(minutes: 5)});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'GET') {
      final cacheKey = _getCacheKey(options);
      final cachedResponse = _cache[cacheKey];
      
      if (cachedResponse != null && _isValid(cachedResponse)) {
        handler.resolve(cachedResponse);
        return;
      }
    }
    
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.method == 'GET' && response.statusCode == 200) {
      final cacheKey = _getCacheKey(response.requestOptions);
      _cache[cacheKey] = response;
    }
    
    handler.next(response);
  }

  String _getCacheKey(RequestOptions options) {
    return '${options.uri}';
  }

  bool _isValid(Response response) {
    // Implement cache validation logic
    return true;
  }
}
```

## Best Practices

### 1. Handler Usage
- **Always call exactly one handler method** (`next`, `resolve`, or `reject`)
- Handle exceptions in interceptors to prevent uncaught errors
- Use `callFollowing` parameters carefully to maintain expected flow

### 2. Interceptor Ordering
- Add authentication interceptors early in the chain
- Add logging interceptors last to capture all modifications
- Consider dependencies between interceptors

### 3. Error Handling
```dart
class SafeInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      // Your interceptor logic
      handler.next(options);
    } catch (e) {
      // Convert to DioException if needed
      handler.reject(DioException(
        requestOptions: options,
        error: e,
        type: DioExceptionType.unknown,
      ));
    }
  }
}
```

### 4. State Management
- Avoid storing request-specific state in interceptor instances
- Use request/response extra fields for passing data between interceptors
- Consider thread safety for shared state in queued interceptors

### 5. Performance Considerations
- Use `QueuedInterceptor` only when serial processing is required
- Minimize blocking operations in interceptor callbacks
- Consider caching strategies for expensive operations

## Troubleshooting

### Common Issues

**1. StateError: Handler already called**
```
The `handler` has already been called, make sure each handler gets called only once.
```
**Solution:** Ensure exactly one handler method is called per interceptor execution.

**2. Interceptor not executing**
- Check interceptor order in the list
- Verify that previous interceptors call `handler.next()`
- Ensure the interceptor is properly added to `dio.interceptors`

**3. Infinite loops**
- Avoid creating new Dio instances with the same interceptors inside interceptor callbacks
- Use separate Dio instances for retry/refresh operations
- Implement proper termination conditions for recursive operations

**4. Unexpected behavior with QueuedInterceptor**
- Remember that queued interceptors process requests serially
- Consider timing implications for concurrent requests
- Test thoroughly with multiple concurrent requests

### Debugging Interceptors

```dart
class DebugInterceptor extends Interceptor {
  final String name;

  DebugInterceptor(this.name);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print('[$name] Request: ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('[$name] Response: ${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('[$name] Error: ${err.message}');
    handler.next(err);
  }
}

// Usage
dio.interceptors.addAll([
  DebugInterceptor('Auth'),
  AuthInterceptor(),
  DebugInterceptor('Logging'),
  LogInterceptor(),
]);
```

## Managing Interceptors

The `Interceptors` class provides a List-like interface for managing interceptors:

```dart
final interceptors = dio.interceptors;

// Add interceptors
interceptors.add(LogInterceptor());
interceptors.addAll([AuthInterceptor(), RetryInterceptor()]);

// Remove interceptors
interceptors.remove(specificInterceptor);
interceptors.removeWhere((i) => i is LogInterceptor);

// Clear all (keeps ImplyContentTypeInterceptor by default)
interceptors.clear();

// Clear all including ImplyContentTypeInterceptor
interceptors.clear(keepImplyContentTypeInterceptor: false);

// Remove only the ImplyContentTypeInterceptor
interceptors.removeImplyContentTypeInterceptor();

// Access by index
final firstInterceptor = interceptors[0];
interceptors[1] = newInterceptor;

// Check size and contents
print('Count: ${interceptors.length}');
print('Contains: ${interceptors.contains(someInterceptor)}');
```

---

This documentation covers the comprehensive interceptor system in Dio. For additional examples and use cases, refer to the test files and the main Dio documentation.