import 'dart:async';
import 'dart:convert';

/// One Server-Sent Event: its `id:` (if any) and its `data:` lines joined.
class SseFrame {
  const SseFrame({this.id, required this.data});

  final String? id;
  final String data;
}

/// Splits a `text/event-stream` body into events. Comments (keep-alives) and
/// events without data are dropped.
///
/// A plain transformer rather than an `async*` generator: cancelling an
/// `async*` stream waits for its next chunk, and an idle connection may never
/// send one.
Stream<SseFrame> parseSse(Stream<List<int>> bytes) {
  String? id;
  final data = <String>[];

  void dispatch(EventSink<SseFrame> sink) {
    if (data.isNotEmpty) sink.add(SseFrame(id: id, data: data.join('\n')));
    id = null;
    data.clear();
  }

  return const LineSplitter()
      .bind(utf8.decoder.bind(bytes))
      .transform(
        StreamTransformer<String, SseFrame>.fromHandlers(
          handleData: (line, sink) {
            if (line.isEmpty) return dispatch(sink);
            if (line.startsWith(':')) return;

            final colon = line.indexOf(':');
            final field = colon < 0 ? line : line.substring(0, colon);
            var value = colon < 0 ? '' : line.substring(colon + 1);
            if (value.startsWith(' ')) value = value.substring(1);

            switch (field) {
              case 'data':
                data.add(value);
              case 'id':
                id = value;
            }
          },
          handleDone: (sink) {
            dispatch(sink);
            sink.close();
          },
        ),
      );
}
