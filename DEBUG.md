# Debugging Guide

Below are some techniques I've used to debug my device drivers during
development. Most of this information is distilled from:
* Reading the available MS-DOS [source code](https://github.com/microsoft/MS-DOS)
  from Microsoft, especially v2.0
* Consulting [Ergodon Tan](www.erdogantan.com)'s MS-DOS [disassemblies](https://www.erdogantan.com/trdos/retrodos/retrodos4/)
  when I required information _specifically_ about `IO.SYS`/`IBMBIO.COM`, as
  Microsoft's source does not target IBM PCs or compatibles.
* Writing various C (OpenWatcom)/Assembly (DEBUG.COM) test programs and
  analyzing their output when I get tired of reading source :).
* Ray Duncan's [Advanced MS-DOS Programming](https://www.pcjs.org/documents/books/mspl13/msdos/advdos/),
  particularly:
  * Chapter 5 gives an explanation on the capabilities of MS-DOS' cooked mode.
  * Chapter 14 is a good complement to `DEVDRIV.txt`.

This guide does _not_ attempt to be a comprehensive guide to the source code or
how MS-DOS works (data structures or code). It is collection of things that
took me a while to understand when exploring the source code myself. This way,
when it's not fresh in my memory, I can refer back to this document for help!

## Debugging Setup
TODO.

