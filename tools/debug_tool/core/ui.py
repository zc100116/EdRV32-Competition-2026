"""ui.py — live-demo L7 UI_ITEMS fragment assembly; UDP receiver thread."""
import struct


class UiMirror:
    def __init__(self):
        self.snapshot = dict(revision=0, page=0, title='等待板端控件', items=[])
        self.header = None
        self.fragments = {}

    def receive(self, payload):
        revision, part, parts, page, _, title_length = struct.unpack_from('<IBBBBB', payload)
        offset = 9
        title = payload[offset:offset + title_length].decode('utf-8')
        offset += title_length
        header = (revision, parts, page, title)
        if self.header != header:
            self.header = header
            self.fragments.clear()
        items = []
        while offset < len(payload):
            ident, kind, value, minimum, maximum, area, length = struct.unpack_from(
                '<BBhhhBB', payload, offset)
            offset += 10
            label = payload[offset:offset + length].decode('utf-8')
            offset += length
            length = payload[offset]
            offset += 1
            options = payload[offset:offset + length].decode('utf-8')
            offset += length
            items.append(dict(id=ident, kind=kind, value=value, min=minimum, max=maximum,
                              area=area, label=label, options=options.split('\n') if options else []))
        self.fragments[part] = items
        if len(self.fragments) == parts:
            self.snapshot = dict(revision=revision, page=page, title=title,
                                 items=[item for index in range(parts)
                                        for item in self.fragments[index]])
            self.fragments.clear()
