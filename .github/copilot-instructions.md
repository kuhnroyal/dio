# Copilot Instructions for Dio Repository

## Repository Summary

Dio is a powerful HTTP networking package for Dart and Flutter, supporting features like interceptors, request cancellation, custom adapters, transformers, and more. This is a monorepo containing the core dio package and several specialized plugins for different platforms and use cases.

## High-Level Repository Information

- **Repository Type**: Dart/Flutter HTTP networking library
- **Size**: ~50+ packages/modules in monorepo structure
- **Languages**: Dart (primary), Flutter, CMake for native components
- **Target Runtimes**: Dart VM, Flutter (iOS/Android/Web/Desktop), Web browsers
- **Package Manager**: Dart pub, managed via Melos for monorepo coordination
- **Compatibility Requirements**: Code must be compatible with Dart >=2.18.0 and Flutter >=3.3.0 (follows compatibility policy of supporting SDKs released less than 2 years ago)
- **Development Environment**: Assumes latest Flutter version is available

## Build, Test, and Development Commands

### Prerequisites

**Development Environment Assumptions:**
- Dart SDK (>=2.18.0) is installed and available
- Flutter SDK (>=3.3.0) is installed and available  
- Melos is globally installed (`dart pub global activate melos`)
- Repository dependencies are installed (`dart pub get`)

**Bootstrap Workspace:**
```bash
# Bootstrap the workspace - run when dependencies change
melos bootstrap
```

**Important:** The `melos bootstrap` command only needs to be run when dependencies have been changed. The project uses a custom script (`scripts/melos_packages.dart`) to check package compatibility with current Dart SDK.

### Core Development Commands

#### Code Quality (Format and Analysis)
```bash
# Format code (check mode) - always run before committing
melos run format

# Format code (fix mode) - auto-fix formatting issues
melos run format:fix

# Analyze all packages - catches linting issues and errors
melos run analyze

# Publish dry-run - validates packages can be published
melos run publish-dry-run
```

#### Testing (Multi-Platform)
```bash
# Run ALL tests across all platforms - comprehensive test suite
melos run test

# Individual test targets:
melos run test:vm          # Dart VM tests
melos run test:web         # Web tests (Chrome + Firefox)
melos run test:web:chrome  # Web tests in Chrome only
melos run test:web:firefox # Web tests in Firefox only
melos run test:flutter     # Flutter-specific tests

# Coverage reporting
melos run test:coverage    # Run tests and show coverage
```

**Test Configuration Notes:**
- Tests require network access for HTTP testing against httpbun.com/httpbun.local
- Some tests use certificate pinning (requires `prepare_pinning_certs.sh`)
- Web tests support WebAssembly compilation on Chrome
- Coverage reports are generated in `coverage/` directory

#### Building and Examples
```bash
# Build Flutter example APK
melos run build:example:apk

# Clean workspace
melos clean
```

### Environment Setup Details

**Required Environment Variables:**
- `TEST_PLATFORM`: Set to `chrome` or `firefox` for web tests
- `TARGET_DART_SDK`: Set to `min`, `stable`, or `beta` for CI
- `TEST_PRESET`: Set to `all` or `default` for test configuration

**Network Dependencies:**
- Tests require internet access to httpbun.com
- CI uses local httpbun instance with SSL certificates
- Certificate pinning tests need `openssl` for cert generation

## Project Architecture and Layout

### Directory Structure

```
├── .github/                    # GitHub workflows and templates
│   ├── workflows/              # CI/CD pipelines (tests.yml, coverage, etc.)
│   └── ISSUE_TEMPLATE/         # Issue templates
├── dio/                        # Core dio package
│   ├── lib/src/               # Main source code
│   │   ├── dio.dart           # Main Dio class (~300 lines)
│   │   ├── adapters/          # HTTP adapters
│   │   ├── interceptors/      # Request/response interceptors
│   │   └── transformers/      # Data transformers
│   └── test/                  # Core package tests
├── plugins/                    # Plugin packages
│   ├── cookie_manager/        # Cookie handling plugin
│   ├── http2_adapter/         # HTTP/2 support
│   ├── native_dio_adapter/    # Native platform adapters
│   ├── web_adapter/           # Web-specific adapter
│   └── compatibility_layer/   # Backward compatibility
├── example_dart/              # Pure Dart example
├── example_flutter_app/       # Flutter app example  
├── dio_test/                  # Shared testing utilities
├── scripts/                   # Build and utility scripts
├── melos.yaml                 # Monorepo configuration
└── analysis_options.yaml     # Dart linting rules
```

