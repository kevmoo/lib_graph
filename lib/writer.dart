import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

String toDotHtml(String dot, String title) {
  return _DOT_HTML_TEMPLATE
      .replaceAll(_DOT_PLACE_HOLDER, dot)
      .replaceAll(_TITLE_PLACE_HOLDER, title);
}

Future openHtml(String name, String htmlContent) async {
  var dir = await Directory.systemTemp.createTemp('pubviz_${name}_');
  var filePath = p.join(dir.path, '$name.html');
  var file = new File(filePath);

  file = await file.create();
  await file.writeAsString(htmlContent, mode: FileMode.WRITE, flush: true);

  print('File generated: $filePath');

  String openCommand;
  if (Platform.isMacOS) {
    openCommand = 'open';
  } else if (Platform.isLinux) {
    openCommand = 'xdg-open';
  } else if (Platform.isWindows) {
    openCommand = 'start';
  } else {
    print("We don't know how to open a file in ${Platform.operatingSystem}");
    exit(1);
  }

  return Process.run(openCommand, [filePath], runInShell: true);
}

const _DOT_PLACE_HOLDER = 'DOT_HERE';

const _TITLE_PLACE_HOLDER = 'PACKAGE_TITLE';

const String _DOT_HTML_TEMPLATE = r'''
<!DOCTYPE html>
<html>
  <head>
    <title>PACKAGE_TITLE</title>
    <base href="https://kevmoo.github.io/pubviz/">
    <link rel="stylesheet" href="style.css">
    <script src="viz.js"></script>
  </head>
  <body>
    <button id="zoomBtn">Zoom</button>
    <script type="text/vnd.graphviz" id="dot">
DOT_HERE
    </script>
  </body>
  <script deferred src="web_app.dart.js"></script>
</html>
''';
