package Text::KDL::XS::Document;

use strict;
use warnings;

use Carp ();
use Text::KDL::XS::Node;
use Text::KDL::XS::Value;

sub new {
    my ($class, %args) = @_;
    return bless { nodes => $args{nodes} // [] }, $class;
}

sub nodes { $_[0]->{nodes} }

# Drive a parser to assemble a full document tree.
# Treats each event as a guarded transition; bails fast on illegal sequences.
sub _build_from_parser {
    my ($class, $parser) = @_;

    my $doc   = $class->new;
    my @stack;            # nodes whose children we're currently filling
    my $current;          # node we're attaching args/props to (top of stack)

    while (defined(my $ev = $parser->next_event)) {
        my $kind = $ev->{event};

        if ($kind eq 'start_node') {
            my $node = Text::KDL::XS::Node->new(
                name            => $ev->{name},
                type_annotation => $ev->{type},
            );
            if ($current) {
                $current->_push_child($node);
            }
            else {
                push @{ $doc->{nodes} }, $node;
            }
            push @stack, $node;
            $current = $node;
            next;
        }

        if ($kind eq 'end_node') {
            Carp::croak("KDL: end_node with empty stack") unless @stack;
            pop @stack;
            $current = $stack[-1];
            next;
        }

        if ($kind eq 'argument') {
            Carp::croak("KDL: argument outside any node") unless $current;
            $current->_push_arg(_value_from_event($ev->{value}));
            next;
        }

        if ($kind eq 'property') {
            Carp::croak("KDL: property outside any node") unless $current;
            $current->_push_prop($ev->{name}, _value_from_event($ev->{value}));
            next;
        }

        # Comments only appear when emit_comments is set; we currently
        # discard them at the tree layer. Streaming users can opt in.
        next if $kind eq 'comment';

        Carp::croak("KDL: unexpected event '$kind'");
    }

    Carp::croak("KDL: input ended with " . scalar(@stack) . " unclosed node(s)")
        if @stack;

    return $doc;
}

sub _value_from_event {
    my ($v) = @_;
    return $v if ref($v) eq 'Text::KDL::XS::Value';
    # XS already blesses; this guard exists only for hand-built events.
    return Text::KDL::XS::Value->new(%$v);
}

sub as_data {
    my ($self) = @_;
    return [ map { $_->as_data } @{ $self->{nodes} } ];
}

1;

__END__

=encoding utf-8

=head1 NAME

Text::KDL::XS::Document - A parsed KDL document: the list of top-level nodes

=head1 SYNOPSIS

=for highlighter language=Perl

  use Text::KDL::XS qw(parse_kdl emit_kdl);

  my $doc = parse_kdl($text);

  for my $node (@{ $doc->nodes }) {          # Text::KDL::XS::Node objects
      print $node->name, "\n";
  }

  my ($server) = grep { $_->name eq 'server' } @{ $doc->nodes };

  my $plain = $doc->as_data;                 # arrayref of plain hashes
  print emit_kdl($doc);                      # back to KDL text

  # Build one by hand from Text::KDL::XS::Node objects:
  my $new = Text::KDL::XS::Document->new(nodes => [ $node, Text::KDL::XS::Node->new(name => 'extra') ]);

=for highlighter

=head1 DESCRIPTION

A C<Text::KDL::XS::Document> is what L<Text::KDL::XS/parse_kdl> returns.
It is a thin container: an ordered list of the document's top-level
L<Text::KDL::XS::Node> objects. Everything else (arguments, properties,
children) hangs off the nodes.

Objects are plain blessed hashes and are meant to be modified in place:
push nodes onto C<< $doc->nodes >>, splice them out, reorder them, then
pass the document to L<Text::KDL::XS/emit_kdl>. (Restructuring the
C<props> of a node has a caveat, see L<Text::KDL::XS::Node/prop>.)

=head1 CONSTRUCTOR

=head2 new

=for highlighter language=Perl

  my $doc = Text::KDL::XS::Document->new;
  my $doc = Text::KDL::XS::Document->new(nodes => \@nodes);

=for highlighter

Creates a document holding the given L<Text::KDL::XS::Node> objects, or an
empty one. The array reference is stored as is, not copied.

=head1 METHODS

=head2 nodes

=for highlighter language=Perl

  my $nodes = $doc->nodes;   # arrayref of Text::KDL::XS::Node, in document order

=for highlighter

The top-level nodes. Always an array reference, empty for an empty
document. It is the document's own array, so modifying it modifies the
document.

=head2 as_data

=for highlighter language=Perl

  my $data = $doc->as_data;  # [ { name => ..., args => [...], ... }, ... ]

=for highlighter

Returns the whole document as plain Perl data: an array reference with one
hash per top-level node, in the shape described in
L<Text::KDL::XS::Node/as_data>. This is convenient for dumping, comparing
in tests, or converting to JSON, but it is lossy: value type annotations,
number kinds, repeated properties and the boolean/number distinction are
not represented. Use the node objects when those matter.

=head1 SEE ALSO

L<Text::KDL::XS>, L<Text::KDL::XS::Node>, L<Text::KDL::XS::Value>.

=head1 AUTHOR

Davenonymous E<lt>perl@davenonymous.comE<gt>

=head1 LICENSE

Copyright (C) 2026 Davenonymous.

This Perl distribution is licensed under the same terms as Perl itself.

=cut
