package Text::KDL::XS::Value;

use strict;
use warnings;

use Carp ();

# A Value is a blessed hashref with these slots:
#   type            : 'null' | 'bool' | 'number' | 'string'
#   kind            : 'integer' | 'float' | 'string'   (only when type=number)
#   value           : underlying scalar (IV/NV/PV) or undef
#   type_annotation : string, optional KDL type tag like "u32"

sub new {
    my ($class, %args) = @_;
    Carp::croak("Text::KDL::XS::Value->new: 'type' is required")
        unless defined $args{type};

    return bless {
        type            => $args{type},
        kind            => $args{kind},
        value           => $args{value},
        type_annotation => $args{type_annotation},
    }, $class;
}

sub type            { $_[0]->{type}            }
sub kind            { $_[0]->{kind}            }
sub type_annotation { $_[0]->{type_annotation} }

sub is_null   { $_[0]->{type} eq 'null'   }
sub is_bool   { $_[0]->{type} eq 'bool'   }
sub is_number { $_[0]->{type} eq 'number' }
sub is_string { $_[0]->{type} eq 'string' }

# Raw underlying scalar (already typed in XS).
sub value { $_[0]->{value} }

# Returns a Perl number suitable for arithmetic when possible.
# Arbitrary-precision integers are still returned as strings; callers
# who need bigint semantics should pass C<as_string> to Math::BigInt.
sub as_number {
    my ($self) = @_;
    return undef if $self->{type} eq 'null';
    return $self->{type} eq 'bool' ? ($self->{value} ? 1 : 0) : $self->{value} + 0
        if $self->{type} ne 'number';
    return $self->{value} if defined $self->{kind} && $self->{kind} ne 'string';
    # string-encoded number - preserve as string-on-the-wire but coerce at use
    return $self->{value};
}

sub as_string {
    my ($self) = @_;
    return undef        if $self->{type} eq 'null';
    return $self->{value} ? 'true' : 'false' if $self->{type} eq 'bool';
    return defined $self->{value} ? "$self->{value}" : undef;
}

# Best-effort native Perl scalar:
#   null    -> undef
#   bool    -> 1/0
#   number  -> IV / NV / string (for arbitrary-precision)
#   string  -> PV
sub as_perl {
    my ($self) = @_;
    my $t = $self->{type};
    return undef           if $t eq 'null';
    return $self->{value} ? 1 : 0 if $t eq 'bool';
    return $self->{value};
}

1;

__END__

=encoding utf-8

=head1 NAME

Text::KDL::XS::Value - A KDL value: null, boolean, number or string, with optional type annotation

=head1 SYNOPSIS

=for highlighter language=Perl

  my $v = $node->args->[0];             # or $node->prop('key')

  $v->type;             # 'null' | 'bool' | 'number' | 'string'
  $v->kind;             # for numbers: 'integer' | 'float' | 'string'; else undef
  $v->type_annotation;  # e.g. 'u32' for (u32)42, else undef

  $v->is_null;  $v->is_bool;  $v->is_number;  $v->is_string;

  $v->value;            # the raw stored scalar
  $v->as_perl;          # undef | 1/0 | number | string  (best native scalar)
  $v->as_string;        # undef | 'true'/'false' | "$number" | string
  $v->as_number;        # undef | 1/0 | number | digit string (kind 'string') | numified string

  # Constructing values for emit_kdl:
  Text::KDL::XS::Value->new(type => 'null');
  Text::KDL::XS::Value->new(type => 'bool',   value => 1);
  Text::KDL::XS::Value->new(type => 'number', kind => 'integer', value => 42);
  Text::KDL::XS::Value->new(type => 'number', kind => 'float',   value => 2.5);
  Text::KDL::XS::Value->new(type => 'number', kind => 'string',  value => '1e400');
  Text::KDL::XS::Value->new(type => 'string', value => 'text', type_annotation => 'date');

=for highlighter

=head1 DESCRIPTION

Every argument and every property value in a KDL document is one of four
types: null, boolean, number or string, optionally preceded by a
C<(type)> annotation. C<Text::KDL::XS::Value> carries exactly that
information, without coercing it, so that a document can be inspected and
written back without loss.

The object is a blessed hash with the keys C<type>, C<kind>, C<value> and
C<type_annotation>. Editing C<< $v->{value} >> in place is supported and
is the simplest way to change a value before re-emitting.

=head1 VALUE MODEL

  KDL source                  type    kind     value (Perl)        as_perl
  --------------------------  ------  -------  ------------------  ----------
  #null (v1: null)            null    undef    undef               undef
  #true (v1: true)            bool    undef    1                   1
  #false (v1: false)          bool    undef    0                   0
  42, 0xFF, 1_000             number  integer  IV 42, 255, 1000    same
  3.14, 1e3                   number  float    NV 3.14, 1000       same
  #inf #-inf #nan             number  float    Inf, -Inf, NaN      same
  4294967295, 1e400,          number  string   the digits as text  the string
    3.141592653589793,
    1180591620717411303424
  "text", bare, #"raw"#       string  undef    character string    same

