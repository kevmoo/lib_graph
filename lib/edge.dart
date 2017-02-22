import 'package:analyzer/dart/element/element.dart';

import 'util.dart';

class Edge implements Comparable<Edge> {
  final LibraryElement from;
  final LibraryElement to;
  final bool isExport;

  Edge(this.from, this.to, this.isExport);

  @override
  bool operator ==(Object other) =>
      other is Edge &&
      other.from == from &&
      other.to == to &&
      other.isExport == this.isExport;

  @override
  int get hashCode => from.hashCode ^ to.hashCode ^ isExport.hashCode;

  @override
  int compareTo(Edge other) => compareLibs(this.to, other.to);
}
