import 'package:archive/archive_io.dart';

OutputStreamBase openZipFileSink(String path) => OutputFileStream(path);

Future<void> closeZipFileSink(OutputStreamBase sink) => (sink as OutputFileStream).close();
