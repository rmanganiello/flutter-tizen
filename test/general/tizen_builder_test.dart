// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:flutter_tizen/build_targets/package.dart';
import 'package:flutter_tizen/tizen_build_info.dart';
import 'package:flutter_tizen/tizen_builder.dart';
import 'package:flutter_tizen/tizen_sdk.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/analyze_size.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/reporting/reporting.dart';
import 'package:meta/meta.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_tizen_sdk.dart';
import '../src/test_build_system.dart';
import '../src/test_flutter_command_runner.dart';

const String _kTizenManifestContents = '''
<manifest package="package_id" version="1.0.0" api-version="4.0">
    <profile name="common"/>
    <ui-application appid="app_id" exec="Runner.dll" type="dotnet"/>
</manifest>
''';

void main() {
  FileSystem fileSystem;
  ProcessManager processManager;
  BufferLogger logger;
  Platform platform;
  FlutterProject project;
  TizenBuildInfo tizenBuildInfo;
  TizenBuilder tizenBuilder;

  setUpAll(() {
    Cache.disableLocking();
  });

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion": 2, "packages": []}');
    processManager = FakeProcessManager.any();
    logger = BufferLogger.test();
    platform = FakePlatform(environment: <String, String>{'HOME': '/'});
    project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);

    tizenBuildInfo = const TizenBuildInfo(
      BuildInfo.debug,
      targetArch: 'arm',
      deviceProfile: 'common',
    );
    tizenBuilder = TizenBuilder(
      logger: logger,
      processManager: processManager,
      fileSystem: fileSystem,
      artifacts: Artifacts.test(),
      usage: TestUsage(),
      platform: platform,
    );
  });

  testUsingContext('Build fails if there is no Tizen project', () async {
    await expectLater(
      () => tizenBuilder.buildTpk(
        project: project,
        tizenBuildInfo: tizenBuildInfo,
        targetFile: 'main.dart',
      ),
      throwsToolExit(message: 'This project is not configured for Tizen.'),
    );
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });

  testUsingContext('Build fails if Tizen Studio is not installed', () async {
    fileSystem.file('tizen/tizen-manifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(_kTizenManifestContents);

    await expectLater(
      () => tizenBuilder.buildTpk(
        project: project,
        tizenBuildInfo: tizenBuildInfo,
        targetFile: 'main.dart',
      ),
      throwsToolExit(message: 'Unable to locate Tizen CLI executable.'),
    );
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });

  testUsingContext('Output TPK is missing', () async {
    fileSystem.file('tizen/tizen-manifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(_kTizenManifestContents);

    await expectLater(
      () => tizenBuilder.buildTpk(
        project: project,
        tizenBuildInfo: tizenBuildInfo,
        targetFile: 'main.dart',
      ),
      throwsToolExit(message: 'The output TPK does not exist.'),
    );
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    TizenSdk: () => FakeTizenSdk(fileSystem),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true)),
    PackageBuilder: () => _FakePackageBuilder(null),
  });

  testUsingContext('Indicates that TPK has been built successfully', () async {
    fileSystem.file('tizen/tizen-manifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(_kTizenManifestContents);

    await tizenBuilder.buildTpk(
      project: project,
      tizenBuildInfo: tizenBuildInfo,
      targetFile: 'main.dart',
    );

    expect(
      logger.statusText,
      contains('Built build/tizen/tpk/package_id-1.0.0.tpk (0.0MB).'),
    );
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    Logger: () => logger,
    TizenSdk: () => FakeTizenSdk(fileSystem),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true)),
    PackageBuilder: () => _FakePackageBuilder('package_id-1.0.0.tpk'),
  });

  testUsingContext('Can update tizen-manifest.xml', () async {
    fileSystem.file('tizen/tizen-manifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(_kTizenManifestContents);

    const BuildInfo buildInfo = BuildInfo(
      BuildMode.debug,
      null,
      treeShakeIcons: false,
      buildName: '9.9.9',
    );
    await tizenBuilder.buildTpk(
      project: project,
      tizenBuildInfo: const TizenBuildInfo(
        buildInfo,
        targetArch: 'arm',
        deviceProfile: 'wearable',
      ),
      targetFile: 'main.dart',
    );

    final String tizenManifest =
        fileSystem.file('tizen/tizen-manifest.xml').readAsStringSync();
    expect(tizenManifest, isNot(equals(_kTizenManifestContents)));
    expect(tizenManifest, contains('9.9.9'));
    expect(tizenManifest, contains('wearable'));
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    TizenSdk: () => FakeTizenSdk(fileSystem),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true)),
    PackageBuilder: () => _FakePackageBuilder('package_id-9.9.9.tpk'),
  });

  testUsingContext('Performs code size analysis', () async {
    fileSystem.file('tizen/tizen-manifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(_kTizenManifestContents);

    const BuildInfo buildInfo = BuildInfo(
      BuildMode.release,
      null,
      treeShakeIcons: false,
      codeSizeDirectory: 'code_size_analysis',
    );
    await tizenBuilder.buildTpk(
      project: project,
      tizenBuildInfo: const TizenBuildInfo(
        buildInfo,
        targetArch: 'arm',
        deviceProfile: 'wearable',
      ),
      targetFile: 'main.dart',
      sizeAnalyzer: _FakeSizeAnalyzer(fileSystem: fileSystem, logger: logger),
    );

    final File outputFile =
        fileSystem.file('.flutter-devtools/tpk-code-size-analysis_01.json');
    expect(outputFile.existsSync(), isTrue);
    expect(
      logger.statusText,
      contains('A summary of your TPK analysis can be found at'),
    );
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    Logger: () => logger,
    TizenSdk: () => FakeTizenSdk(fileSystem),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true)),
    PackageBuilder: () => _FakePackageBuilder('package_id-1.0.0.tpk'),
    FileSystemUtils: () =>
        FileSystemUtils(fileSystem: fileSystem, platform: platform),
  });
}

class _FakePackageBuilder extends PackageBuilder {
  _FakePackageBuilder(this._outputTpkName);

  final String _outputTpkName;

  @override
  Future<void> build(Target target, Environment environment) async {
    if (_outputTpkName != null) {
      final Directory tpkDir = environment.outputDir.childDirectory('tpk');
      tpkDir.childDirectory('tpkroot').createSync(recursive: true);
      tpkDir.childFile(_outputTpkName).createSync(recursive: true);
    }
  }
}

class _FakeSizeAnalyzer extends SizeAnalyzer {
  _FakeSizeAnalyzer({
    @required FileSystem fileSystem,
    @required Logger logger,
  }) : super(
          fileSystem: fileSystem,
          logger: logger,
          flutterUsage: TestUsage(),
        );

  @override
  Future<Map<String, Object>> analyzeAotSnapshot({
    @required Directory outputDirectory,
    @required File aotSnapshot,
    @required File precompilerTrace,
    @required String type,
    String excludePath,
  }) async {
    return <String, Object>{};
  }
}
