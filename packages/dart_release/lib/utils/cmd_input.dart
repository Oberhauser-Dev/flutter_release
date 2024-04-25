import 'dart:convert';
import 'dart:io';

String readInput() {
  String? line;
  do {
    line = stdin.readLineSync(encoding: utf8);
    if (line == null) {
      print('Line is empty. Plz try again!');
    } else {
      line = line.trim();
    }
  } while (line == null || line.isEmpty);

  if (line.toLowerCase() == 'q') {
    exit(0);
  }

  return line;
}
