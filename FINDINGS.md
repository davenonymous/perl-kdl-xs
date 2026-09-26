# Code findings for Text::KDL::XS

Issues discovered while documenting the distribution on 2026-09-26. Each
entry was reproduced against the current checkout (version 0.001) built
against the ckdl commit pinned by Alien::ckdl. Nothing in this file has been
fixed; the documentation describes the behaviour as it is today and points
here where it matters.

Severity scale:

- **Critical** - silently produces wrong data.
- **Major** - fails or misbehaves on reasonable input.
- **Minor** - rough edge, easy to work around.
- **Upstream** - lives in ckdl, not in this distribution.

Reproduction snippets assume `perl -Mblib` from the build directory and
`use Text::KDL::XS qw(parse_kdl emit_kdl);`.

---

## Critical

### C1. Floating point numbers are emitted with wrong digits (upstream, ckdl)

`kdl_emitter` formats doubles with a hand-written digit loop
(`src/emitter.c`, `_float_to_string`). It is not a shortest-round-trip
algorithm and it is not even monotonic: some values lose the last digits,
some are rounded to fewer digits than needed, and some come out with a
different digit sequence altogether.

```perl
print emit_kdl({ n => 1908124443056.387 });   # n 1.098124443056387e12   (1908 became 1098)
print emit_kdl({ n => 123456789012345.0 });   # n 1.23456780912345e14    (789 became 809)
print emit_kdl({ n => 0.1 + 0.2 });           # n 0.3                    (was 0.30000000000000004)
print emit_kdl({ n => 2**53 });               # n 9.00719925475e15       (was 9007199254740992)
print emit_kdl({ n => 5e-324 });              # n -2147483648e-324       (garbage, int overflow)
print emit_kdl({ n => 123456789.0 });         # n 1.2345679e8            (re-parses as 123456790)
```

A random sample of 5000 doubles spread over 40 decades failed to round-trip
in 3215 cases. Perl integers (IV) are unaffected; integral doubles are not
safe either (`123456789.0` and `2**53` above, while `1e15 + 1` and
`3e17` happen to be fine). "Short" decimals such as `3.14` or `100.5` are
fine, which is why the existing test suite does not notice. ckdl also prints a warning to stderr
(`ckdl WARNING - _float_to_string calculated digit > 9`) for some inputs.

Impact: every float that reaches the emitter, in tree mode or data mode, may
be written incorrectly. Values with few significant digits are usually fine.

Workaround (documented in the POD): format the number yourself and hand the
emitter a string-encoded number, which ckdl copies verbatim:

```perl
my $v = Text::KDL::XS::Value->new(type => 'number', kind => 'string',
                                  value => sprintf('%.17g', $float));
```

Suggested fix in this distribution: in `Text::KDL::XS::Emitter`, convert
every `kind => 'float'` payload into `kind => 'string'` using a
shortest-round-trip formatter (Perl's own `"$nv"` stringification with
`%.15g` is not enough; `sprintf('%.17g')` always round-trips, or use a
Grisu/Ryu style formatter) before calling the XS layer. Do the same in
`XS.xs` for `KDL_NUMBER_TYPE_FLOATING_POINT` if the Perl layer is bypassed.
Report upstream to https://github.com/tjol/ckdl.

### C2. Perl character strings are parsed as Latin-1 bytes

`_new_string_parser` (`XS.xs:209`, `XS.xs:216`) fetches the source with
`SvPVbyte`. ckdl expects UTF-8. For a Perl string that carries the UTF-8
flag this either downgrades to Latin-1 (all characters below U+0100) or
croaks (any character at U+0100 or above):

```perl
parse_kdl("caf\x{e9} 1\n");      # dies: KDL parse error   (0xE9 is not valid UTF-8)
parse_kdl("n \"\x{2713}\"\n");   # dies: Wide character in subroutine entry
parse_kdl("caf\xc3\xa9 1\n");    # works: byte string that is already UTF-8
```

The same applies to chunks returned by a code reference source
(`ptkx_read_thunk`, `XS.xs:121`). Filehandles are unaffected because
`sysread` always returns bytes.

Meanwhile the emitter (`_emit_node`, `_emit_arg`, `_emit_property`) uses
`SvPVutf8`, i.e. it treats its input as *characters* and encodes on the way
out. Parser and emitter therefore disagree about what a Perl string means:

```perl
my $doc = parse_kdl("caf\xc3\xa9 1\n");          # name is the 4-character string "café"
print emit_kdl({ "caf\xc3\xa9" => 1 });          # prints "cafÃ© 1" when printed through an :encoding(UTF-8) layer (double encoded)
print emit_kdl({ "caf\x{e9}" => 1 });            # prints "café 1"
```

