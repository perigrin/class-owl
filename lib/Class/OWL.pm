package Class::OWL::MOP;
use base qw(Class::MOP::Class);

sub new_instance {
	my $self = shift;
	my $uri = shift || Class::OWL->get_helper()->new_bnode(); # this may break uniqueness - refactor!
	
	if (ref $_[0] && $_[0]->isa('RDF::Helper'))
	{
		my $rdf = shift;
		die "Inconsistent type"
			unless $rdf->exists($uri,'rdf:type',$self->_type);
	
		Class::OWL->from_rdf($uri,$rdf);
	}
	else
	{
		return Class::OWL->new_instance($self->_type => $uri,@_);
	}
}

package Class::OWL::Property;
use base qw(Class::MOP::Attribute);

sub _resource {
	$_[0]->{_resource};
}

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

use Data::Dumper;

sub restrict {
	my ($p,$property_data,$rdf) = @_;
	$p->{_cardinality} = [0,undef] unless $p->{_cardinality};
	if ($rdf->exists($p->{_resource},'rdf:type','owl:FunctionalProperty'))
	{
		$p->{_cardinality} = [0,1];
	}
	$p->{_cardinality} = [0,$property_data->{'owl:cardinality'}] 
		if $property_data->{'owl:cardinality'};
	$p->{_cardinality} = [$property_data->{'owl:minCardinality'},$property_data->{'owl:maxCardinality'}] 
		if $property_data->{'owl:minCardinality'} || $property_data->{'owl:maxCardinality'};
		
	$p->{_domain} = $property_data->{'rdfs:domain'} 
		if $property_data->{'rdfs:domain'};
	$p->{_range} = $property_data->{'rdfs:range'} 
		if $property_data->{'rdfs:range'};
}

sub new {
	my ( $class, $resource, $property_data, $rdf ) = @_;
	
	my $value = undef;
	my $name = Class::OWL::_get_name($resource);
	die "Malformed resource $resource" unless $name;
	my $p = bless Class::MOP::Attribute->new(
		'$'
		  . $name => (
			accessor => $name,
			init_arg => ':' . $name,
			default  => $value,
		  )
	), $class;
	$p->{_resource} = $resource;
	$p->restrict($property_data,$rdf);
	
	$p;
}

package Class::OWL;

use version; $VERSION = qv('0.0.4');

use warnings;
use strict;
use Carp;

use RDF::Helper;
use Class::MOP;

#use Class::OWL::MOP::Class;
use Class::MOP::Attribute;

use LWP::Simple qw(get);

use XML::CommonNS qw(RDF RDFS OWL);

use Data::Dumper;

my %CONFIG = (
	Namespaces => {
		rdf  => "$RDF",
		rdfs => "$RDFS",
		owl  => "$OWL",
	},
	ExpandQNames => 1,
);

my $DEBUG = 0;
sub debug($) { return unless $DEBUG; print STDERR @_, "\n" }


sub import {
	my $class = shift;
	my %opt   = @_;

	if ( $opt{debug} ) { $DEBUG = 1; }

	if ( $opt{namespaces} ) {
		$CONFIG{Namespaces} =
		  { %{ $CONFIG{Namespaces} }, %{ $opt{namespaces} }, };
	}

	if ( $opt{url} ) {
		$CONFIG{Namespaces}{'#default'} ||= $opt{url};
		$class->parse_url( $opt{package} || __PACKAGE__, $opt{url} );
	}

	if ( $opt{file} ) {
		$class->parse_url( $opt{package} || __PACKAGE__, $opt{file} );
	}
	
	if ( $opt{owl} ) {
		$class->parse_rdfxml($opt{package} || __PACKAGE__,$opt{owl});
	}
}

