use strict;
use warnings;

package CMS::Base;

use Web::Simple;

has $_ => ( is => 'ro', lazy => 1, builder => "_build_$_" ) for qw( config soap db session_store );
has $_ => ( is => 'rw' ) for qw( req );

sub _build_session_store { Plack::Session::Store::File->new( dir => File::Spec->tmpdir ) }

1;