Anything parsed and re-emitted round-trips correctly because the parser
always produces character strings; the asymmetry bites only when *input*
comes from Perl source code or from a decoded filehandle.

Suggested fix: use `SvPVutf8` in `_new_string_parser` and in the read
thunk, so that both directions consistently speak Perl character strings.
Document that byte strings must be decoded first (or, if backwards
compatibility for byte input matters, detect `SvUTF8` and only encode
flagged strings). Add tests with non-ASCII input in both forms.

### C3. Integers above IV_MAX wrap to negative numbers

`_emit_arg` / `_emit_property` cast with `(long long) SvIV(*sv_val)`
(`XS.xs:463`, `XS.xs:541`). A Perl UV larger than IV_MAX is truncated:

```perl
print emit_kdl({ a => 18446744073709551615 });   # a -1
print emit_kdl({ a => 9223372036854775808 });    # a -9223372036854775808
```

In data mode, `_coerce_scalar_to_payload` also classifies such values as
`integer` because `SVf_IOK` is set for UVs.

Suggested fix: check `SvIsUV` and, when the value does not fit in a signed
64-bit integer, emit it as `kind => 'string'` with the decimal digits.

### C4. `parse_kdl(..., emit_comments => 1)` resurrects slashdashed content

`Document::_build_from_parser` (`Document.pm`) never looks at the
`commented` flag of the events. With `emit_comments => 1` ckdl reports
slashdashed nodes, arguments, properties and children blocks as ordinary
events with that flag set, so they end up in the tree:

```perl
print emit_kdl(parse_kdl("/-a 1\nb /-2 /-k=3 /-{ c }\n", emit_comments => 1));
# a 1
# b 2 k=3 {
#     c
# }
print emit_kdl(parse_kdl("/-a 1\nb /-2 /-k=3 /-{ c }\n"));   # b
```

A `/- kdl-version 2` marker becomes a real node the same way. The option
is accepted silently by `parse_kdl` and was documented only as "ignored".

Suggested fix: skip events with `commented` set in `_build_from_parser`
(and drop `comment` events as now), or refuse the option in `parse_kdl`.

---

## Major

### M1. Parse errors discard ckdl's error message

ckdl reports the reason for a parse error in `ev->value.string`
(`_set_parse_error` in `src/parser.c`), with messages such as
`Unexpected end of data (unclosed lists of children)`, `Dangling slashdash
(/-)`, `Whitespace required before argument or property` or `Bare identifier
not allowed here`. `_next_event` (`XS.xs:282`) throws the constant string
`KDL parse error` and drops the message.

ckdl does not track line or column numbers, so a position cannot be added
without extending ckdl, but the message is available for free.

Suggested fix: `croak("KDL parse error: %.*s", (int) ev->value.string.len,
ev->value.string.data)`.

### M2. Filehandles with an encoding layer yield an empty or truncated document, silently

`_make_io_reader` (`Parser.pm:75`) uses `sysread`, which Perl refuses on
handles that have a `:utf8` or `:encoding(...)` layer (`sysread() isn't
allowed on :utf8 handles`). That exception is raised inside the read callback,
where `ptkx_read_thunk` (`XS.xs:108`-`XS.xs:118`) swallows it with `G_EVAL`
and reports a zero-length read. The parser sees EOF:

```perl
open my $fh, '<:encoding(UTF-8)', 'config.kdl';
my $doc = parse_kdl($fh);          # empty document, or "KDL parse error" if EOF lands mid-node
```

The same swallowing applies to any exception thrown by a code reference
source: `parse_kdl(sub { die "boom" })` returns an empty document with no
indication that the reader failed.

`sysread` also bypasses PerlIO buffering. If the caller has already read
part of the handle with `<$fh>` or `read`, the buffered bytes are lost:

```perl
open my $fh, '<', 'two-lines.kdl';
my $first = <$fh>;                 # PerlIO buffers the whole file
my $doc = parse_kdl($fh);          # zero nodes, not one
```

In-memory filehandles (`open my $fh, '<', \$string`) have no file
descriptor at all, so `sysread` fails with `Bad file descriptor` and the
result is again a silently empty document:

```perl
open my $fh, '<', \ "a 1\nb 2\n";
parse_kdl($fh)->nodes;             # []
```

Real files, sockets and pipes that have not been read from yet work.

