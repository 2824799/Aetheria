/// Last component of a filename received in a library database. Both Windows
/// and POSIX separators are accepted, regardless of the current platform.
String? managedFileName(String stored) {
  final name = stored.replaceAll('\\', '/').split('/').last;
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains(':') ||
      name.codeUnits.contains(0)) {
    return null;
  }
  return name;
}

String? managedAudioPath(String libraryPath, String stored) =>
    _managedPath(libraryPath, 'files', stored);

String? managedCoverPath(String libraryPath, String stored) =>
    _managedPath(libraryPath, 'covers', stored);

String? phigrosSeDirPath(String libraryPath) {
  if (libraryPath.trim().isEmpty) return null;
  final clean = libraryPath.replaceAll('\\', '/').replaceAll(RegExp('/+\$'), '');
  return '$clean/phigros/se';
}

String? phigrosChartPath(String libraryPath, String stored) =>
    _managedPath(libraryPath, 'phigros/charts', stored);

String? _managedPath(String libraryPath, String directory, String stored) {
  if (libraryPath.trim().isEmpty) return null;
  final name = managedFileName(stored);
  if (name == null) return null;
  return '$libraryPath/$directory/$name'.replaceAll('\\', '/');
}
