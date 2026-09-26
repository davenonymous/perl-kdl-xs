package Text::KDL::XS;

use strict;
use warnings;

our $VERSION = '0.001';

use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

use Text::KDL::XS::Parser;
use Text::KDL::XS::Value;
use Text::KDL::XS::Node;
use Text::KDL::XS::Document;

use Exporter 'import';
our @EXPORT_OK = qw(parse_kdl emit_kdl);

# parse_kdl($source, %opts) -> Text::KDL::XS::Document
#   $source : string | filehandle | coderef
#   %opts   : version => 'detect'|'1'|'2', emit_comments => 0|1
sub parse_kdl {
    my ($source, %opts) = @_;
    my $parser = Text::KDL::XS::Parser->new($source, %opts);
    return Text::KDL::XS::Document->_build_from_parser($parser);
}

# emit_kdl($tree, %opts) -> string
#   $tree : Text::KDL::XS::Document | Text::KDL::XS::Node | arrayref of Nodes
sub emit_kdl {
    my ($tree, %opts) = @_;
    require Text::KDL::XS::Emitter;
    return Text::KDL::XS::Emitter->_emit_tree($tree, %opts);
}

1;

__END__

=encoding utf-8

=head1 NAME

Text::KDL::XS - KDL Document Language parser and emitter built on libckdl

=head1 SYNOPSIS

=for highlighter language=Perl

  use Text::KDL::XS qw(parse_kdl emit_kdl);
  binmode STDOUT, ':encoding(UTF-8)';   # parsed strings are Perl characters

  # Parse a string (or a filehandle, or a code reference returning chunks).
  my $doc = parse_kdl(<<'KDL');
  package "kdl-rs" {
      version "0.4.0"
      author "Kat Marchán" email="kat@example.com"
      keywords "config" "data"
  }
  KDL

  # Walk the tree.
  for my $node (@{ $doc->nodes }) {
      print $node->name, "\n";                              # package
      print $node->args->[0]->as_string, "\n";              # kdl-rs
      for my $child (@{ $node->children }) {
          printf "  %s", $child->name;
          printf " %s", $_->as_string for @{ $child->args };
          printf " %s=%s", $_->[0], $_->[1]->as_string for @{ $child->props };
          print "\n";
      }
  }

  # Look up a property, with type information intact.
  my $email = $doc->nodes->[0]->children->[1]->prop('email');
  print $email->type;        # string
  print $email->as_string;   # kat@example.com

  # Write it back out (tree mode: preserves order, kinds and annotations).
  print emit_kdl($doc);

  # Or serialise plain Perl data (data mode).
  print emit_kdl({ server => { host => 'localhost', port => 8080 } });
  # server {
  #     host localhost
  #     port 8080
  # }

=for highlighter

=head1 DESCRIPTION

C<Text::KDL::XS> reads and writes documents in the
L<KDL Document Language|https://kdl.dev>, a small configuration and data
language that looks like this:

=for highlighter language=KDL

  node "argument" key="value" {
      child 1 2 3
      (type)annotated #true
  }

=for highlighter

It is a thin XS binding to L<ckdl|https://github.com/tjol/ckdl>, a C11
implementation that passes the official KDL test suites. Both KDL
B<2.0.0> (current) and KDL B<1.0.0> (legacy) are supported, and the version
is detected automatically unless you pin it.

The distribution provides:

=over 4

=item * L</parse_kdl>, which turns KDL text into a tree of
L<Text::KDL::XS::Document>, L<Text::KDL::XS::Node> and
L<Text::KDL::XS::Value> objects.

=item * L</emit_kdl>, which turns such a tree, or plain Perl hashes and
arrays, back into KDL text.

=item * L<Text::KDL::XS::Parser>, a streaming (SAX-style) event parser for
documents that should not be held in memory at once.

=back

A tour of every KDL feature with runnable examples is in
L<Text::KDL::XS::Cookbook>. This page is the API reference.

=head1 QUICK REFERENCE

=over 4

=item parse a string, a file, a stream

L</parse_kdl>, L</"Sources">

=item choose KDL v1 or v2, detect the version

L</"parse_kdl options">, L</"KDL VERSIONS">

=item write KDL from Document and Node objects

L</emit_kdl>, L</"Tree mode">

=item write KDL from hashes and arrays

L</"Data mode">, L</"Scalar coercion">

