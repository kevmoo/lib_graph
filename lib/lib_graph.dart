// Copyright (c) 2017, Kevin Moore. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:gviz/gviz.dart' as gv;
import 'package:path/path.dart' as p;

import 'analyzer.dart';
import 'edge.dart';
import 'lib_cluster.dart';
import 'util.dart';

class LibGraph {
  final bool _writeExports = false;

  final String projectPath;
  final String projectLibPath;
  final String packageName;
  final AnalysisContext context;
  final String srcDir;

  LibGraph._(this.packageName, this.projectPath, this.projectLibPath,
      this.context, this.srcDir);

  static Future<LibGraph> create(String projectPath) async {
    //TODO(kevmoo) actually parse the pubspec, right?
    var packageName = p.split(projectPath).last;

    var projectLibPath = p.join(projectPath, 'lib');

    var result = Process.runSync('find', [projectLibPath, '-iname', '*.dart']);

    var items = LineSplitter.split(result.stdout).toList();

    var context = await getAnalysisContextForProjectPath(projectPath, items);

    final srcDir = p.join(projectLibPath, 'src');

    return new LibGraph._(
        packageName, projectPath, projectLibPath, context, srcDir);
  }

  String _prettyName(LibraryElement element) =>
      prettyNameCore(element, projectLibPath);

  LibraryElement _getRightLibrary(LibraryElement lib) {
    var uri = lib.librarySource.uri;

    if (uri.scheme == 'file' || uri.scheme == 'dart') {
      return lib;
    }

    assert(uri.scheme == 'package');

    if (uri.pathSegments.first == packageName) {
      // let's find the actual file library for this guy

      var fileUri = p.toUri(p.absolute(
          p.join(projectLibPath, p.joinAll(uri.pathSegments.skip(1)))));

      return context.getLibraryElement(context.librarySources.singleWhere((s) {
        return s.uri == fileUri;
      }));
    }
    return lib;
  }

  String _nameForLib(LibraryElement element) =>
      _prettyName(element).hashCode.toString();

  bool _isPrimaryLib(Uri uri) {
    if (uri.scheme != 'file') {
      return false;
    }

    var path = p.fromUri(uri);

    assert(p.isWithin(projectLibPath, path));

    return !p.isWithin(srcDir, path);
  }

  bool _excludeIncomingEdges(LibraryElement element) {
    //These are pretty common. Helps the graph layout be less of a mess
    //return _prettyName(element).startsWith("src/facade/");
    return false;
  }

  bool _includeNode(LibraryElement le) => true;

  bool _importExportFilter(LibraryElement le) {
    var uri = le.librarySource.uri;
    return uri.isScheme('file');
  }

