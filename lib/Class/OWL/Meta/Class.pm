package Class::OWL::Meta::Class;
use Moose;
extends qw(Moose::Meta::Class);

sub from_rdf {
	my ($self,$uri,$rdf) = @_;
	
	die "Inconsistent type"
			unless $rdf->exists($uri,'rdf:type',$self->_type);
	
	Class::OWL->from_rdf($uri,$rdf);
}

sub new_instance {
	my $self = shift;
	my ($uri,$rdf);
	
	# (uri,rdf)
	# (uri)
	# (rdf)
	# (rdf,uri)  
	
	$uri = shift unless ref $_[0];
	$rdf = shift if ref $_[0] && $_[0]->isa("RDF::Helper");
	$uri = shift unless $uri;
	
	$rdf = Class::OWL->new_model() unless $rdf;
	$uri = $rdf->new_bnode() unless $uri;
	return Class::OWL->new_instance($rdf,$self->_type => $uri,@_);
}

sub accessor {
	my ($mop,$o,$a,$v) = @_;
	
	my $attr = $mop->find_attribute_by_name('$'.$a);
	
	unless ($attr) {
		warn caller();
		die "No such attribute $a on $o";
	}
	
	if (defined $v) {
		if ($v) {
			$attr->set_value($o,$v);
		} else {
			$attr->clear_value($o);
		}
	}
	$v = $attr->get_value($o);
	
	return undef unless defined $v;
	
	if (wantarray) {
		return ref $v eq 'ARRAY' ? @$v : ($v);
	} else {
		return ref $v eq 'ARRAY' ? $v->[0] : $v;
	}
}

1;
__END__