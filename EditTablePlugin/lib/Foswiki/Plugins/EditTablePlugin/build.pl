#!/usr/bin/perl -w
#
# Build for EditTablePlugin
#
use strict;

BEGIN {
    foreach my $pc ( split( /:/, $ENV{FOSWIKI_LIBS} ) ) {
        unshift @INC, $pc;
    }
}

use Foswiki::Contrib::Build;

# Create the build object
$build = new Foswiki::Contrib::Build('EditTablePlugin');

# Build the target on the command line, or the default target
$build->build( $build->{target} );

