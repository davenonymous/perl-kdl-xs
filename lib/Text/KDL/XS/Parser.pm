package Text::KDL::XS::Parser;

use strict;
use warnings;

use Scalar::Util ();
use Carp ();

# Constructor:
#   Text::KDL::XS::Parser->new($source, %opts)
#     $source : string | filehandle | coderef returning chunks
#     %opts   : version       => 'detect'|'1'|'2'   (default: detect)
#               emit_comments => 0|1                (default: 0)
sub new {
    my ($class, $source, %opts) = @_;

    Carp::croak("Text::KDL::XS::Parser: source is required")
        unless defined $source;

    my $opts_int = _build_opt_flags(\%opts);

    if (my $reftype = ref $source) {
        return $class->_new_stream_parser($source, $opts_int)
            if $reftype eq 'CODE';

        my $reader = _make_io_reader($source);
        return $class->_new_stream_parser($reader, $opts_int)
            if $reader;

        Carp::croak("Text::KDL::XS::Parser: unsupported source ref type '$reftype'");
    }

    return $class->_new_string_parser($source, $opts_int);
}

# Returns the next event hashref, or undef at EOF. Dies on parse error.
sub next_event {
    my ($self) = @_;
    return $self->_next_event;
}

# --- internals -------------------------------------------------------------