## Debug
TODO. [This](https://thestarman.pcministry.com/asm/debug/debug2.htm) is a good
tutorial that I reference a lot.

### How To Find Your Driver In Memory
TODO.

## MS-DOS Source Code Layout
Since Device Drivers (and file handles) only appeared in `v2.0` and up, assume
we are in the `v2.0` source directory for this, unless otherwise stated. A
working MS-DOS at minimum, provides `IO.SYS`/`IBMBIO.COM`,
`MSDOS.SYS`/`IBMDOS.COM`, and `COMMAND.COM`. If `grep`ping, use the `-a` switch
because some text files will otherwise be treated as binary. The following
bullets provide a brief synopsis of a number of files in the directory:

* `COMEQU.ASM`, `COMMAND.COM` `COMSEG.ASM`, `COMSW.ASM`,  _among other
   files listed in `COMLINK`_, implement `COMMAND.COM`.
* `COMLINK` is a hint for which files implement `COMMAND.COM`.
* `DEV.ASM` implement shared code for older syscalls (0x01-0x0c).
* `DEVSYM.ASM` and `DOSSYM.ASM` provides useful constants and MASM structs
  for `DEV.ASM` and all of the DOS kernel source respectively.
  * `DEVSYM.ASM` symbols are not always used for drivers, such as those
    in `SKELIO.ASM`.
  * Some `DOSSYM.ASM` constants structs are defined multiple times, and
    _all definitions are used_, like `devid_ISDEV` and `devid_device`.
    If looking for symbols uses, `grep` with caution!
* `DEVDRIV.txt` is the existing literature on how to write a device driver.
* `DOSLINK` is a hint for which files implement `MSDOS.SYS`/`IBMDOS.COM`.
* `DOSMAC.ASM` provides early [MASM](https://en.wikipedia.org/wiki/Microsoft_Macro_Assembler)
   macros. I'm vaguely aware they break on later versions.
* `FORMAT.TXT` and `README.TXT` provide useful general information about
  the boot process, including the fact that `IO.SYS` and `MSDOS.SYS` must
  be [contiguous](https://archive.ph/20120717061828/http://support.microsoft.com/kb/66530/en-us);
  [doesn't seem](https://thestarman.pcministry.com/asm/mbr/DOS50FDB.htm) like
  512 bytes is enough for arbitrarily-placed/fragmented files.
* `IO.ASM` implements syscalls 0x01-0x0c, and _is missing from Microsoft's
   source distribution_. `STDIO.ASM` wraps `IO.ASM`.
* `MSCODE.ASM` provides the entry point/dispatch table for syscalls.
* `MSDOS.ASM`, `MSDATA.ASM`, `MSHEAD.ASM`, `MSINIT.ASM`,  and `SYSMES.ASM`,
   _among other files listed in `DOSLINK`_, implements `MSDOS.SYS`.
   * `MSDOS.SYS` implement the kernel including syscalls, file management, and
     talking to device drivers (provided by `IO.SYS` or otherwise.)
* `XENIX{2}.ASM` implement the file-handle syscall API (0x3d-0x46).
* `SKELIO.ASM`, `SYSINIT.ASM` and `SYSIMES.ASM` implement `IO.SYS`/`IBMBIO.COM`.
  * `IO.SYS` includes default device drivers and init code (`SYSINT`).
* `STRIN.ASM` implements syscall 0x0a, the only syscall <= 0x0c whose source
  is included. This code, which also implements basic terminal handling for
  e.g. ^C, comes up more often that you'd think; see raw vs cooked.
* `TCODE{2,3,4,5}.ASM` implement the transient portion of `COMMAND.COM` at the
  upper end of memory.

Not all files in the directory are listed above, just enough so I can get my
bearings after a break :). Files are also grouped in a way that's convenient
for me.

## Device Driver Attributes
In MS-DOS, the info contained device driver attribute word is kept in two
places in memory. One is the device driver header; the other is a _copy_ of the
device header's attribute word kept with the information pointed to by an open
file handle. Changing a device's attributes will only affect the file handle's
_copy_ of the attributes. Therefore it is possible to have two file handles
pointing to the same device while having different device attributes set.

## File Handles
File handles 0-4 are always available, and older DOS syscalls (0x01-0x0c) operate
on them implicitly. They can be redirected from the below defaults, however.
These are devices as well, with device headers and names (`CON`, `AUX`, `PRN`):

0- `stdin`- Standard Console Input (`CON`)
1- `stdout`- Standard Console Output (`CON`)
2- `stderr`- Standard Console Error (`CON`)
3- `stdaux`- Standard Auxilary Device (Input/Output) (`AUX`)
4- `stdprn`- Standard Printer (Output) (`PRN`)

`AUX` and `PRN` are separate devices from say, `COM1` and `LPT1`; there are 4
devices installed for each of `AUX`, `PRN`, `COM1` and `LPT1`, though code
_may_ be shared between them.

AFAICT, only `stdin` and `stdout` (not `stderr`!) get reset back to defaults
when a program finishes and returns to `COMMAND.COM`.

## The Input/Output Console Device Bits
It appears MS-DOS 2.0 unconditionally sets these bits for the `CON` device as
part of initialization. Since `CON` also unconditionally becomes the console
device at boot (and gets file handles 0, 1, and 2), this means:

* Your custom default `stdin`/`stdout` device _must_ be named `CON`.
* The Input/Output console bits _will_ be forcefully set!

The Input/Output console bits _are_ used (sparingly) in the MS-DOS source code,
though I don't understand how at this time. So the bits should be set if you
intend your device to serve as `stdin`/`stdout`.

Additionally, if `stdin`/`stdout` handles are _not_ associated with your device
(via close-then-dup or redirection), I'm not sure if the Input/Output console
bits are used. It is possible to have multiple devices open with the
Input/Output console bits set without issue (at least in my testing). The `CTTY`
command will do both setting the bits and redirection to `stdin`/`stdout` for
you.

All of the above is to say: I'm not sure how meaningful it is the sti/sto bits
is in your custom device header, since MS-DOS provides code to make sure
these bits are set in file handles when appropriate.

### How `CTTY` works
`CTTY` is a `COMMAND.COM` built-in that does the following (more-or-less):

1. Given a filename, check it is a character device, and if so, open the file.
2. Set the Input/Output console bits on the device's attributes associated with
   your open file handle.
3. Close file handles 0 (`stdin`), 1 (`stdout`), and 2 (`stderr`).
4. Use the dup syscall to duplicate your new device handle. Because file
   handles are allocated in order of lowest number available (also true for
   UNIX?), handles 0, 1, and 2 will now point to your new device.
5. Close the file handle that was opened in step 1, as we don't need it
   anymore.
6. Notify MS-DOS that file handles 0 and 1 point to a new device by default.
   This is how file handles are restored to your new device when a program
   that redirected 0 and 1 exits, and is _not exposed by syscalls_. Also,
   2 is _not_ restored when a program exits AFAICT.

Perhaps everything except step 6 can be re-implemented using the redirection
syscall?

## Raw vs Cooked Bits
TODO.

## How `SYSINIT` In `IO.SYS` Works (Oversimplified)
`IO.SYS` provides default device drivers as well as initialization code. The
default device drivers mostly call into the system BIOS via a software
interrupt mechanism (IBM PC or otherwise).

At boot, after `IO.SYS` is loaded into memory by the bootloader, the following
happens in a function called `SYSINT`. This is simplified because I'm not
exactly sure why `SYSINIT` does some of these things :):

1. `SYSINIT` initializes the hardware and BIOS (if necessary).
2. `SYSINIT` then loads `MSDOS.SYS`/the DOS kernel into its final place in
   memory; the bootloader does the initial load of `MSDOS.SYS`.
3. The init code calls into `MSDOS.SYS` to initialize the DOS kernel. Device
   drivers are initialized here, including forcing `CON`'s I/O console bits on.
4. `MSDOS.SYS`'s init code returns to `IO.SYS`, such that the init code can
   then use the MS-DOS syscalls! MS-DOS devices are further initialized
   while `SYSINIT` runs (why?).
5. `IO.SYS` _may_ call the system BIOS for reinitialization (it does for the
   Microsoft-provided source, I don't think it does for IBM PCs).
6. Eventually, the `SYSINIT` execs `COMMAND.COM`.
