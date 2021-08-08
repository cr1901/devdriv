# `devdriv` Repository

This repo is a collection of MS-DOS Device Drivers that I've created for fun.
Yes, in 2021. Right now, the bulk of the docs are in [`DEBUG.md`](./DEBUG.md).

To assemble, you require [GNU Make](https://www.gnu.org/software/make/) and
[NASM](https://nasm.us).

## List of Device Drivers
* `HELLO`- A "Hello World"-style character device that prints
  `HELLO WORLD\r\n^Z\0` when opened for reading.