sub _build_opt_flags {
    my ($opts) = @_;

    my $version = lc($opts->{version} // 'detect');
    my $flags
        = $version eq 'detect' ? Text::KDL::XS::_OPT_DETECT()
        : $version eq '1'      ? Text::KDL::XS::_OPT_V1()
        : $version eq '2'      ? Text::KDL::XS::_OPT_V2()
        : Carp::croak("unknown version '$version' (expected 'detect', '1', or '2')");

    $flags |= Text::KDL::XS::_OPT_EMIT_COMMENTS() if $opts->{emit_comments};
    return $flags;
}

# Wrap a filehandle / IO object as a Perl sub the XS layer can call.
sub _make_io_reader {
    my ($source) = @_;

    my $reftype = Scalar::Util::reftype($source) // '';
    return undef unless $reftype eq 'GLOB' || Scalar::Util::blessed($source);

    # Duck-type: must support sysread or read.
    my $can_sysread = $reftype eq 'GLOB' || (Scalar::Util::blessed($source)
        && ($source->can('sysread') || $source->can('read')));
    return undef unless $can_sysread;

    return sub {
        my ($want) = @_;
        my $buf = '';
        my $n;
        if ($reftype eq 'GLOB') {
            $n = sysread($source, $buf, $want);
        }
        elsif ($source->can('sysread')) {
            $n = $source->sysread($buf, $want);
        }
        else {
            $n = $source->read($buf, $want);
        }
        return defined $n && $n > 0 ? $buf : '';
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

Text::KDL::XS::Parser - Streaming, event-based KDL parser

=head1 SYNOPSIS

=for highlighter language=Perl

  use Text::KDL::XS;   # also loads Text::KDL::XS::Parser

  open my $fh, '<:raw', 'big.kdl' or die $!;
  my $parser = Text::KDL::XS::Parser->new($fh, version => 'detect');

  while (my $ev = $parser->next_event) {
      if ($ev->{event} eq 'start_node') {
          print "node ", $ev->{name}, "\n";
      }
      elsif ($ev->{event} eq 'argument') {
          print "  arg ", $ev->{value}->as_string // '#null', "\n";
      }
      elsif ($ev->{event} eq 'property') {
          print "  $ev->{name} = ", $ev->{value}->as_string // '#null', "\n";
      }
  }
  # next_event returned undef: end of input

=for highlighter

=head1 DESCRIPTION

C<Text::KDL::XS::Parser> exposes ckdl's event stream directly. Instead of
building a tree, it hands you one event at a time: a node starts, an
argument or property was read, a node ends. With a filehandle or code
reference source the input is consumed in chunks, so memory use does not
grow with the document (a string source is copied once in full), and you
can stop reading at any point.

L<Text::KDL::XS/parse_kdl> is built on this class; use it unless you need
streaming, early termination, or access to comments and slashdashed
elements.

=head1 CONSTRUCTOR

=head2 new

=for highlighter language=Perl

  my $parser = Text::KDL::XS::Parser->new($source);
  my $parser = Text::KDL::XS::Parser->new($source, version => '2', emit_comments => 1);

=for highlighter

Creates a parser over C<$source>, which must be one of the following.

=over 4

=item String

The whole document as UTF-8 bytes. The parser keeps a copy, so the caller
may discard or modify the original afterwards.

=item Filehandle or IO object

A glob reference (C<\*STDIN>, not the bare C<*STDIN>) or an object that
implements C<sysread> (preferred) or C<read>. A glob is read with Perl's
C<sysread>, an object with its C<sysread> method or, failing that, its
C<read> method, in chunks whose size ckdl chooses. It must be a raw handle
backed by a real file descriptor: no C<:encoding(...)> or C<:utf8> layer,
no in-memory handle, and no prior buffered reads on it. See
L<Text::KDL::XS/"FILEHANDLE SOURCES">.

=item Code reference

Called as C<< $code->($wanted_bytes) >> whenever the parser needs more
input. Return a byte string with the next chunk, or an empty string or
C<undef> at end of input. The chunk must be at most C<$wanted_bytes> long
(at most 4096, varying per call): anything beyond that is discarded
without an error and
nodes silently disappear. Chunk boundaries need not align with lines or
tokens. An exception thrown inside the callback is swallowed and treated
as end of input.

=back

C<undef> dies with C<Text::KDL::XS::Parser: source is required>; any other
reference type dies with C<Text::KDL::XS::Parser: unsupported source ref
type '...'>.

Options:

=over 4

=item version => 'detect' | '1' | '2'

Which KDL version to accept; case-insensitive; default C<'detect'>. See
L<Text::KDL::XS/"KDL VERSIONS">.

=item emit_comments => 0 | 1

When true, comments produce C<comment> events, and nodes, arguments and
properties that were commented out with a slashdash (C</->) are reported
with C<< commented => 1 >> instead of being dropped. Default false.

=back

=head1 METHODS

=head2 next_event

=for highlighter language=Perl

  my $ev = $parser->next_event;   # hashref, or undef at end of input

=for highlighter

Returns the next event as a hash reference, or C<undef> once the document
has been consumed. Calling it again after C<undef> keeps returning
C<undef>. Dies with C<KDL parse error> on malformed input; after an error
every further call dies again.

=head1 EVENT HASH

Each event is a hash reference with these keys:

  key        present for                  value
  ---------  ---------------------------  ----------------------------------------
  event      always                       'start_node' | 'end_node' | 'argument'
                                          | 'property' | 'comment'
  commented  always                       1 if the element was slashdashed (/-),
                                          otherwise 0 (see below)
  name       start_node, property         node name / property key (character string)
  type       start_node, when annotated   the node's type annotation
  value      argument, property           a Text::KDL::XS::Value

Notes:

=over 4

=item * C<commented> is only ever 1 when the parser was created with
C<< emit_comments => 1 >>; without that option slashdashed elements are
not reported at all. A slashdashed node reports all of its arguments,
properties, children and its C<end_node> with C<< commented => 1 >>.

=item * C<comment> events (only with C<emit_comments>) mark the position of
C<//> and C</* */> comments. They have C<< commented => 1 >> and no other
keys. The comment text itself is not available in this release.

=item * Type annotations on argument and property values are on the
L<Text::KDL::XS::Value> object (C<< $ev->{value}->type_annotation >>), not
in the event hash.

=item * Every C<start_node> is eventually matched by exactly one
C<end_node>, unless a parse error intervenes. Arguments and properties of a
node arrive between its C<start_node> and the C<start_node> of its first
child (or its own C<end_node>).

=back

=head1 EXAMPLES

=head2 Event sequence for a small document

=for highlighter language=KDL

  node 1 key=2 {
      child 3
  }

=for highlighter

produces, in order:

  start_node  name=node
  argument    value=1
  property    name=key value=2
  start_node  name=child
  argument    value=3
  end_node
  end_node

=head2 Seeing slashdashed elements and comments

=for highlighter language=Perl

  my $p = Text::KDL::XS::Parser->new("// note\nnode 1 /-2 {\n  /-gone\n}\n", emit_comments => 1);
  while (my $ev = $p->next_event) {
      printf "%-10s commented=%d %s\n", $ev->{event}, $ev->{commented}, $ev->{name} // '';
  }

=for highlighter

  comment    commented=1
  start_node commented=0 node
  argument   commented=0
  argument   commented=1
  start_node commented=1 gone
  end_node   commented=1
  end_node   commented=0

=head2 Stopping early

Because events are pulled on demand, you can stop as soon as you have what
you need. Here we find the first top-level C<version> node and stop:

=for highlighter language=Perl

  my $p = Text::KDL::XS::Parser->new($big_document);
  my ($depth, $version) = (0);
  while (my $ev = $p->next_event) {
      if ($ev->{event} eq 'start_node') {
          if ($depth == 0 && $ev->{name} eq 'version') {
              my $next = $p->next_event;                    # the next event: usually its first argument
              $version = $next->{value}->as_string if $next && $next->{event} eq 'argument';
              last;
          }
          $depth++;
      }
      elsif ($ev->{event} eq 'end_node') { $depth-- }
  }

=for highlighter

=head2 Building your own structure

The tree builder in L<Text::KDL::XS::Document> is a short loop over these
events and is a good template for custom builders: keep a stack of open
nodes, push on C<start_node>, pop on C<end_node>, attach values to the top
of the stack.

=head1 SEE ALSO

L<Text::KDL::XS>, L<Text::KDL::XS::Value>,
L<Text::KDL::XS::Cookbook/"Stream a large file without building a tree">.

=head1 AUTHOR

Davenonymous E<lt>perl@davenonymous.comE<gt>

=head1 LICENSE

Copyright (C) 2026 Davenonymous.

This Perl distribution is licensed under the same terms as Perl itself.

=cut
