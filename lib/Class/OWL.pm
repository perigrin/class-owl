package Class::OWL;

use version; $VERSION = qv('0.0.1');

use warnings;
use strict;
use Carp;

use YAML::Syck;

use RDF::Helper;

use Class::MOP;
use Class::MOP::Class;
use Class::MOP::Attribute;

use LWP::Simple qw(get);

use XML::CommonNS qw(RDF RDFS OWL DC);
my $FOAF = XML::NamespaceFactory->new("http://xmlns.com/foaf/0.1/");

my %CONFIG = (
    BaseInterface => 'RDF::Redland',
    Namespaces    => {
        rdf  => "$RDF",
        rdfs => "$RDFS",
        owl  => "$OWL",
        foaf => "$FOAF",
    },
    ExpandQNames => 1,
);

my $DEBUG = 0;

our %class;

sub import {
	my $class = shift;
	my %opt = @_;
	if ($opt{url}) {
		$class->parse_url($opt{url});
	} 
	elsif ($opt{file}) {
		$class->parse_url($opt{url});
	}
}

sub debug($) { return unless $DEBUG; print STDERR @_, "\n" }

sub _get_helper { return RDF::Helper->new(%CONFIG); }

sub _parse_resource { 
	my ($rdf, $object, $sub) = @_;
	if ( $rdf->exists(undef, undef, $object) ) {
		for my $resource ($rdf->resourcelist( 'rdf:type', $object )) {
			$sub->($resource, $rdf->property_hash($resource))
		}
	}
}


sub parse_url {
    my ( $self, $url ) = @_;
    ( my $uri = $url ) =~ s/\.rdf$//;
    my $rdfxml = get($url);
	$CONFIG{'Namespaces'}->{'#default'} = $url;
    return $self->parse_rdfxml($rdfxml);
}

sub parse_rdfxml {
	my ($self, $rdfxml) = @_;
	debug $rdfxml;
	my $rdf = $self->_get_helper();
	$rdf->include_rdfxml( xml => $rdfxml );
	if ( $rdf->exists(undef, 'rdf:type', 'owl:Class') ) {
		debug 'Found ' . $rdf->count(undef, 'rdf:type','owl:Class') . ' owl:Class objects in document';		
		_parse_classes($rdf);
		_parse_inheritance($rdf);  	
    }
	debug Dump \%class;
	#	print $rdf->serialize(format => 'rdfxml-abbrev');
}

sub _get_name { return ($_[0] =~ /#(\w+)$/)[0]; }

sub _parse_classes {
	my ($rdf) = @_;
	_parse_resource($rdf, 'owl:Class', sub {		
		my ($resource, $class_data) = @_;
		debug "parsing: $resource";
		# Do Class::MOP/Moose Magic
		my ($name, $class) = _create_class($resource, $class_data);
		$class{ $name } = $class;	
	});
}

sub _create_class { 
	my ($resource, $class_data) = @_;
	my $name = _get_name($resource);			
	my $class;
	if ($name) { 
		$class = Class::MOP::Class->create($name); 
	} else {
		$class = Class::MOP::Class->create_anon_class;
		$name = ref $class;
	}
	
	#XXX This is obviously wrong, 
	# the right answer is to subclass Class::MOP::Class to not make ->meta immutable.
	$class->{name} = $name;
	$class->{resource} = $resource;
	
	for (keys %$class_data) {	
		my $attr = Class::MOP::Attribute->new('$'.$_ => ( default => sub { $class_data->{$_} } ) );	
		$class->add_attribute($attr);
	}
			
	return $name, $class;
}

sub _parse_inheritance { 
	my ($rdf) = @_;
	for my $c (values %class) {
		_parse_resource($rdf, $c->{resource}, sub {
				my ($instance, $class_data) = @_;
				my $name = _get_name($instance);
				unless (exists $class{$name}) { 
					my ($name, $class) = _create_class($instance, $class_data);
					$class{$name} = $class;
				}
				my $i =  $class{$name};
				debug "$i->{name} is an instance of $c->{name}";				
				$i->superclasses( $i->superclasses, $c );
		})				
	}	
}

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

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


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
