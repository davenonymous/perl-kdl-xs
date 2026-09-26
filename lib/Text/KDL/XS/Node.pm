package Text::KDL::XS::Node;

use strict;
use warnings;

# A Node is a hashref:
#   name            : string
#   type_annotation : string|undef
#   args            : arrayref of Text::KDL::XS::Value
#   props           : arrayref of [name => Text::KDL::XS::Value]   (ordered)
#   prop_index      : { name => idx_into_props }                   (last-wins)
#   children        : arrayref of Text::KDL::XS::Node
sub new {
    my ($class, %args) = @_;
    return bless {
        name            => $args{name},
        type_annotation => $args{type_annotation},
        args            => $args{args}     // [],
        props           => $args{props}    // [],
        prop_index      => $args{prop_index} // {},
        children        => $args{children} // [],
    }, $class;
}

sub name            { $_[0]->{name}            }
sub type_annotation { $_[0]->{type_annotation} }
sub args            { $_[0]->{args}            }
sub props           { $_[0]->{props}           }
sub children        { $_[0]->{children}        }

sub prop {
    my ($self, $key) = @_;
    my $idx = $self->{prop_index}{$key};
    return undef unless defined $idx;
    return $self->{props}[$idx][1];
}

# Plain Perl view - lossy with respect to property order and per-arg type
# annotations. Documented in POD.
sub as_data {
    my ($self) = @_;
    return {
        name     => $self->{name},
        type     => $self->{type_annotation},
        args     => [ map { $_->as_perl } @{ $self->{args} } ],
        props    => { map { $_->[0] => $_->[1]->as_perl } @{ $self->{props} } },
        children => [ map { $_->as_data } @{ $self->{children} } ],
    };
}

# Internal: append (used by the tree builder)
sub _push_arg {
    my ($self, $value) = @_;
    push @{ $self->{args} }, $value;
}

sub _push_prop {
    my ($self, $key, $value) = @_;
    push @{ $self->{props} }, [ $key, $value ];
    $self->{prop_index}{$key} = $#{ $self->{props} };
}

sub _push_child {
    my ($self, $child) = @_;
    push @{ $self->{children} }, $child;
}

1;

__END__

=encoding utf-8

=head1 NAME

Text::KDL::XS::Node - A KDL node: name, type annotation, arguments, properties, children

=head1 SYNOPSIS

=for highlighter language=Perl

  # From a parsed document:
  my $node = $doc->nodes->[0];

  $node->name;                    # 'server'
  $node->type_annotation;         # 'primary' for (primary)server, else undef
  $node->args;                    # [ Text::KDL::XS::Value, ... ]
  $node->props;                   # [ [ 'port', Text::KDL::XS::Value ], ... ]
  $node->prop('port');            # Text::KDL::XS::Value or undef
  $node->children;                # [ Text::KDL::XS::Node, ... ]
  $node->as_data;                 # plain hash, see below

  # Built by hand:
  my $node = Text::KDL::XS::Node->new(
      name            => 'server',
      type_annotation => 'primary',                       # optional
      args            => [ Text::KDL::XS::Value->new(type => 'string', value => 'web-1') ],
      props           => [ [ port => Text::KDL::XS::Value->new(type => 'number', kind => 'integer', value => 8080) ] ],
      children        => [ Text::KDL::XS::Node->new(name => 'tls') ],
  );

=for highlighter

=head1 DESCRIPTION

Each KDL node

=for highlighter language=KDL

  (type)name arg1 arg2 key=value {
      child
  }

=for highlighter

is represented by one C<Text::KDL::XS::Node>. The object is a blessed hash
whose contents you may read and modify directly; the accessors below are
the supported way to do so, but pushing onto C<< @{ $node->args } >> or
assigning to C<< $node->{name} >> works and is used in the examples of
L<Text::KDL::XS::Cookbook>.

=head1 CONSTRUCTOR

=head2 new

=for highlighter language=Perl

  my $node = Text::KDL::XS::Node->new(name => $name, %fields);

=for highlighter

