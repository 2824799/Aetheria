import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data != null) {
      await writeResponseData(
        data,
        testOutputFilename: 'ui_performance',
        destinationDirectory: 'build/ui_performance',
      );
    }
  },
);