=item control indentation, escaping, quoting

L</"emit_kdl options">

=item read comments and slashdashed elements

L<Text::KDL::XS::Parser>

=item access nodes, arguments, properties, children

L<Text::KDL::XS::Node>

=item strings, numbers, booleans, null, type annotations

L<Text::KDL::XS::Value>

=item big integers, 1e400, #inf, #nan, number kinds

L<Text::KDL::XS::Value/"VALUE MODEL">,
L<Text::KDL::XS::Value/"ARBITRARY PRECISION NUMBERS">

=item UTF-8 and character strings

L</ENCODING>

=item filehandles, STDIN, pipes, in-memory handles

L</"FILEHANDLE SOURCES">

=item what dies and when

L</ERRORS>

=item known problems and workarounds

L</"KNOWN ISSUES AND LIMITATIONS">

=item feature-by-feature examples and recipes

L<Text::KDL::XS::Cookbook>

=back

=head1 EXPORTS

Nothing is exported by default. Request the functions you need:

=for highlighter language=Perl

  use Text::KDL::XS qw(parse_kdl emit_kdl);

=for highlighter

Loading C<Text::KDL::XS> also loads L<Text::KDL::XS::Parser>,
L<Text::KDL::XS::Document>, L<Text::KDL::XS::Node> and
L<Text::KDL::XS::Value>. L<Text::KDL::XS::Parser> cannot be loaded on its
own (see L</"KNOWN ISSUES AND LIMITATIONS">); always C<use Text::KDL::XS>
first.

=head1 FUNCTIONS

=head2 parse_kdl

=for highlighter language=Perl

  my $doc = parse_kdl($source);
  my $doc = parse_kdl($source, version => '2');
  my $doc = parse_kdl($source, %options);

=for highlighter

Parses a complete KDL document and returns a L<Text::KDL::XS::Document>.
Dies on malformed input (see L</ERRORS>).

=head3 Sources

C<$source> is one of:

=over 4

=item A string

The document text as UTF-8 B<bytes>. This is the fastest source; the
string is copied once and ckdl reads from the copy. See L</ENCODING> for
what to do with Perl character strings.

=item A glob reference or IO object

A reference to a filehandle (C<\*STDIN>, C<$fh> from C<open>), or an
object with a C<sysread> or C<read> method (L<IO::Handle>, L<IO::File>,
L<IO::Socket>). Note the backslash: a bare C<*STDIN> is not a reference
and is parsed as the text C<*main::STDIN>.

The handle is read in chunks with C<sysread> (or the object's C<sysread>
or C<read> method), which means it must be backed by a real file
descriptor and should not have a C<:utf8> or C<:encoding(...)> layer.
Because C<sysread> bypasses PerlIO's buffer, do not read from the handle
with C<< <$fh> >> or C<read> before passing it in. In-memory handles
(C<< open my $fh, '<', \$string >>) are not supported; pass C<$string>
directly. See L</"FILEHANDLE SOURCES"> for the details.

=item A code reference

Called repeatedly as C<< $code->($wanted_bytes) >>. It must return the next
chunk of the document as a byte string of B<at most C<$wanted_bytes>>
bytes (at most 4096; the number can vary from call to call), and an empty
string or C<undef> when the input is exhausted. Bytes beyond C<$wanted_bytes> are discarded without an error,
which silently loses data, so hand over at most that many. Chunk
boundaries need not align with lines or tokens. Exceptions thrown inside
the callback are swallowed and treated as end of input.

=back

=head3 parse_kdl options

=over 4

=item version => 'detect' | '1' | '2'