Suggested fix: use `read` (PerlIO aware) instead of `sysread`, re-throw
exceptions from the callback after the ckdl call returns (store the error
in `ptkx_parser`, check it in `_next_event`), and document that the handle
must deliver bytes (`:raw`).

### M3. Strings that look like keywords or numbers are emitted bare and do not round-trip (upstream, ckdl)

In KDL v2 output, a *string* whose content is `true`, `false`, `null`,
`inf`, `-inf`, `nan`, or which starts like a number (`-1`, `.5`), is written
as a bare identifier by `_emit_bare_string` (`src/emitter.c:237`). The
result is either a syntax error or a different value on re-parse:

```perl
emit_kdl({ n => "true" });   # n true     -> parse error in v2; detect mode reads it back as a *boolean*
emit_kdl({ n => "-1" });     # n -1       -> re-parses as the number -1
emit_kdl({ n => "inf" });    # n inf      -> parse error
emit_kdl({ true => 6 });     # true 6     -> parse error (node name)
```

KDL v1 output quotes values correctly but still emits the *node names*
`true`, `null`, `-1` bare, which v1 parsers reject as well.

Workaround (documented): `identifier_mode => 1` quotes every identifier and
every string, which round-trips in both versions.

Suggested fix: report upstream; in the meantime the Perl layer could force
quoting for the reserved words and number-like strings by post-processing,
or default `identifier_mode` to 1 until ckdl is fixed.

### M4. Comment text is not passed to the caller

With `emit_comments => 1` the parser yields `{ event => 'comment' }`
events, but the comment body that ckdl provides in `ev->value.string`
(`_set_comment_event`, `src/parser.c`) is never copied into the event hash
(`XS.xs:295` handles the event name only, `value` is populated solely for
arguments and properties). The events are therefore only useful as
"a comment was here" markers.

Suggested fix: store the string as `text` in the event hash for
`real_event == 0`.

### M5. Data mode rejects stringifiable objects that the coercion layer claims to support

`_coerce_scalar_to_payload` (`Emitter.pm:239`) has a branch that
stringifies blessed objects such as `Math::BigInt` or `URI`. That branch is
unreachable from data mode: `_emit_data_pair` (`Emitter.pm:154`) only lets
plain scalars, boolean objects and `Text::KDL::XS::Value` objects through,
and croaks with `cannot serialize Math::BigInt ref` for everything else.
`_is_complex` likewise treats any other blessed object as complex, so
`[ Math::BigInt->new(1) ]` is expanded as repeated siblings and then dies.

Tree mode reaches the branch (a `Math::BigInt` inside `Node->args` is
emitted as a *string*, which is also questionable for a number).

Suggested fix: decide one behaviour. Either route blessed objects through
`_coerce_scalar_to_payload` in data mode too, or remove the dead branch and
document that only booleans and `Value` objects are accepted.

### M6. Code reference chunks longer than the requested size are silently truncated

`ptkx_read_thunk` (`XS.xs:121`-`XS.xs:124`) copies at most `bufsize`
bytes (`bufsize` is at most 4096 and can vary per call) and throws the
rest of the returned chunk away:

```perl
my $big = join '', map { "n$_ 1\n" } 1 .. 2000;   # 14893 bytes
my $done;
scalar @{ parse_kdl(sub { $done++ ? '' : $big })->nodes };   # 601, no error
```

When the cut lands inside a token the result is a parse error instead;
either way the caller gets no hint that data was dropped.

Suggested fix: keep the remainder in `ptkx_parser` and serve it on the next
call before invoking the callback again (or croak when a chunk is too
long). The POD now tells callers to return at most `$wanted_bytes`.

### M7. Number kinds do not follow the documented 64-bit / double rule (upstream, ckdl)

`kind` mirrors ckdl's `kdl_number_type`, and ckdl's classification is
narrower than "fits the C type":

```perl
parse_kdl("n 2147483648\n")->nodes->[0]->args->[0]->kind;            # string  (2**31)
parse_kdl("n 4294967295\n")->nodes->[0]->args->[0]->kind;            # string  (0xFFFFFFFF)
parse_kdl("n 4294967296\n")->nodes->[0]->args->[0]->kind;            # integer (2**32)
parse_kdl("n -9223372036854775808\n")->nodes->[0]->args->[0]->kind;  # string  (-2**63)
parse_kdl("n 3.141592653589793\n")->nodes->[0]->args->[0]->kind;     # string  (16 digits)
parse_kdl("n 1.22222222222222\n")->nodes->[0]->args->[0]->kind;      # float   (15 digits)
parse_kdl("n 1e285\n")->nodes->[0]->args->[0]->kind;                 # string  (1e284 is float)
```