The kind of a number follows the classification of the underlying ckdl
library, which is stricter than "fits the C type":

  integer   no decimal point or exponent; fits in signed 64 bits; and the
            magnitude is not in 2**31 .. 2**32-1 and not -2**63
  float     decimal point or exponent; at most 15 digits written before
            the exponent (leading and trailing zeros count); written
            exponent within -284 .. 284; also #inf, #-inf and #nan
  string    every other number, as text (underscores removed, radix
            prefixes converted to decimal, leading + dropped, otherwise
            verbatim)

So C<0xFFFFFFFF>, Unix timestamps after 2038 and C<3.141592653589793> all
arrive as C<string>. The text is always exact; see
L</"ARBITRARY PRECISION NUMBERS"> for how to use it. Do not use C<kind> to
judge whether a number is small.

=head1 CONSTRUCTOR

=head2 new

=for highlighter language=Perl

  my $v = Text::KDL::XS::Value->new(type => $type, %fields);

=for highlighter

=over 4

=item type (required)

One of C<'null'>, C<'bool'>, C<'number'>, C<'string'>. Missing dies with
C<Text::KDL::XS::Value-E<gt>new: 'type' is required>. Any other value is
accepted by the constructor but rejected when the value is emitted
(C<emit_arg: unknown value type '...'>).

=item value

The payload: ignored for C<null>; any Perl value for C<bool>, judged by
Perl truthiness (so the string C<'false'> means true); a Perl number or,
for C<< kind => 'string' >>, the number as text for C<number>; a
character string for C<string>.

=item kind

For numbers only: C<'integer'>, C<'float'> or C<'string'>. Always give
one: when it is omitted the emitter writes C<value> verbatim and warns
about an uninitialized value. C<'string'> means "emit C<value> verbatim as
the number's text", which is the way to write arbitrary precision numbers
and the way to write floats with exactly the digits you want (see
L<Text::KDL::XS::Cookbook/"Emitting floating point numbers safely">).
The text is not validated: C<< kind => 'string', value => 'hello' >> is
written as C<hello>, which re-parses as a string, and an unknown C<kind>
is treated like C<'string'>.

=item type_annotation

Optional C<(type)> annotation string.

=back

=head1 METHODS

=head2 type

C<'null'>, C<'bool'>, C<'number'> or C<'string'>.

=head2 kind

For numbers: C<'integer'>, C<'float'> or C<'string'>. C<undef> for the
other types.

=head2 type_annotation

The C<(type)> annotation written before the value, as a string, or
C<undef>.

=head2 is_null, is_bool, is_number, is_string

True when C<type> is the corresponding type.

=head2 value

The stored scalar exactly as the parser produced it (or as passed to
C<new>): C<undef> for null, C<1>/C<0> for booleans, an integer or
floating point number for numbers, the digit string for arbitrary
precision numbers, the text for strings.

=head2 as_perl

The most natural Perl representation:

  null    -> undef
  bool    -> 1 or 0
  number  -> integer / float (or the digit string for kind 'string')
  string  -> the string

This is what L<Text::KDL::XS::Node/as_data> uses.

=head2 as_string

A string form for display or comparison:

  null    -> undef
  bool    -> 'true' or 'false'
  number  -> Perl's stringification of the number ("1000" for 1e3), or the
             verbatim digits for kind 'string'
  string  -> the string

=head2 as_number

A number for arithmetic:

  null    -> undef
  bool    -> 1 or 0
  number  -> the number (kind integer / float)
             the digit string unchanged (kind string; see below)
  string  -> the string numified with + 0 (a non-numeric string gives 0
             and an "isn't numeric" warning)

For arbitrary precision numbers the digit string is returned as is.
Using it in arithmetic converts through a double and loses precision;
pass it to L<Math::BigInt> or L<Math::BigFloat> instead.

=head1 ARBITRARY PRECISION NUMBERS

=for highlighter language=Perl

  use Math::BigInt;
  use Math::BigFloat;

  if ($v->is_number && $v->kind eq 'string') {
      my $exact = $v->value =~ /[.eE]/ ? Math::BigFloat->new($v->value)
                                       : Math::BigInt->new($v->value);
  }

=for highlighter

The stored text is normalised: underscores removed, hexadecimal, octal and
binary literals converted to decimal, a leading C<+> dropped, a C<->
preserved. For decimal literals
with a point or exponent the original spelling is kept (C<1e400>,
C<3.141592653589793>). Values in the 32-bit range mentioned under
L</"VALUE MODEL"> are ordinary integers in text form and can simply be
used as numbers.

=head1 SEE ALSO

L<Text::KDL::XS>, L<Text::KDL::XS::Node>, L<Text::KDL::XS::Cookbook/NUMBERS>.

=head1 AUTHOR

Davenonymous E<lt>perl@davenonymous.comE<gt>

=head1 LICENSE

Copyright (C) 2026 Davenonymous.

This Perl distribution is licensed under the same terms as Perl itself.

=cut
