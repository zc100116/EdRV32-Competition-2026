"""model/__init__.py — gpu-spec 2–6: public functional model API.
Host Python package, no clock domain; see README.md for use.
"""
from .arithmetic import Numeric
from .renderer import GPU
from .layout import interleave_texture

__all__ = ['GPU', 'Numeric', 'interleave_texture']