sub _assert_triple {
	my ($rdf,$subject,$predicate,$object) = @_;
	
	if (ref $object eq 'ARRAY') {
		foreach my $v (@{$object}) {
			_assert_triple($rdf,$subject,$predicate,$v);
		}
	} elsif (ref $object) {
		$rdf->assert_resource( $subject, $predicate,$object->_resource );
		Class::OWL->to_rdf($object,$rdf);
	} else {
		$rdf->assert_literal( $subject, $predicate, $object );
	}
}

sub to_rdf($) {
	my ( $self, $i, $rdf ) = @_;
	$rdf = get_helper() unless $rdf;
	$rdf->assert_resource( $i->_resource, 'rdf:type', $i->meta->_type );
	foreach my $attr ( $i->meta->compute_all_applicable_attributes() ) {
		next if $attr->name eq '$_resource';
		my $value = $attr->get_value($i);
		next unless $value;
		_assert_triple($rdf,$i->_resource,$attr->_resource,$value);
	}
	return $rdf;
}

sub from_rdf($$) {
	my ($self,$subject,$rdf) = @_;
	
	unless (ref $rdf)
	{
		my $xml = $rdf;
		$rdf = $self->get_helper();
		$rdf->include_rdfxml( xml => $xml );
		#print $rdf->serialize( filename => '/tmp/input.n3', format => 'ntriples' );
	}
	
	$subject = $rdf->new_resource($subject) unless ref $subject;
	my $instance_data = $rdf->property_hash($subject);
	my $type = $instance_data->{'rdf:type'};
	my $o = Class::OWL->new_instance($type => $subject);
	my $m = $o->meta;
	
	foreach my $stmt ($rdf->get_statements($subject)) {
		next if $stmt->[1]->as_string eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type';
		my $p = Class::OWL->owl_property($stmt->[1]);
		die "Unknown property type $stmt->[1]" unless $p;
		my $attr = $m->find_attribute_by_name($p->name);
		die "Unknown attribute ".$p->name unless $attr;
		
		my $value;
		if ($stmt->[2]->is_literal)
		{
			$value = $stmt->[2]->literal_value;
		}
		else
		{
			$value = $self->from_rdf($stmt->[2],$rdf);
		}
		
		CASE: {
			$attr->single_valued and do {
				$attr->set_value($o,$value);
			},last CASE;
			
			!$attr->max_cardinality || $attr->max_cardinality > 1 and do {
				my $v = $attr->get_value($o) || [];
				push(@{$v},$value);
				$attr->set_value($o,$v);
			},last CASE;
		}
	}
	
	$o;
}

our %class;
our %attribute;

sub _r_name {
	return $_[0] unless ref $_[0]; 
	$_[0]->is_blank ? $_[0]->blank_identifier : $_[0]->uri->as_string;
}

sub owl_class {
	my $self = shift;
	my $name = _r_name($_[0]);
	die "Malformed resource $_[0] ", caller() unless $name;
	$class{$name} = $_[1] if $_[1];
	return $class{$name};
}

sub owl_property {
	my $self = shift;
	my $name = _r_name($_[0]);
	die "Malformed resource $_[0]", caller() unless $name;
	$attribute{$name} = $_[1] if $_[1];
	return $attribute{$name};
}

sub new_instance {
	my ( $self, $type, $subject, @params ) = @_;
	debug "New instance of $type -> ".$self->owl_class($type);
	my $c = $self->owl_class($type);
	die "No such class $type" unless $c;
	my $o = $c->new_object(@params);
	$o->_resource($subject) if $subject;
	$o;
}

sub get_helper { return RDF::Helper->new(%CONFIG); }

sub _for_type {
	my ( $rdf, $type, $sub) = @_;
	if ( $rdf->exists( undef, undef, $type ) ) {
		for my $s ( $rdf->get_statements(undef, 'rdf:type', $type ) ) {
			$sub->( $s->[0], $rdf->property_hash($s->[0]), $rdf );
		}
	}
}

