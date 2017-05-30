// Copyright (c) 2017, Kevin Moore. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'package:lib_graph/lib_graph.dart';

main(List<String> arguments) async {
  var projectPath = arguments.single;

  var thing = await LibGraph.create(projectPath);

  await thing.doIt();
}
