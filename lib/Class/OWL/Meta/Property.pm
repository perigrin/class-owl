package Class::OWL::Meta::Property;
use Moose;
extends qw(Moose::Meta::Attribute);

has _resource => (   isa => 'Str',   is  => 'ro', );

sub _cardinality {
    $_[0]->{_cardinality} = $_[1] if exists $_[1];
    $_[0]->{_cardinality};
}

sub _domain {
    $_[0]->{_domain} = $_[1] if exists $_[1];
    $_[0]->{_domain};
}

sub _range {
    $_[0]->{_range} = $_[1] if exists $_[1];
    $_[0]->{_range};
}

sub single_valued {
    $_[0]->max_cardinality == 1;
}

sub max_cardinality {
    $_[0]->{_cardinality}->[1];
}

sub min_cardinality {
    $_[0]->{_cardinality}->[0];
}

sub restrict {
    my ( $p, $property_data, $rdf ) = @_;
    $p->{_cardinality} = [ 0, undef ] unless $p->{_cardinality};
    if ( $rdf->exists( $p->{_resource}, 'rdf:type', 'owl:FunctionalProperty' ) )
    {
        $p->{_cardinality} = [ 0, 1 ];
    }
    $p->{_cardinality} = [ 0, $property_data->{'owl:cardinality'} ]
      if $property_data->{'owl:cardinality'};
    $p->{_cardinality} = [
        $property_data->{'owl:minCardinality'},
        $property_data->{'owl:maxCardinality'}
      ]
      if $property_data->{'owl:minCardinality'}
          || $property_data->{'owl:maxCardinality'};

    $p->{_domain} = $property_data->{'rdfs:domain'}
      if $property_data->{'rdfs:domain'};
    $p->{_range} = $property_data->{'rdfs:range'}
      if $property_data->{'rdfs:range'};
}

sub _accessor_info {
    my ( $self, $name ) = @_;

    return {
        $name => sub { my ( $o, $v ) = @_; $o->meta->accessor( $o, $name, $v ) }
    };
}

sub new {
    my ( $class, $resource, $property_data, $rdf ) = @_;

    my $value = undef;
    my $name  = Class::OWL::_get_name($resource);
    die "Malformed resource $resource" unless $name;
    my $p = bless Class::MOP::Attribute->new(
        '$'
          . $name => (
            accessor => $class->_accessor_info($name),
            init_arg => ':' . $name,
            default  => $value,
          )
    ), $class;
    $p->{_resource} = $resource;
    $p->restrict( $property_data, $rdf );

    $p;
}

1;
__END__