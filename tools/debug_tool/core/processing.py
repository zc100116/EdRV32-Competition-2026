"""processing.py — PIX 2.2–2.5 / GEO 2.1 controls; host, no clock domain.

One complete parameter command per edit group, shared by GUI, REST and CLI.
"""

PIX_DEFAULTS = dict(bc=0, contrast=256, brightness=0, gamma_en=0, gamma=1000,
                    stage1=0, stage2=0, gray=0, binary=0, threshold=128, invert=0)
GEO_DEFAULTS = dict(enabled=0, angle=0, scale_x=1000, scale_y=1000,
                    translate_x=0, translate_y=0, mirror_x=0, mirror_y=0)


class ProcessingControl:
    def __init__(self, engine):
        self.engine = engine
        self.pix = dict(PIX_DEFAULTS)
        self.geo = dict(GEO_DEFAULTS)

    def send(self, kind, values):
        defaults = {'pix': PIX_DEFAULTS, 'geo': GEO_DEFAULTS}[kind]
        unknown = values.keys() - defaults.keys()
        if unknown:
            raise ValueError(f'Unknown {kind} parameters: {sorted(unknown)}')
        state = dict(getattr(self, kind), **values)
        if any(type(value) is not int for value in state.values()):
            raise ValueError('Processing parameters must be integers in wire units')
        if kind == 'pix':
            ranges = dict(bc=(0, 1), contrast=(0, 511), brightness=(-256, 255),
                          gamma_en=(0, 1), gamma=(1, 2147483647), stage1=(0, 6),
                          stage2=(0, 6), gray=(0, 1), binary=(0, 1),
                          threshold=(0, 255), invert=(0, 1))
        else:
            ranges = {key: (-2147483647, 2147483647) for key in defaults}
            ranges.update(enabled=(0, 1), scale_x=(1, 2147483647),
                          scale_y=(1, 2147483647), mirror_x=(0, 1), mirror_y=(0, 1))
        for key, (low, high) in ranges.items():
            if not low <= state[key] <= high:
                raise ValueError(f'{kind}.{key} must be {low}..{high}')
        result = self.engine.send(f'{kind} set ' + ' '.join(str(state[key]) for key in defaults),
                                  'cr')
        setattr(self, kind, state)
        return result

    def status(self):
        return dict(pix=dict(self.pix), geo=dict(self.geo))
