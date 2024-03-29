#!perl

# Astro::Catalog test harness
use Test::More tests => 8;

use strict;

use File::Temp qw/tempfile/;

# load modules
require_ok("Astro::Catalog");

# In this test, we want to read from the DATA handle, write the
# catalog to disk, read it in again and then make sure that we
# have the correct number of stars. This guarantees that our
# reader can read something generated by the writer

my $tempfile = File::Temp->new();

# Read catalog from Simple File from the DATA handle

my $cat = new Astro::Catalog(Format => 'Simple', Data => \*DATA);

isa_ok($cat, "Astro::Catalog");

# Count the number of stars
is($cat->sizeof, 5, "Confirm initial star count");

# Write it to disk

ok($cat->write_catalog(Format => 'Simple', File => $tempfile),
    "Check catalog write");

# Read it back in using filehandle
seek($tempfile, 0, 0);
my $newcat = new Astro::Catalog(Format => 'Simple', Data => $tempfile);

isa_ok($newcat, "Astro::Catalog");

# Count the number of stars
is($newcat->sizeof, 5, "Confirm star count");


# Read it back in (forcing the file name to be used)
$newcat = new Astro::Catalog(Format => 'Simple', File => "$tempfile");

isa_ok($newcat, "Astro::Catalog");

# Count the number of stars
is($newcat->sizeof, 5, "Confirm star count");

exit;

__DATA__
# Catalog written automatically by class Astro::Catalog::IO::Simple
# on date Sun Jul 27 03:37:59 2003UT
# Origin of catalog: <UNKNOWN>
A  09 55 39.00  +60 07 23.60 B1950 # This is a comment
B  10 44 57.00  +12 34 53.50 J2000 # This is another comment
C  12:33:52    + 12:28:30
D  12 33 52.0   +12 28 30.0  # A comment without epoch
E  12 33 52    - 12 28 30.0  AZEL