Fields (all optional except C<name>):

=over 4

=item name

The node name, a string. Any string is allowed; it is quoted on output if
necessary.

=item type_annotation

The node's C<(type)> annotation as a string, or C<undef> (the default) for
none.

=item args

Array reference of argument values, in order. Elements are normally
L<Text::KDL::XS::Value> objects. Plain scalars, C<undef> and boolean
objects are accepted as well and are coerced by
L<Text::KDL::XS/emit_kdl> when the node is emitted (see
L<Text::KDL::XS/"Scalar coercion">); note that C<as_data> and the C<Value>
methods are then not available for those elements.

=item props

Array reference of C<[ $key, $value ]> pairs, in order. The same rules for
C<$value> apply as for C<args>.

=item children

Array reference of child C<Text::KDL::XS::Node> objects.

=back

The array references are stored, not copied.

B<Limitation:> L</prop> works through an index that only the parser
builds. For a node created with C<new>, C<prop> returns C<undef> for every
key; the node still emits correctly. Iterate C<props> instead.

=head1 METHODS

=head2 name

The node name as a character string. Never C<undef> for a parsed node.

=head2 type_annotation

The C<(type)> written before the node name, or C<undef> if there is none.

=head2 args

Array reference of the node's arguments as L<Text::KDL::XS::Value>
objects, in document order. Empty array reference when there are none.

=for highlighter language=Perl

  my @strings = map { $_->as_string } @{ $node->args };
  my $first   = $node->args->[0];      # undef if there are no arguments

=for highlighter

=head2 props

Array reference of C<[ $key, $value ]> pairs in document order, one pair
per property as written, including repeated keys. C<$value> is a
L<Text::KDL::XS::Value>.

=for highlighter language=Perl

  for my $pair (@{ $node->props }) {
      my ($key, $value) = @$pair;
      ...
  }

=for highlighter

=head2 prop

=for highlighter language=Perl

  my $value = $node->prop($key);   # Text::KDL::XS::Value, or undef if absent

=for highlighter

Looks up a property by key. When the key appears more than once the last
occurrence is returned, as the KDL specification requires. Returns C<undef>
for a missing key; a property whose value is C<#null> returns a C<Value>
object with C<is_null> true, so the two cases can be told apart.

The lookup uses an index built by the parser and not updated afterwards.
Changing the C<value> of a property object is fine, but after adding,
removing or reordering entries of the C<props> array the index is stale: C<prop>
then returns old values or the value of a neighbouring key. Read
restructured properties by iterating C<props>. Hand-built nodes have no
index at all, see L</new>.

=head2 children

Array reference of child nodes, in document order. Empty when the node has
no children block (or an empty one).

=head2 as_data

=for highlighter language=Perl

  my $data = $node->as_data;

=for highlighter

Returns the node and its subtree as plain Perl data:

=for highlighter language=Perl

  {
      name     => $string,
      type     => $string_or_undef,             # node type annotation
      args     => [ $scalar, ... ],             # Value->as_perl for each argument
      props    => { $key => $scalar, ... },     # last value wins for repeated keys
      children => [ \%child, ... ],             # same shape, recursively
  }

=for highlighter

Values are converted with L<Text::KDL::XS::Value/as_perl>: C<undef> for
null, C<1>/C<0> for booleans, numbers as numbers (or digit strings for
arbitrary precision values), strings as strings. Type annotations on values
and the number kind are dropped.

=head1 INTERNAL METHODS

C<_push_arg>, C<_push_prop> and C<_push_child> are used by the tree
builder and may change without notice.

=head1 SEE ALSO

L<Text::KDL::XS>, L<Text::KDL::XS::Value>, L<Text::KDL::XS::Document>,
L<Text::KDL::XS::Cookbook/"Building nodes and values by hand">.

=head1 AUTHOR

Davenonymous E<lt>perl@davenonymous.comE<gt>

=head1 LICENSE

Copyright (C) 2026 Davenonymous.

This Perl distribution is licensed under the same terms as Perl itself.

=cut
