## vCard

A vCard file cleanup utility.

The vcard utility can sort cards, cleanup phone numbers, remove duplicate cards, and combine data from similar cards.

Input data supported is vCard visiting card VCF Virtual Contact File format, version 2.1.  Other versions may work OK. For technical details see the [IETF RFC 6350, vCard Format Specification](https://tools.ietf.org/html/rfc6350).

## Usage

```sh
vcard.sh - vCard cleanup utility.
Usage: vcard.sh [flags] [in-file|-]
Option flags:
  -h --help          - Show this help and exit.
  -v --verbose       - Verbose execution.
  -i --in-file       - Input file. Default: '/dev/stdin'.
  -o --out-file      - Output file. Default: '/dev/stdout'.
Option steps:
  -1 --sort          - Sort cards by FN field. Default: '1'.
  -2 --clean-numbers - Convert phone numbers to xxx-xxx-xxxx format. Default: '1'.
  -3 --remove-dupes  - Remove duplicate cards. Default: '1'.
  -4 --combine-cards - Combine data from cards with same FN field. Default: '1'.
Send bug reports to Geoff Levand <geoff@infradead.org>.
```

## Licence & Usage

All files in the [vcard project](https://github.com/glevand/vcard), unless otherwise noted, are covered by an [MIT Plus License](https://github.com/glevand/vcard/blob/master/mit-plus-license.txt).  The text of the license describes what usage is allowed.
