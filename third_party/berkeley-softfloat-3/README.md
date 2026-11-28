
Package Overview for Berkeley SoftFloat Release 3e
==================================================

John R. Hauser<br>
2018 January 20


Berkeley SoftFloat is a software implementation of binary floating-point
that conforms to the IEEE Standard for Floating-Point Arithmetic.  SoftFloat
is distributed in the form of C source code.  Building the SoftFloat sources
generates a library file (typically `softfloat.a` or `libsoftfloat.a`)
containing the floating-point subroutines.


The SoftFloat package is documented in the following files in the `doc`
subdirectory:

* [SoftFloat.html](http://www.jhauser.us/arithmetic/SoftFloat-3/doc/SoftFloat.html) Documentation for using the SoftFloat functions.
* [SoftFloat-source.html](http://www.jhauser.us/arithmetic/SoftFloat-3/doc/SoftFloat-source.html) Documentation for building SoftFloat.
* [SoftFloat-history.html](http://www.jhauser.us/arithmetic/SoftFloat-3/doc/SoftFloat-history.html) History of the major changes to SoftFloat.

Other files in the package comprise the source code for SoftFloat.



## EdRV32 source import

Upstream: https://github.com/ucb-bar/berkeley-softfloat-3

Release: 3e (upstream master; no release tag selected).
Commit: `afdc157e71f0d97508301ac0965defead49c679b`.
Import date: 2026-11-28.

Unmodified source copy, including upstream license and build recipes.
Local integration uses RISCV specialization; all compiled output goes under
repository `build/fpu/`, never this directory. See `tools/fpu/README.md`.
