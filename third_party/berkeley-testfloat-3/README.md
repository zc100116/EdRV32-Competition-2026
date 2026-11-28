
Package Overview for Berkeley TestFloat Release 3e
==================================================

John R. Hauser<br>
2018 January 20


Berkeley TestFloat is a small collection of programs for testing that an
implementation of binary floating-point conforms to the IEEE Standard for
Floating-Point Arithmetic.  TestFloat is distributed in the form of C source
code.


The TestFloat package is documented in the following files in the `doc`
subdirectory:

* [TestFloat-general.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/TestFloat-general.html) General documentation for understanding and using the TestFloat programs.
* [testfloat_gen.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat_gen.html) Specific documentation for the `testfloat_gen` program.
* [testfloat_ver.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat_ver.html) Specific documentation for the `testfloat_ver` program.
* [testfloat.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat.html) Specific documentation for the all-in-one `testfloat` program.
* [testsoftfloat.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/testsoftfloat.html) Specific documentation for the `testsoftfloat` program.
* [timesoftfloat.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/timesoftfloat.html) Specific documentation for the `timesoftfloat` program.
* [TestFloat-source.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/TestFloat-source.html) Documentation for building TestFloat.
* [TestFloat-history.html](http://www.jhauser.us/arithmetic/TestFloat-3/doc/TestFloat-history.html) History of the major changes to TestFloat.

Other files in the package comprise the source code for TestFloat.



## EdRV32 source import

Upstream: https://github.com/ucb-bar/berkeley-testfloat-3

Release: 3e (upstream master; no release tag selected).
Commit: `a9c849f1b0eb0264b626d9686ffae167d996e3be`.
Import date: 2026-11-28.

Unmodified source copy, including upstream license and build recipes.
Local integration uses RISCV specialization; all compiled output goes under
repository `build/fpu/`, never this directory. See `tools/fpu/README.md`.
