#!perl
# Astro::Catalog::Query::SkyCat with usnoa2 test harness

# strict
use strict;

#load test
use Test::More tests => 351;
use Data::Dumper;

BEGIN {
  # load modules
  use_ok("Astro::Catalog::Star");
  use_ok("Astro::Catalog");
  use_ok("Astro::Catalog::Query::SkyCat");
}

# Load the generic test code
my $p = ( -d "t" ?  "t/" : "");
do $p."helper.pl" or die "Error reading test functions: $!";




# T E S T   H A R N E S S --------------------------------------------------

# Grab USNO-A2 sample from the DATA block
# ---------------------------------------
my @buffer = <DATA>;
chomp @buffer;

# test catalog
my $catalog_data = new Astro::Catalog();

# create a temporary object to hold stars
my $star;

# Parse data block
# ----------------
foreach my $line ( 0 .. $#buffer ) {

   # split each line
   my @separated = split( /\s+/, $buffer[$line] );

   # check that there is something on the line
   if ( defined $separated[0] ) {

       # create a temporary place holder object
       $star = new Astro::Catalog::Star();

       # ID
       my $id = $separated[2];
       $star->id( $id );
       #print "# ID $id star $line\n";

       # RA
       my $objra = "$separated[3] $separated[4] $separated[5]";

       # Dec
       my $objdec = "$separated[6] $separated[7] $separated[8]";

       $star->coords( new Astro::Coords( name => $id,
                                         ra => $objra,
                                         dec => $objdec,
                                         units => 'sex',
                                         type => 'J2000',
                                       ));

       # R Magnitude
       my %r_mag = ( R => $separated[9] );
       $star->magnitudes( \%r_mag );

       # B Magnitude
       my %b_mag = ( B => $separated[10] );
       $star->magnitudes( \%b_mag );

       # Quality
       my $quality = $separated[11];
       $star->quality( $quality );

       # Field
       my $field = $separated[12];
       $star->field( $field );

       # GSC
       my $gsc = $separated[13];
       if ( $gsc eq "+" ) {
          $star->gsc( "TRUE" );
       } else {
          $star->gsc( "FALSE" );
       }

       # Distance
       my $distance = $separated[14];
       $star->distance( $distance );

       # Position Angle
       my $pos_angle = $separated[15];
       $star->posangle( $pos_angle );

    }

    # Push the star into the catalog
    # ------------------------------
    $catalog_data->pushstar( $star );

    # Calculate error
    # ---------------

    my ( $power, $delta_r, $delta_b );

    # delta.R
    $power = 0.8*( $star->get_magnitude( 'R' ) - 19.0 );
    $delta_r = 0.15* (( 1.0 + ( 10.0 ** $power ) ) ** (1.0/2.0));

    # delta.B
    $power = 0.8*( $star->get_magnitude( 'B' ) - 19.0 );
    $delta_b = 0.15* (( 1.0 + ( 10.0 ** $power ) ) ** (1.0/2.0));

    # mag errors
    my %mag_errors = ( B => $delta_b,  R => $delta_r );
    $star->magerr( \%mag_errors );

    # calcuate B-R colour and error
    # -----------------------------

    my $b_minus_r = $star->get_magnitude( 'B' ) -
                    $star->get_magnitude( 'R' );

    my %colours = ( 'B-R' => $b_minus_r );
    $star->colours( \%colours );

    # delta.(B-R)
    my $delta_bmr = ( ( $delta_r ** 2.0 ) + ( $delta_b ** 2.0 ) ) ** (1.0/2.0);

    # col errors
    my %col_errors = ( 'B-R' => $delta_bmr );
    $star->colerr( \%col_errors );

}

# field centre
$catalog_data->fieldcentre( RA => '01 10 12.9', Dec => '+60 04 35.9', Radius => '1' );


# Grab comparison from ESO/ST-ECF Archive Site
# --------------------------------------------

my $usno_byname = new Astro::Catalog::Query::SkyCat( #Target => 'HT Cas',
                                                    Catalog => 'usno',
                                                    RA => '01 10 12.9',
                                                    Dec => '+60 04 35.9',
                                                    Radius => '1' );

print "# Connecting to ESO/ST-ECF USNO-A2 Catalogue\n";
my $catalog_byname = $usno_byname->querydb();
print "# Continuing tests\n";

# C O M P A R I S O N ------------------------------------------------------

# check sizes
print "# DAT has " . $catalog_data->sizeof() . " stars\n";
print "# NET has " . $catalog_byname->sizeof() . " stars\n";

$catalog_byname->sort_catalog( 'ra' );

# Now compare the stars in the catalogues in order
#-------------------------------------------------
compare_catalog( $catalog_byname, $catalog_data);

exit;


# D A T A   B L O C K  -----------------------------------------------------
# nr ID              ra           dec        r_mag b_mag  q field gsc    d'     pa
__DATA__
   1 U1500_01193693  01 10 08.76 60 05 10.2  16.2  18.8   0 00080  -   0.770 317.921
   2 U1500_01194083  01 10 10.31 60 04 42.4  18.2  19.6   0 00080  -   0.341 288.524
   3 U1500_01194433  01 10 11.62 60 04 49.8  17.5  18.8   0 00080  -   0.281 325.435
   4 U1500_01194688  01 10 12.60 60 04 14.3  13.4  14.6   0 00080  -   0.362 185.885
   5 U1500_01194713  01 10 12.67 60 04 26.8  17.6  18.2   0 00080  -   0.154 190.684
   6 U1500_01194715  01 10 12.68 60 04 43.0  17.8  18.9   0 00080  -   0.122 346.850
   7 U1500_01194794  01 10 12.95 60 04 36.2  16.1  16.4   0 00080  -   0.009  50.761
   8 U1500_01195060  01 10 13.89 60 05 28.7  18.1  19.1   0 00080  -   0.889   7.975
   9 U1500_01195140  01 10 14.23 60 05 25.5  16.5  17.9   0 00080  -   0.843  11.328
  10 U1500_01195144  01 10 14.26 60 04 38.1  18.4  19.5   0 00080  -   0.173  77.596
  11 U1500_01195301  01 10 14.83 60 04 19.1  14.2  16.8   0 00080  -   0.370 139.435
  12 U1500_01195521  01 10 15.71 60 04 43.8  18.7  19.6   0 00080  -   0.374  69.469
  13 U1500_01195912  01 10 17.30 60 05 22.1  14.1  16.9   0 00080  -   0.944  35.466
  14 U1500_01196088  01 10 18.00 60 04 37.1  15.1  17.7   0 00080  -   0.636  88.143
  15 U1500_01196555  01 10 20.00 60 04 12.3  18.2  19.1   0 00080  -   0.969 113.908
