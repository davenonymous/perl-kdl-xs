# Text::KDL::XS

A fast Perl XS binding to [ckdl](https://github.com/tjol/ckdl) for parsing
and emitting [KDL](https://kdl.dev) documents. Supports KDL 2.0.0 and the
legacy KDL 1.0.0 with automatic version detection.

The full documentation is in the POD: `perldoc Text::KDL::XS` for the API
reference and `perldoc Text::KDL::XS::Cookbook` for a tour of every KDL
feature with Perl examples. This file is the short version.

## What is KDL?

KDL ("cuddle", the **K**DL **D**ocument **L**anguage) is a small
configuration and data language. A document is a tree of *nodes*; each
node has a name, optional *arguments*, optional *properties*
(`key=value`) and an optional block of child nodes:

```kdl
package "kdl-rs" {
    version "0.4.0"
    author "Kat Marchán" email="kat@example.com"
    keywords "config" "data" "structured"
    license "MIT" {
        url "https://opensource.org/licenses/MIT"
    }
}
```

Values are strings, numbers, `#true`/`#false`, `#null` or the special
numbers `#inf`, `#-inf` and `#nan`, and any value or node can carry a
`(type)` annotation. Comments, multi-line and raw strings,
hexadecimal/octal/binary numbers and `/-` "slashdash" comments round out
the language. The [Cookbook](https://metacpan.org/pod/Text::KDL::XS::Cookbook) shows all of
them.

## Synopsis

```perl
use Text::KDL::XS qw(parse_kdl emit_kdl);

my $doc = parse_kdl(<<'KDL');
server "web-1" port=8080 {
    tls #true
    upstream name="app" weight=3
}
KDL

for my $node (@{ $doc->nodes }) {
    print $node->name, "\n";                          # server
    print $node->args->[0]->as_string, "\n";          # web-1
    print $node->prop('port')->as_number, "\n";       # 8080
    for my $child (@{ $node->children }) {
        print "  ", $child->name, "\n";               # tls, upstream
    }
}

print emit_kdl($doc);                                 # round trip

print emit_kdl({                                      # plain data
    server => { host => 'localhost', port => 8080 },
    tags   => [ 'a', 'b' ],
});
# server {
#     host localhost
#     port 8080
# }
# tags a b
```

`parse_kdl` accepts a string of UTF-8 bytes, a raw filehandle, or a code
reference returning chunks. `emit_kdl` accepts a parsed document, a node,
a list of nodes, or plain hashes and arrays.

For SAX-style streaming without building a tree:

```perl
use Text::KDL::XS;   # loads Text::KDL::XS::Parser as well

open my $fh, '<:raw', 'huge.kdl' or die $!;
my $p = Text::KDL::XS::Parser->new($fh);
while (my $ev = $p->next_event) {
    print $ev->{name}, "\n" if $ev->{event} eq 'start_node';
}
```

## Modules

| Module                                                     | Role                                                   |
|------------------------------------------------------------|--------------------------------------------------------|
| [`Text::KDL::XS`](https://metacpan.org/pod/Text::KDL::XS)                      | `parse_kdl`, `emit_kdl`, options, encoding, errors     |
| [`Text::KDL::XS::Cookbook`](https://metacpan.org/pod/Text::KDL::XS::Cookbook)  | Every KDL feature with KDL and Perl examples; recipes  |
| [`Text::KDL::XS::Parser`](https://metacpan.org/pod/Text::KDL::XS::Parser)       | Streaming event parser                                 |
| [`Text::KDL::XS::Document`](https://metacpan.org/pod/Text::KDL::XS::Document)   | Container for the top-level nodes                      |
| [`Text::KDL::XS::Node`](https://metacpan.org/pod/Text::KDL::XS::Node)           | A node: name, type annotation, args, props, children   |
| [`Text::KDL::XS::Value`](https://metacpan.org/pod/Text::KDL::XS::Value)         | A typed value: null, bool, number, string              |
| [`Text::KDL::XS::Emitter`](https://metacpan.org/pod/Text::KDL::XS::Emitter)     | Internal emitter helpers                               |

## Features

- Tree API (`parse_kdl` / `emit_kdl`) with faithful round-tripping of
  argument order, property order, type annotations and number kinds.
- Streaming event API for memory-bounded processing of large documents,
  with optional reporting of comments and slashdashed elements.
- Sources: strings, filehandles, IO objects, code references.
- Complete value model: distinct null and booleans, integers, floats,
  arbitrary-precision numbers kept as text, `#inf`/`#-inf`/`#nan`.
- KDL 1.0.0 and 2.0.0, detected automatically or pinned with
  `version => '1' | '2'`; emit in either version.
- Plain-Perl data emission for the "just write my config" case.
- Passes the upstream KDL test suites for both versions (the remaining
  differences are listed in `FINDINGS.md` in the repository).

## Known issues

The bundled ckdl release has a defective float formatter: some floating
point values are emitted with wrong or missing digits. Perl integers and
short decimals are fine; for anything else format the number yourself and pass
it as a string-encoded number. This and a few smaller issues (UTF-8
character strings as parser input, filehandles with encoding layers,
strings equal to `true`/`null`/`-1` being emitted bare) are described with
workarounds in `perldoc Text::KDL::XS`, section "KNOWN ISSUES AND
LIMITATIONS", and in detail in
[`FINDINGS.md`](https://github.com/Davenonymous/perl-kdl-xs/blob/master/FINDINGS.md)
in the source repository (the file is not part of the CPAN tarball).

## Installation

```sh
perl Makefile.PL
make
make test
make install
```

`Text::KDL::XS` links statically against ckdl through
[`Alien::ckdl`](https://github.com/davenonymous/perl-alien-ckdl), which
builds the C library from source. No system package is needed; a C11
compiler is.

## Status

Version 0.001 is the first CPAN release. The API (`parse_kdl`, `emit_kdl`,
`Parser`, `Document`, `Node`, `Value`) is expected to stay stable; the
issues listed above are planned fixes for the next releases.

## See also

- [KDL specification](https://github.com/kdl-org/kdl) and [kdl.dev](https://kdl.dev)
- [ckdl](https://github.com/tjol/ckdl), the underlying C library
- [`Alien::ckdl`](https://github.com/davenonymous/perl-alien-ckdl)

## License

Copyright (C) 2026 Davenonymous.

This Perl distribution is released under the same terms as Perl itself.
The bundled `ckdl` library (linked statically through `Alien::ckdl`) is
MIT-licensed.