Observed rule: integers are `integer` unless the magnitude lies in
2**31 .. 2**32-1 or equals 2**63; decimals are `float` only with at most
15 digits written before the exponent (leading and trailing zeros count,
underscores do not) and a written exponent within -284 .. 284. The text is
always exact, so no data is lost, but callers who branch on
`kind eq 'integer'` (32-bit masks, timestamps after 2038) or who expect a
`%.17g`-formatted double to come back as `float` are surprised. Affects
`Value.pm`'s documented model; the docs now describe the observed rule.

Suggested fix: classify in `ptkx_make_value_sv` (`XS.xs:64`) using Perl's
own `grok_number` / `SvIV` on the string-encoded text before falling back
to `kind => 'string'`. Report upstream.

---

## Minor

### m1. `Text::KDL::XS::Node->new(props => ...)` leaves `prop()` blind

`new` accepts `props` but only fills `prop_index` when it is passed
explicitly (`Node.pm:20`). A hand-built node therefore emits its properties
fine but `$node->prop('key')` returns `undef`:

```perl
my $n = Text::KDL::XS::Node->new(name => 'n', props => [[ k => $value ]]);
$n->prop('k');   # undef
```

Suggested fix: derive `prop_index` from `props` in the constructor and drop
the `prop_index` argument.

The index is also never updated: after `push @{ $node->props }, [ a => $v ]`
on a parsed node, `prop('a')` still returns the old value, and after a
`shift` every lookup is off by one. Suggested fix: drop the index and scan
`props` from the end in `prop`, or rebuild it lazily.

### m2. Duplicate properties are all re-emitted

`props` keeps every occurrence of a repeated key, and tree mode writes them
all (`node prop=10 prop=11`). The upstream test suite expects
`node prop=11`. The output is still valid KDL and re-parses to the same
data, so this is cosmetic, but it differs from every other implementation.

### m3. Parse errors are reported at `Parser.pm line 39`

`croak` from XS attributes the error to the nearest Perl frame, which is
inside this distribution, not the user's call site. Adding
`our @CARP_NOT` / using `Carp::croak` from the Perl wrapper with the right
`CarpLevel` would point at the caller.

### m4. Return values of the XS emitter calls are ignored

`_emit_node`, `_emit_arg`, `_emit_property`, `_start_children`,
`_finish_children` and `_emit_end` return ckdl's `bool` success flag, and
`Emitter.pm` never checks it (`Emitter.pm:57`, `:82`, `:84`, `:88`, `:93`,
`:95`). A write failure inside ckdl would produce a truncated document
without an error.

### m5. Empty documents are emitted as the empty string

`emit_kdl($empty_doc)` returns `""` while the upstream suite (and most
emitters) produce `"\n"`. Harmless, but worth a note if byte-for-byte
comparisons matter.

### m6. Unknown options are silently ignored

`parse_kdl($src, bogus => 1)` and `emit_kdl($data, bogus => 1)` accept any
key. A typo such as `emit_comment => 1` (singular) goes unnoticed.

### m7. `version` is case-insensitive for the parser but not for the emitter

`Parser::_build_opt_flags` lower-cases the option (`DETECT` works),
`Emitter::_emit_tree` compares verbatim (`DETECT` croaks). The parser also
accepts `'2'` but not `'v2'`, which the error message spells out; the
emitter's message does not list the accepted values.

### m8. Dead code in `XS.xs`

`ptkx_bless_parser` (`XS.xs:138`) is never called, and the `BOOT` section
creates an unused `opt_stash`. The `typemap` entries for `kdl_parser *` and
`kdl_emitter *` are unused as well (all XSUBs take `SV*` and unpack by
hand).

### m9. `Text::KDL::XS::Value::as_number` is misleading for arbitrary-precision numbers

For `kind => 'string'` values it returns the digit string unchanged, so
`$v->as_number + 1` silently goes through Perl's string-to-number
conversion and loses precision. The POD now says so; a stricter API would
return a `Math::BigInt` / `Math::BigFloat` or refuse.

### m10. `Text::KDL::XS::Parser` cannot be loaded on its own

`use Text::KDL::XS::Parser;` followed by `->new` dies with `Undefined
subroutine &Text::KDL::XS::_OPT_DETECT`, because the option constants live
in the XS bootstrap of `Text::KDL::XS` and `Parser.pm` never loads it.
The same applies to `Text::KDL::XS::Emitter`. The documentation therefore
tells users to `use Text::KDL::XS`, which loads everything.

Suggested fix: add `use Text::KDL::XS ();` (or move the XS loader) so each
module is self-contained.

