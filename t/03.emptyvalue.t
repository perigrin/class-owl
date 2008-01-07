use Test::More tests=>2;

use_ok('Class::OWL',package=>'OM2','url'=>'http://www.openmetadir.org/om2/om2-1.owl');
my $m1 = OM2::Message->meta->new_instance('http://www.su.se/om2#dummy1',mid=>22);
$m1->mid(undef);

warn $m1->_rdf->serialize();
