import 'package:analyzer/dart/element/element.dart';

import 'package:path/path.dart' as p;

String libPathCore(LibraryElement element, String projectPath) {
  var libUri = element.librarySource.uri;
  if (libUri.isScheme('file')) {
    return p.relative(p.fromUri(libUri), from: projectPath);
  } else if (libUri.isScheme('package') || libUri.isScheme('dart')) {
    return libUri.toString();
  }

  throw "not supported - $libUri";
}

int compareLibs(LibraryElement a, LibraryElement b) =>
    a.librarySource.uri.toString().compareTo(b.librarySource.uri.toString());

String prettyNameCore(LibraryElement element, String projectPath) {
  var uri = element.librarySource.uri;

  if (uri.scheme == 'file') {
    return libPathCore(element, projectPath);
  } else {
    return uri.toString();
  }
}