### m11. Surrogate escapes are accepted in v1 and detect mode

`n "\u{D800}"` parses with `version => '1'` and with the default detection
and yields a Perl string holding a lone surrogate (Perl warns
`Unicode surrogate U+D800 is illegal in UTF-8` when it is printed).
`version => '2'` rejects it, as the 2.0.0 specification requires (only
Unicode scalar values are allowed in `\u{...}`). Upstream ckdl behaviour of
the v1 rules; a check in `ptkx_make_value_sv` could reject it everywhere.

### m12. Detect mode accepts `.5` as an identifier string

`parse_kdl("n .5\n")` (and `-.5`, `+.5`) returns the string `.5`, while
both `version => '1'` and `version => '2'` reject the input as the
specification requires. Upstream ckdl behaviour of the hybrid mode.

### m13. `escape_mode` without `0x20` produces invalid KDL v2

`emit_kdl({ n => "a\nb" }, escape_mode => 0)` writes the newline
literally inside the quotes; `parse_kdl($out, version => '2')` fails
(v1 accepts literal newlines in strings). By design in ckdl, but worth a
guard or at least the documentation note that is now in place.

### m14. No nesting limit

The tree builder is iterative and parses 50 000 nested blocks without
complaint, but `emit_kdl` (`_emit_node_recursive`) and `as_data` recurse
once per level ("Deep recursion" warnings from 100 levels on, and one
indentation unit per level in the output). Untrusted input can therefore
exhaust the stack or memory in the consumer. Suggested fix: an optional
`max_depth` parse option, or at least documentation (now in place).

### m15. `\u{}` with no hex digits is accepted

`n "\u{}"` parses in every mode and yields U+0000; the specification
requires 1 to 6 hex digits. Upstream ckdl behaviour.

---

## Upstream (ckdl) limitations worth knowing

### U1. No source positions in parse errors

`kdl_event_data` carries no line or column. Errors can only be reported by
message (see M1), never by location.

### U2. A children block must be preceded by whitespace, also in v1 mode

The KDL 2.0.0 grammar (tag `2.0.0`, `(node-space+ node-children)?`)
requires whitespace, so rejecting `n{}` in v2 is correct (the later draft
on `main` relaxes this). KDL 1.0.0 allows `node{}`, but ckdl rejects it
with `version => '1'` as well. `n {}` and `n 1 {}` parse in both.

### U3. Detect mode is documented as "almost all" of KDL v1

ckdl's own documentation states that `KDL_DETECT_VERSION` handles every v2
document and *almost* every v1 document. For strict v1 compliance pass
`version => '1'`.

### U4. Emitter always writes `#inf`, `#-inf`, `#nan`

Even with `version => '1'` these keywords are written with the v2 `#`
prefix because v1 has no spelling for them. The resulting document is not
valid KDL v1.

### U5. Vertical tab is treated as whitespace, not as a newline

KDL 2.0.0 lists U+000B in its newline table. ckdl parses `a 1\x0bb 2` as
one node with three arguments (v1 mode rejects the character, as its
specification says).

---

## Verified as correct (no action)

Things that looked suspicious but behave properly, listed so nobody
re-investigates them:

- The upstream KDL test suites (319 documents for 2.0.0, 225 for 1.0.0)
  pass through `parse_kdl` + `emit_kdl`: every `*_fail.kdl` document is
  rejected and every other document re-parses to the same data. The only
  textual differences from the expected output are the spelling of floats
  (`1e10` vs `1.0E+10`; the suite's floats are short enough not to trigger
  C1), `""` vs `"\n"` for empty output (m5), and duplicate properties (m2).
- Slashdash on nodes, arguments, properties and children blocks (without
  `emit_comments`, see C4); nested block comments; line continuations with
  trailing comments; CRLF and BOM handling; multi-line string dedent; raw
  strings with any number of `#`; the escape sequences `\n \r \t \\ \"
  \b \f \s` and `\u{...}` with 1 to 6 digits (but see m11 and m15);
  `0x`/`0o`/`0b` radix prefixes and `_` separators; arbitrary-precision
  integers and out-of-range floats as `kind => 'string'`.
- Number `9223372036854775807` is an integer; `9223372036854775808` and
  `0x8000000000000000` become string-encoded (but see C4 for the
  surprising cases inside the 64-bit range).
- `emit_kdl` correctly quotes node names and strings that contain spaces,
  quotes, `=`, `{`, `\`, or that are empty (`""`), in both versions.
- The parser object can be iterated to EOF and then returns `undef`
  forever; after an error it keeps throwing the same error.