Which KDL syntax to accept. The default C<'detect'> accepts both and
settles on one at the first version-specific construct (C<#true> versus
C<true>, C<#"raw"#> versus C<r"raw">, a bare identifier used as a value).
C<'1'> and C<'2'> accept exactly one version and reject the other's syntax.
The value is compared case-insensitively. Any other value dies with
C<unknown version '...' (expected 'detect', '1', or '2')> (the value is
reported in lower case).

See L</"KDL VERSIONS"> for how the versions differ.

=item emit_comments => 0 | 1

Do not pass this to C<parse_kdl>. The option makes the underlying parser
report slashdashed nodes, arguments, properties and children blocks as
ordinary events flagged C<commented>, and the tree builder ignores that
flag, so C<< parse_kdl($src, emit_comments => 1) >> puts everything that
was commented out with C</-> back into the document (comment events
themselves are discarded). Use L<Text::KDL::XS::Parser> when you need
comments.

=back

Unknown options are ignored.

=head3 Return value

A L<Text::KDL::XS::Document>. Its C<nodes> method returns the top-level
nodes as L<Text::KDL::XS::Node> objects; every argument and property value
is a L<Text::KDL::XS::Value>. Node names, property keys, string values and
type annotations are returned as Perl character strings. An empty or
comment-only document gives a document with no nodes.

=head2 emit_kdl

=for highlighter language=Perl

  my $text = emit_kdl($document);
  my $text = emit_kdl($node);
  my $text = emit_kdl(\@nodes);
  my $text = emit_kdl(\%data);
  my $text = emit_kdl(\@data);
  my $text = emit_kdl($anything, %options);

=for highlighter

Serialises a tree or a plain data structure to KDL and returns the text as
a Perl character string (encode it as UTF-8 before writing it to a file;
see L</ENCODING>). The output ends with a newline unless it is empty.

The mode is chosen from the type of the first argument.

=head3 Tree mode

Selected when the argument is a L<Text::KDL::XS::Document>, a
L<Text::KDL::XS::Node>, or an array reference whose elements are all
L<Text::KDL::XS::Node> objects. An empty array reference produces an empty
string; an array that mixes nodes with anything else dies.

Tree mode is faithful: it writes arguments and properties in their stored
order, keeps type annotations on nodes and values, keeps the
integer/float/string distinction of numbers (C<1.0> stays C<1.0>), and
writes repeated properties as often as they occur. It is the mode to use
for round-tripping a parsed document. What it does not preserve (comments,
layout, number spelling) is listed in
L<Text::KDL::XS::Cookbook/"What a round trip loses">.

Argument and property values inside the tree are normally
L<Text::KDL::XS::Value> objects, but plain scalars and boolean objects are
accepted too and are coerced as described under L</"Scalar coercion">.

=head3 Data mode

Selected for any other hash or array reference. Data mode is a convenience
for writing configuration from ordinary Perl data; it is deterministic but
lossy. Every hash key becomes a node; data mode never writes properties.

  Perl value                       Emitted as
  -------------------------------  ----------------------------------------------
  { key => $scalar }               key <value>
  { key => undef }                 key #null
  { key => [ $s1, $s2, ... ] }     key <s1> <s2> ...      (all elements scalars)
  { key => [] }                    key                    (bare node)
  { key => {} }                    key                    (bare node)
  { key => { ... } }               key { <children> }
  { key => [ {...}, {...} ] }      key { ... }  key { ... }   (one sibling per element)
  { key => [ $s, {...} ] }         key <s>  key { ... }   (mixed: one sibling per element)
  { key => [ [1,2], [3] ] }        key 1 2  key 3         (inner arrays: one sibling each)
  [ $a, $b, ... ]   (top level)    - <a>  - <b>  ...      (nodes named "-")
  {} or []          (top level)    (empty string)
  boolean object                   #true / #false
  Text::KDL::XS::Value object      as the object says (type, kind, annotation)

Hash keys are emitted in sorted order. Scalar values are classified by
L</"Scalar coercion">.

What data mode cannot express: properties; arguments and children on the
same node; a specific node order (keys are sorted); type annotations on
nodes; and the difference between C<< { key => 'a' } >> and
C<< { key => ['a'] } >> (both give C<key a>). Build a
L<Text::KDL::XS::Node> tree when you need any of these.

=head3 Scalar coercion

Plain Perl scalars that reach the emitter, in either mode, are mapped like
this:

  Perl scalar                                     KDL value
  ----------------------------------------------  ---------------------------
  undef                                           #null
  JSON::PP::Boolean, Types::Serialiser::Boolean,
    JSON::Boolean, boolean, Mojo::JSON::_Bool     #true / #false (by truthiness)
  Text::KDL::XS::Value                            as specified by the object
  scalar with only a string value                 string
  scalar with an integer value (IV)               number, integer
  scalar with a floating point value (NV)         number, float
  any other scalar                                string

The decision uses the scalar's internal flags, not its appearance. C<'42'>
from a string literal is a string; C<42> is a number; C<'42'> after it has
been used in arithmetic is a number. Force one or the other with
C<"$x"> or C<0 + $x>. The strings C<'true'> and C<'false'> are never
promoted to booleans.

Other blessed objects (L<Math::BigInt>, L<URI>, ...) are handled
inconsistently in this release: in tree mode they are stringified and
written as a KDL string; in data mode they make C<emit_kdl> die with
C<cannot serialize ... ref>. Unblessed references other than the hashes
and arrays of data mode (code references, scalar references, globs) always
die.

=head3 emit_kdl options

=over 4

=item version => 'detect' | '1' | '2'

Output syntax. C<'2'> (and C<'detect'>, the default) writes KDL 2.0.0:
C<#true>, C<#null>, bare identifier strings where possible. C<'1'> writes
KDL 1.0.0: C<true>, C<null>, every string value quoted. The special
numbers are always written as C<#inf>, C<#-inf> and C<#nan> because v1 has
no spelling for them. The value is compared case-sensitively; anything else
dies with C<emit_kdl: unknown version '...'>.

=item indent => $columns

Number of spaces per nesting level. Default 4.

=item escape_mode => $bitmask

Which characters inside quoted strings are written as escape sequences.
Values are the ckdl C<kdl_escape_mode> flags:

  0       minimal: " and \, plus (in v2 output) the characters KDL never
          allows literally: U+0000 to U+0008, U+000E to U+001F, U+007F,
          the bidi controls and U+FEFF, which are always written as \u{...}
  0x10    also escape backspace (\b) and vertical tab
  0x20    also escape newline characters: LF, CR, FF, NEL, LS, PS
  0x40    also escape tabs
  0x70    default (control characters, newlines and tabs)
  0x170   ASCII only: every non-ASCII character becomes \u{...}

C<0x10>, C<0x20> and C<0x40> combine with bitwise or; C<0x170> is a preset
(C<0x100> has an effect only together with all of C<0x70>). Without
C<0x20> a string containing a newline is written with the newline inside
the quotes, which is not valid KDL v2 (v1 accepts it). In v1 output mode
C<0> really is minimal and writes control characters literally.

=item identifier_mode => 0 | 1 | 2

How node names, property keys, type annotations and (in v2) string values
are written:

  0    bare whenever the characters allow it (default)
  1    always quoted
  2    bare only when pure ASCII

Mode 1 is the safe choice when strings, names or keys may equal C<true>,
C<false>, C<null>, C<inf>, C<nan> or look like numbers; see
L</"KNOWN ISSUES AND LIMITATIONS">.

=back

Unknown options are ignored.

=head1 ENCODING

KDL documents are UTF-8 by definition. The rules for this module are:

=over 4

=item * Input to L</parse_kdl> and L<Text::KDL::XS::Parser> must be UTF-8
B<bytes>: a byte string, a raw filehandle, or a code reference returning
byte strings.

=item * Everything the parser returns (names, keys, strings, annotations)
is a Perl B<character> string with the UTF-8 flag on.

=item * L</emit_kdl> takes Perl character strings and returns a character
string. Encode it when writing it out, either explicitly
(C<encode('UTF-8', $text)>) or through an C<:encoding(UTF-8)> output
layer. Printing it to a handle without a layer writes a string whose
non-ASCII characters are all below U+0100 as Latin-1 bytes (wrong for a
UTF-8 consumer), and a string containing a character above U+00FF as
UTF-8 with a "Wide character" warning.

=back

In this release, giving C<parse_kdl> a character string that contains
non-ASCII characters does not work: characters below U+0100 are passed to
ckdl as Latin-1 bytes (which produces a parse error or wrong text) and
characters at or above U+0100 make it die with C<Wide character in
subroutine entry>. Encode such strings first:

=for highlighter language=Perl

  use utf8;
  use Encode qw(encode);
  my $doc = parse_kdl(encode('UTF-8', "café \"✓\"\n"));

=for highlighter

Byte strings that already contain UTF-8, such as a heredoc in a source file
without C<use utf8> or data read through a C<:raw> handle, need no
conversion. Invalid UTF-8 in the input is a parse error.

=head1 FILEHANDLE SOURCES

The parser reads filehandles with C<sysread>, in chunks of the size the
underlying library asks for. Consequences:

=over 4

=item * Handles should be raw: open them with C<:raw> or call C<binmode>.
A handle with a C<:utf8> or C<:encoding(...)> layer makes C<sysread> fail,
and the failure is currently reported as end of input rather than as an
error, so you get an empty or truncated document. A C<:crlf> layer is
ignored by C<sysread> and does no harm.

=item * Do not mix buffered reads and C<parse_kdl> on the same handle.
Anything PerlIO has already buffered is invisible to C<sysread>.

=item * In-memory handles have no file descriptor and read as empty. Pass
the string to C<parse_kdl> instead.

=item * Pipes, sockets and C<STDIN> work; the parser simply blocks until
enough bytes arrive or the peer closes the connection.

=back

When these constraints are inconvenient, read the file yourself and pass a
string, or pass a code reference that returns chunks.

=head1 KDL VERSIONS

KDL 1.0.0 (2021) and KDL 2.0.0 (2024) share most of their syntax, and any
document that parses under both versions has the same meaning under both.
The differences that matter most when reading or writing with this module
are the C<#> prefix on C<#true>, C<#false> and C<#null>; bare identifier
strings as values (v2 only); raw strings C<#"..."#> (v2) versus
C<r"..."> (v1); and multi-line strings C<"""> (v2) versus literal newlines
inside quotes (v1). The complete table is in
L<Text::KDL::XS::Cookbook/"Differences between KDL v1 and v2">.

With the default C<< version => 'detect' >>, the parser accepts either
until the first construct that only exists in one version, and then
requires that version for the rest of the document. To reject the other
version outright, pin C<version>. The parser does not report which version
it detected; L<Text::KDL::XS::Cookbook/"Version detection"> shows how to
find out.

C<emit_kdl> defaults to v2 output. Pass C<< version => '1' >> to write
legacy documents; the parsed data is identical either way, so converting a
document between versions is a parse followed by an emit
(L<Text::KDL::XS::Cookbook/"Converting between versions">).

=head1 ERRORS

All errors are exceptions (C<die>). The messages you can expect:

=over 4

=item C<KDL parse error at .../Text/KDL/XS/Parser.pm line 39.>

The input is not valid KDL for the selected version. Raised by
C<parse_kdl> and by L<Text::KDL::XS::Parser/next_event>. The underlying
library provides no line or column information, and in this release its
reason text (such as C<Unexpected end of data (unclosed lists of
children)>) is not included in the message. The error is attributed to a
line inside C<Text::KDL::XS::Parser> rather than to your call site.

=item C<Text::KDL::XS::Parser: source is required>

C<parse_kdl(undef)>.

=item C<Text::KDL::XS::Parser: unsupported source ref type 'X'>

The source was a reference that is neither a code reference nor a
filehandle-like object (for example an array or hash reference).

=item C<unknown version 'X' (expected 'detect', '1', or '2')>

Bad C<version> option to C<parse_kdl>.

=item C<Wide character in subroutine entry>

C<parse_kdl> was given a character string with a character above U+00FF,
or a code reference returned one. See L</ENCODING>.

=item C<emit_kdl: unknown version 'X'>

Bad C<version> option to C<emit_kdl>.

=item C<emit_kdl: expected Document, Node, ARRAY ref, or HASH ref>

C<emit_kdl> was given a plain scalar or an unsupported reference.

=item C<emit_kdl: cannot serialize X ref>

Data mode met a value it cannot convert (a code reference, a scalar
reference, a Node inside a data-mode array, an object that is not a
boolean or a L<Text::KDL::XS::Value>).

=item C<emit_kdl: refs cannot appear as a single scalar value here>

A reference was found where tree mode expected a scalar or C<Value>
object (for example a hash reference inside C<< $node->args >>).

=item C<emit_kdl: tree mode expects Text::KDL::XS::Node, got X>

An element of C<< $node->children >> or C<< $doc->nodes >> is not a Node.

=item C<emit_arg: unknown value type 'X'>, C<emit_property: unknown value type 'X'>

A hand-built L<Text::KDL::XS::Value> has a C<type> other than C<null>,
C<bool>, C<number> or C<string>.

=item C<Text::KDL::XS::Value-E<gt>new: 'type' is required>

C<< Text::KDL::XS::Value->new >> without a C<type>.

=item C<Undefined subroutine &Text::KDL::XS::_OPT_DETECT called>

L<Text::KDL::XS::Parser> was loaded without C<Text::KDL::XS>. Add
C<use Text::KDL::XS;>.

=back

Warnings you may see: C<Use of uninitialized value> from the emitter when
a number C<Value> has no C<kind>; C<Argument "..." isn't numeric> from
C<as_number> on a non-numeric string; C<Deep recursion> from
C<emit_kdl> and C<as_data> on documents nested 100 or more levels deep.

=head1 KNOWN ISSUES AND LIMITATIONS

This is the complete list for the current release, with the workaround
for each. The identifiers in brackets refer to the maintainer's
C<FINDINGS.md> in the source repository
(L<https://github.com/Davenonymous/perl-kdl-xs>), which has reproduction
steps and suggested fixes; that file is not part of the CPAN tarball.

=over 4

=item Floating point output can be wrong [C1]

The float formatter in the bundled ckdl release drops digits or produces
wrong digits for many values: C<0.1 + 0.2> is written as C<0.3>,
C<123456789.0> as C<1.2345679e8>, C<1908124443056.387> as
C<1.098124443056387e12>. Perl integers (IV) are unaffected; floating
point values (NV) are affected even when integral. Short decimals such as
C<3.14> and C<0.5> come out right. If precision matters, format the number
yourself and pass it as a string-encoded number; see
L<Text::KDL::XS::Cookbook/"Emitting floating point numbers safely">.

=item Character strings are not accepted as parser input [C2]

See L</ENCODING>. Encode to UTF-8 first.

=item Integers above 2**63-1 are emitted incorrectly [C3]

A Perl unsigned integer larger than C<9223372036854775807> is written as a
negative number. Pass such values as string-encoded numbers
(C<< Text::KDL::XS::Value->new(type => 'number', kind => 'string', value => "$n") >>).

=item Passing C<emit_comments> to C<parse_kdl> resurrects slashdashed content [C4]

See L</"parse_kdl options">. Never pass the option to C<parse_kdl>.

=item Number kinds do not follow the 64-bit rule exactly [M7]

Integers with a magnitude from 2**31 to 2**32-1 (for example
C<0xFFFFFFFF>, or Unix timestamps after 2038) and the value
-9223372036854775808 come back as C<< kind => 'string' >> rather than
C<'integer'>; decimals with 16 or more digits written before the exponent
(leading and trailing zeros count) or a written exponent beyond 284 come
back as C<'string'> rather than C<'float'>. The text is exact in every
case. Do not rely on C<kind> to judge a number's size; see
L<Text::KDL::XS::Value/"VALUE MODEL">.

=item Parse errors carry no reason and no position [M1, U1, m3]

See L</ERRORS>. The error is also attributed to a line inside this
distribution rather than to your call site.

=item Filehandles must be raw, unread, and real [M2]

See L</"FILEHANDLE SOURCES">. Exceptions thrown by a code reference source
are swallowed and treated as end of input.

=item Code reference chunks longer than requested are truncated [M6]

Bytes beyond C<$wanted_bytes> are dropped silently. Return at most
C<$wanted_bytes> per call; see L</Sources>.

=item Strings equal to keywords or numbers are emitted bare [M3]

The strings C<true>, C<false>, C<null>, C<inf>, C<-inf>, C<nan>, and
strings that look like numbers (C<-1>, C<+1>, C<.5>), are written without
quotes as v2 values and as node names and property keys in both versions,
and therefore change meaning or fail to parse. Use
C<< identifier_mode => 1 >> when your data may contain them.

=item Comment text is not exposed [M4]

The streaming parser reports where comments are, not what they say.

=item Blessed objects are handled inconsistently by the emitter [M5]

See L</"Scalar coercion">.

=item An empty document is emitted as the empty string [m5]

Other emitters write a single newline. Harmless unless you compare bytes.

=item C<version> is case-insensitive for parsing only [m7]

C<parse_kdl> accepts C<'DETECT'>; C<emit_kdl> does not.

=item C<as_number> returns text for arbitrary precision numbers [m9]

See L<Text::KDL::XS::Value/as_number>; use L<Math::BigInt> or
L<Math::BigFloat> for exact arithmetic.

=item C<prop> does not work on hand-built or restructured nodes [m1]

C<< $node->prop >> uses an index built by the parser. A node created with
C<< Text::KDL::XS::Node->new >> has none (C<prop> returns C<undef>), and
adding, removing or reordering entries of C<< $node->props >> leaves the
index stale. Iterate C<props> in those cases.

=item Duplicate properties are all re-emitted [m2]

C<node a=1 a=2> is written back as C<node a=1 a=2>; other implementations
write C<node a=2>. Both parse to the same data.

=item Write failures inside the emitter are not detected [m4]

The XS layer ignores ckdl's success flag.

=item Unknown options are silently ignored [m6]

A misspelt option such as C<emit_comment> has no effect and no warning.

=item C<Text::KDL::XS::Parser> cannot be loaded on its own [m10]

C<use Text::KDL::XS::Parser;> without C<use Text::KDL::XS;> dies at the
first C<new> (the same applies to the internal Emitter; Value, Node and
Document load fine alone). Load C<Text::KDL::XS> first.

=item Surrogate escapes are accepted in v1 and detect mode [m11]

C<\u{D800}> to C<\u{DFFF}> are forbidden by the specification.
C<< version => '2' >> rejects them; C<< version => '1' >> and the default
detection accept them and return a Perl string containing a lone
surrogate. C<\u{}> with no digits is accepted everywhere and yields
U+0000 [m15].

=item Detect mode accepts C<.5> as an identifier [m12]

C<.5>, C<-.5> and C<+.5> are rejected by both C<< version => '1' >> and
C<< version => '2' >> but accepted as strings by the default detection.

=item C<escape_mode> without C<0x20> writes literal newlines [m13]

The output is not valid KDL v2; see L</"emit_kdl options">.

=item A children block needs whitespace before it [U2]

KDL 2.0.0 requires it, so C<node{}> is correctly rejected in v2, but ckdl
rejects it in v1 mode as well although KDL 1.0.0 allows it. Write
C<node {}>.

=item Vertical tab is whitespace, not a newline [U5]

KDL 2.0.0 lists U+000B as a newline; ckdl treats it as whitespace.

=item Special numbers are always written in v2 syntax [U4]

C<#inf>, C<#-inf> and C<#nan> appear even in v1 output, where they are not
valid.

=item Detect mode is not a complete KDL v1 parser [U3]

ckdl documents the hybrid mode as exact for v2 and for I<almost> all v1
documents. Pin C<< version => '1' >> for strict v1.

=item No nesting limit [m14]

Deeply nested input parses (the tree builder is iterative), but
C<emit_kdl>, C<as_data> and any recursive walk of your own recurse once
per level. Check the depth with the streaming parser before building a
tree from untrusted input
(L<Text::KDL::XS::Cookbook/"Parse untrusted input">).

=back

=head1 PERFORMANCE NOTES

Parsing from a string is the fastest path: the document is handed to ckdl
as a single buffer and each event is converted to Perl objects once.
Filehandle and code reference sources cost one Perl callback per chunk.
The streaming parser avoids building the tree and is the right tool for
very large documents or for extracting a few values from a big file.

Values are created as small blessed hashes; a document with a million
values needs about 500 MB as a tree. Use L<Text::KDL::XS::Parser> for
anything of that size.

The module has no global state apart from the loaded XS code; parser and
emitter objects are independent and may be used from different threads or
after C<fork> as long as each object stays with one thread. It requires
Perl 5.12 or newer.

=head1 SEE ALSO

=over 4

=item L<Text::KDL::XS::Cookbook>

Every KDL feature with KDL and Perl examples, plus recipes.

=item L<Text::KDL::XS::Parser>, L<Text::KDL::XS::Document>, L<Text::KDL::XS::Node>, L<Text::KDL::XS::Value>

The classes that make up the API.

=item L<Text::KDL::XS::Emitter>

Internal; documented for completeness.

=item L<Alien::ckdl>

Builds and provides the ckdl library this module links against; its
C<alienfile> pins the ckdl commit that is compiled.

=item L<https://kdl.dev>, L<https://github.com/kdl-org/kdl>

The KDL specification and reference test suite.

=item L<https://github.com/tjol/ckdl>

The C library doing the actual parsing and emitting.

=back

=head1 AUTHOR

Davenonymous E<lt>perl@davenonymous.comE<gt>

=head1 LICENSE

Copyright (C) 2026 Davenonymous.

This Perl distribution is licensed under the same terms as Perl itself.
The bundled C<ckdl> library (linked statically via L<Alien::ckdl>) is
MIT-licensed.

=cut