sub _for_statements {
	my ( $rdf, $subject, $predicate, $sub ) = @_;
	foreach my $stmt ( $rdf->get_statements( $subject, $predicate ) ) {
		$sub->( $rdf, $stmt->[2] );
	}
}

sub parse_url {
	my ( $self, $package, $url ) = @_;
	( my $uri = $url ) =~ s/\.rdf$//;
	my $rdfxml = get($url);
	return $self->parse_rdfxml($package,$rdfxml);
}

sub parse_rdfxml {
	my ( $self, $package, $rdfxml ) = @_;

	my $rdf = $self->get_helper();
	$rdf->include_rdfxml( xml => $rdfxml );
	print $rdf->serialize( filename => '/tmp/model.n3', format => 'ntriples' );
	if ( $rdf->exists( undef, 'rdf:type', 'owl:Class' ) ) {
		_parse_classes($package,$rdf);			
		_parse_properties($package,$rdf);
		_parse_inheritance($package,$rdf);
	}
}

sub _get_name { return ( $_[0] =~ /[#\/]([^#\/]+)$/ )[0] }

sub _parse_properties {
	my ($package,$rdf) = @_;
	_for_type(
		$rdf,
		'http://www.w3.org/2002/07/owl#ObjectProperty',
		sub {
			my ( $resource, $property_data, $rdf ) = @_;
			_create_property( $resource, $property_data, $rdf );
		}
	);
	_for_type(
		$rdf,
		'http://www.w3.org/2002/07/owl#DatatypeProperty',
		sub {
			my ( $resource, $property_data,$rdf ) = @_;
			_create_property( $resource, $property_data, $rdf );
		}
	);
}

sub _create_property {
	my ( $resource, $property_data, $rdf ) = @_;
	
	my $property = Class::OWL::Property->new(_r_name($resource),$property_data,$rdf);
	Class::OWL->owl_property( $resource, $property );
	debug "Created property "
		  . $property->_resource . " as "
		  . $property->name;
	
	my $domain = $property_data->{'rdfs:domain'};
	if ($domain)
	{
		my $domain_class = Class::OWL->owl_class($domain);
		die "No such domain class $domain" unless $domain_class;
		$domain_class->add_attribute($property);
		debug "Added property "
		  . $property->name
		  . " to class "
		  . $domain_class->name;
	}
}

sub _parse_classes {
	my ($package,$rdf) = @_;
	
	# create Thing
	_create_class('Class::OWL',RDF::Helper->new_resource('http://www.w3.org/2002/07/owl#Thing'));
	
	# create All other classes
	_for_type(
		$rdf,
		'http://www.w3.org/2002/07/owl#Class',
		sub {
			my $resource = shift;
			_create_class($package, $resource);
		}
	);
}

sub _package {
	my ($name,$package) = @_;
	return $name ? $package . "::" . $name : $name;
}

sub _class_name {
	my ($resource,$package) = @_;
	my $name = _get_name(_r_name($resource));
	return _package($name,$package);
}

sub _create_class {
	my ( $package, $resource, $name) = @_;
	$name = _class_name($resource,$package) unless $name;
	

	my $class;

	if ($name) {
		$class = Class::OWL::MOP->create($name);
		$class->name($name);
	}
	else {
		$class = Class::OWL::MOP->create_anon_class;
		$name  = $class->name;
	}
	
	debug "Create class from "._r_name($resource)." as $name";
	
	for my $attr ( _create_attribute( '_type' => $resource ) ) {
		$class->meta->add_attribute($attr);
	}

	for my $attr ( _create_attribute( '_resource', $resource ) ) {
		$class->add_attribute($attr);
	}

	$class->add_method('_rdf' => sub {
		Class::OWL->to_rdf($_[0]);
	});

	$class->_type($resource);
	Class::OWL->owl_class($resource,$class);
	
	return $name, $class;
}

sub _create_attribute {
	my ( $name, $value ) = @_;
	if ( ref $value ) {
		$value = sub { $value };
	}
	my %config = ( default => $value, accessor => $name );
	return Class::MOP::Attribute->new( '$' . $name => %config );
}

sub _unwrap_list {
	my ($rdf,$lst,$i) = @_;
	
	foreach my $s ($rdf->get_statements($i,'http://www.w3.org/1999/02/22-rdf-syntax-ns#first'))
	{
		push(@{$lst},$s->[2]);
	}
	
	foreach my $s ($rdf->get_statements($i,'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'))
	{	
		_unwrap_list($rdf,$lst,$s->[2]);
	}
		
	return $lst;
}

sub _parse_inheritance {
	my ($package,$rdf) = @_;
	for my $c ( values %class ) {
		
		_for_statements( $rdf, $c->_type, 'rdfs:subClassOf', sub {
			my ( $rdf, $instance ) = @_;
			return
			  unless $rdf->exists( $instance, 'rdf:type', 'owl:Restriction' )
			  || $rdf->exists( $instance,     'rdf:type', 'owl:Class' );

			my $is_restriction = $rdf->exists( $instance, 'rdf:type', 'owl:Restriction' );
	
			my $class_data = $rdf->property_hash($instance);

			my $class = Class::OWL->owl_class($instance);
			unless ( $class ) {
				my $name = undef;
				if ($is_restriction)
				{
					my $property = $class_data->{'owl:onProperty'};
					my $attr = Class::OWL->owl_property($property);
					$name = "RestrictionOn".ucfirst(substr($attr->name,1))."::"._r_name($instance);
				}
				my ( $actual_name, $aclass ) = _create_class($package,$instance,_package($name,$package));
			}
			$class = Class::OWL->owl_class($instance);
			debug $class->name . " is a superclass of " . $c->name;
			
			if ($is_restriction) {
				# move the attribute from the base domain, restrict it and add it to the restriction
				my $property = $class_data->{'owl:onProperty'};
				my $attr = Class::OWL->owl_property($property);
				debug Dumper($class_data);
				$c->remove_attribute($attr->name) if $c->has_attribute($attr->name);
				$attr->restrict($class_data,$rdf);
				$class->add_attribute($attr);
			}
			
			$c->superclasses( $c->superclasses(), $class->name );
		});

		_for_statements( $rdf, $c->_type, 'owl:unionOf', sub {
			my ($rdf, $instance ) = @_;
			
			my $classes = _unwrap_list($rdf,[],$instance);
			foreach my $resource (@{$classes})
			{
				my $class_data = $rdf->property_hash($resource);
				my $class = Class::OWL->owl_class($resource);
				unless ( $class ) {
					my ( $actual_name, $aclass ) = _create_class($package,$resource);
					Class::OWL->owl_class($resource,$aclass);
				}
				debug $class->name . " is part of the union that is " . $c->name;
				$class->superclasses($class->superclasses(),$c->name);
			}
		});
	}
}

#	  || $rdf->exists( $instance,     'rdf:type', 'owl:unionOf' )
#	  || $rdf->exists( $instance, 	  'rdf:type', 'owl:allValuesFrom')

1;    # Magic true value required at end of module
__END__

=head1 NAME

Class::OWL - [One line description of module's purpose here]


=head1 VERSION

This document describes Class::OWL version 0.0.1


=head1 SYNOPSIS

    #!/usr/bin/perl
	use strict;  
	use lib qw(lib);

	use Class::OWL;
	Class::OWL->parse_url('http://www.w3.org/TR/2004/REC-owl-guide-20040210/wine.rdf');
  
=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE 

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
Class::OWL requires no configuration files or environment variables.


=head1 DEPENDENCIES

Class::MOP, RDF::Helper, LWP::Simple, XML::CommonNS


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-class-owl@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Chris Prather  C<< <cpan@prather.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, Chris Prather C<< <cpan@prather.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
