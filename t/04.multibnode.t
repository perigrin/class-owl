use Test::More tests=>2;

use_ok('Class::OWL',package=>'OM2','url'=>'http://www.openmetadir.org/om2/prim-3.owl');
my $p1 = OM2::User->meta->new_instance();
my $p2 = OM2::User->meta->new_instance($p1->_model); 

warn $p1->_model->serialize();
warn $p1->_rdf->serialize(format=>'ntriples');
warn "--";
warn $p2->_rdf->serialize(format=>'ntriples');