  Future doIt() async {
    var graphedLibraries =
        new SplayTreeMap<LibraryElement, Set<Edge>>(compareLibs);

    for (var ls
        in context.librarySources.where((s) => s.uri.scheme == 'file')) {
      var element = context.getLibraryElement(ls);
      Set<Edge> putThing(LibraryElement element) =>
          graphedLibraries.putIfAbsent(element, () => new SplayTreeSet<Edge>());

      var edges = putThing(element);

      for (var import in element.importedLibraries
          .map(_getRightLibrary)
          .where(_importExportFilter)) {
        putThing(import);
        edges.add(new Edge(element, import, false));
      }

      for (var export in element.exportedLibraries
          .map(_getRightLibrary)
          .where(_importExportFilter)) {
        putThing(export);
        edges.add(new Edge(element, export, true));
      }
    }

    var stats = <LibraryElement, Set<Edge>>{};

    graphedLibraries.forEach((lib, edges) {
      // ensure we have a set (even empty) for all libraries.
      // makes things cleaner later
      stats.putIfAbsent(lib, () => new Set<Edge>());
      for (var e in edges) {
        stats.putIfAbsent(e.to, () => new Set<Edge>()).add(e);
      }
    });

    int statsSortParm(Set<Edge> edges) => edges.where((e) => e.isExport).length;

    var sortedLibs = graphedLibraries.keys.toList();
    sortedLibs.sort((a, b) {
      var value = -statsSortParm(stats[a]).compareTo(statsSortParm(stats[b]));
      if (value == 0) {
        value = _prettyName(a).compareTo(_prettyName(b));
      }
      return value;
    });

    var gviz = new gv.Gviz(
        name: 'lib_graph',
        nodeProperties: {'fontname': 'Helvetica'},
        edgeProperties: {'fontname': 'Helvetica', 'fontcolor': 'gray'});

    var writtenClusters = new Set<LibCluster>();

    void writeCluster(LibCluster cluster) {
      if (!writtenClusters.add(cluster)) {
        return;
      }

      var props = {'label': cluster.toString()};
      props['shape'] = 'polygon';
      props['sides'] = '6';
      props['style'] = 'bold,filled';
      props['fontsize'] = '20';
      props['color'] = 'lightblue';

      gviz.addLine();
      gviz.addNode(cluster.id, properties: props);
    }

    var components =
        LibCluster.stronglyConnected(graphedLibraries, projectLibPath);

    LibCluster getCluster(LibraryElement le) {
      for (var comp in components) {
        if (comp.contains(le)) {
          return comp;
        }
      }
      return null;
    }

    void writeLibraryNode(LibraryElement element) {
      if (!_includeNode(element)) {
        return;
      }

      var cluster = getCluster(element);
      if (cluster != null) {
        writeCluster(cluster);
        return;
      }

      var props = {'label': _prettyName(element)};

      if (_excludeIncomingEdges(element)) {
        props['shape'] = 'polygon';
        props['sides'] = '4';
      }

      var libUri = element.librarySource.uri;
      if (_isPrimaryLib(libUri)) {
        props['style'] = 'bold,filled';
        props['fontsize'] = '20';
        props['color'] = 'red';
      } else if (libUri.isScheme('package')) {
        props['style'] = 'filled';
        props['color'] = 'yellow';
      } else if (libUri.isScheme('dart')) {
        props['style'] = 'filled';
        props['color'] = 'orange';
      }

      gviz.addLine();
      gviz.addNode(_nameForLib(element), properties: props);
    }

    var librariesToProcess = graphedLibraries.keys.toSet();

    var clusterIncoming = <String, Set<Object>>{};
    var clusterOutgoing = <String, Set<Object>>{};

    graphedLibraries.forEach((lib, toEdges) {
      if (librariesToProcess.remove(lib)) {
        writeLibraryNode(lib);
      }

      var fromName = _nameForLib(lib);

      var fromCluster = getCluster(lib);
      Set<Object> outgoingItems;

      if (fromCluster != null) {
        fromName = fromCluster.id;
        outgoingItems = clusterOutgoing.putIfAbsent(
            fromCluster.id, () => new Set<Object>());
      }

      for (var edge in toEdges) {
        if (!_includeNode(lib) || !_includeNode(edge.to)) {
          continue;
        }

        if (_excludeIncomingEdges(edge.to)) {
          continue;
        }

        var toCluster = getCluster(edge.to);
        var toName = toCluster == null ? _nameForLib(edge.to) : toCluster.id;

        var props = <String, String>{};

        if (fromCluster != null) {
          if (fromCluster == toCluster) {
            // don't need a self edge!
            continue;
          }

          if (outgoingItems.add(toCluster ?? edge.to)) {
            // This is the first time we've seen an edge from this cluster to X
            // we should do work!
          } else {
            // already did this - continue!
            continue;
          }
        }

        if (toCluster != null) {
          if (clusterIncoming
              .putIfAbsent(toCluster.id, () => new Set<Object>())
              .add(fromCluster ?? lib)) {
            // we're drawing a line *to* a cluster for the first time - so we're good ?

            // since we collapse imports and exports, use a different color
            props['color'] = 'blue';
            props['style'] = 'bold';
          } else {
            // already drawn this line - never mind
            continue;
          }
        } else {
          // not drawing to a cluster, so do the normal things
          if (edge.isExport) {
            props['color'] = 'darkgreen';
          }

          if (_isPrimaryLib(edge.to.librarySource.uri)) {
            props['constraint'] = 'false';
          }
        }

        gviz.addEdge(fromName, toName, properties: props);
      }
    });

    print(gviz);

    if (_writeExports) {
      for (var lib in sortedLibs.where((le) => statsSortParm(stats[le]) > 1)) {
        stderr
            .writeln([statsSortParm(stats[lib]), _prettyName(lib)].join('  '));
        stderr.writeln("\t" +
            stats[lib]
                .where((e) => e.isExport)
                .map((e) => _prettyName(e.from))
                .join(', '));
      }
    }
  }
}
