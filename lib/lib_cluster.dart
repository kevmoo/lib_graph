import 'dart:collection';

import 'package:analyzer/dart/element/element.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'edge.dart';
import 'util.dart';

class LibCluster {
  static List<LibCluster> stronglyConnected(
      Map<LibraryElement, Set<Edge>> things, String projectLibPath) {
    var easy = <LibraryElement, Set<LibraryElement>>{};

    things.forEach((lib, outLinks) {
      easy[lib] = outLinks.map((e) => e.to).toSet();
    });

    var comps = stronglyConnectedComponents(easy)
        .map((libs) => new SplayTreeSet<LibraryElement>.from(
            libs.where(
                (le) => p.split(libPathCore(le, projectLibPath)).length > 1),
            compareLibs))
        .where((e) => e.length > 1)
        .map((libs) => new LibCluster(libs, projectLibPath))
        .toList();

    return comps;
  }

  final Set<LibraryElement> elements;
  final String _string;

  LibCluster(Iterable<LibraryElement> elements, String projectLibPath)
      : this.elements =
            new SplayTreeSet<LibraryElement>.from(elements, compareLibs),
        this._string = _getName(elements, projectLibPath) {
    if (elements.length <= 1) {
      throw "Let's only do clusters bigger than 1, k?";
    }
  }

  bool contains(LibraryElement element) => elements.contains(element);

  static String _getName(
      Iterable<LibraryElement> elements, String projectLibPath) {
    var segs = elements
        .map((e) => prettyNameCore(e, projectLibPath))
        .map((path) => p.split(path))
        .toList();

    int i;
    for (i = 0; i < segs.first.length; i++) {
      var commonSegs = segs.first.take(i).toList().join(',');

      if (segs.any((s) => s.sublist(0, i).join(',') != commonSegs)) {
        break;
      }
    }

    if (i <= 1) {
      return segs.map((s) => p.joinAll(s)).join('\n');
    }

    var lines = [p.joinAll(segs.first.take(i - 1)) + "/"];
    lines.addAll(segs.map((s) => p.joinAll(s.skip(i - 1))));
    assert(lines.length == segs.length + 1);

    assert(lines.every((l) => l.isNotEmpty));

    return lines.join('\n');
  }

  @override
  String toString() => _string;

  String get id => 'c${_string.hashCode}';
}