### Key Configuration Files

- `melos.yaml`: Monorepo configuration with all development scripts
- `analysis_options.yaml`: Project-wide linting rules (extends package:lints/recommended.yaml)
- `pubspec.yaml`: Workspace-level dependencies
- `.github/workflows/tests.yml`: Main CI pipeline (multi-platform testing)
- `scripts/melos_packages.dart`: SDK compatibility checker
- `scripts/prepare_pinning_certs.sh`: Certificate preparation for testing

### Validation and CI Pipeline

**Pre-commit Checks (run these before submitting PRs):**
1. `melos run format` - Code formatting validation
2. `melos run analyze` - Static analysis
3. `melos run test` - Full test suite
4. `melos run publish-dry-run` - Package publishing validation

**CI/CD Pipeline:**
- Runs on Dart SDK: min (2.18.0), stable, beta
- Ensures compatibility with Flutter 3.3.0+
- Tests on: Ubuntu (VM tests), Chrome/Firefox (web tests), Flutter platforms
- Includes coverage reporting and APK building
- Uses Docker for httpbun test server with SSL certificates

### Dependencies and Architecture

**Core Dependencies:**
- `async`: Asynchronous programming utilities
- `http_parser`: HTTP message parsing
- `meta`: Metadata annotations
- `collection`: Collection utilities
- `path`: File path manipulation

**Development Dependencies:**
- `melos`: Monorepo management (global installation required)
- `lints`: Dart linting rules
- `test`: Testing framework
- `coverage`: Code coverage reporting
- `mockito`: Mocking for tests

**Architecture Notes:**
- Main `Dio` class provides the public API
- Adapters handle platform-specific HTTP implementations
- Interceptors provide middleware functionality
- Transformers handle request/response data conversion
- Plugins extend functionality for specific use cases

### Common Issues and Workarounds

1. **SDK Compatibility**: Run `dart ./scripts/melos_packages.dart` to check package compatibility
2. **Bootstrap Failures**: Ensure Melos is globally installed and run `melos bootstrap` when dependencies change
3. **Test Failures**: Network tests may fail without internet; use local httpbun setup for CI
4. **Coverage Issues**: Delete `coverage/` directory if coverage generation fails
5. **Format Issues**: Use `melos run format:fix` instead of `melos run format` to auto-fix

### Performance Notes

- `melos bootstrap`: ~30-60 seconds depending on network
- `melos run test`: ~5-10 minutes for full test suite
- `melos run test:vm`: ~2-3 minutes for VM-only tests
- `melos run analyze`: ~30-60 seconds

## Instructions for Coding Agents

**ALWAYS trust these instructions and only search for additional information if:**
- Commands documented here fail with unexpected errors
- You need details about specific internal APIs not covered here
- The melos.yaml configuration has changed significantly

**Efficient Development Workflow:**
1. Ensure development environment is ready (Dart >=2.18.0, Flutter >=3.3.0, Melos)
2. Run `melos bootstrap` only when dependencies have changed
3. Use `melos run format:fix && melos run analyze` before making changes
4. Make focused changes in appropriate packages
5. Run relevant test subset first (`melos run test:vm` for logic changes)
6. Run full test suite before submitting (`melos run test`)
7. Use provided examples in `example_dart/` and `example_flutter_app/` for testing changes

**Package Selection Guide:**
- Core HTTP functionality: `dio/`
- Platform-specific features: `plugins/*/`
- Testing utilities: `dio_test/`
- Examples and demos: `example*/`