#!perl

# Make sure we can read a JCMT format catalog. In this case
# it is the pointing catalog.

# Author: Tim Jenness (tjenness@cpan.org)
# Copyright (C) 2003-2005 Particle Physics and Astronomy Research Council

use strict;
use warnings;
use Test::More tests => (16  # general tests
    + (365  # unique sources in catalog
        + 7)  # planets
            * 6  # tests per source
);

require_ok('Astro::Catalog::Item');
require_ok('Astro::Catalog');

# Create a new catalog from the DATA handle
my $cat = new Astro::Catalog(Format => 'JCMT', Data => \*DATA);

isa_ok($cat, "Astro::Catalog");

my $total = 374 + 7;
is($cat->sizeof, $total, "count number of sources [inc planets]");

# check that we are using Astro::Coords and Astro::Catalog::Item

isa_ok($cat->allstars->[0], "Astro::Catalog::Item");
isa_ok($cat->allstars->[0]->coords, "Astro::Coords");

# The remaining tests actually test the catalog filtering
# search by substring
my @results = $cat->filter_by_id("3C");
is(scalar(@results), 5, "search by ID - \"3C\"");

for (@results) {
    print "# Name: " . $_->id . "\n";
}

# search by radius
my $refcoords = new Astro::Coords(
        ra => "23:14:00",
        dec => "61:27:00",
        type => "J2000");

# 10 arcmin
$cat->reset_list;
my $limit = Astro::Coords::Angle->new(10.0, units => "arcmin");
@results = $cat->filter_by_distance($limit->radians, $refcoords);
is(scalar(@results), 2, "search by radius");

# search for string
@results = $cat->filter_by_id(qr/^N7538IRS1$/i);
is(scalar(@results), 1, "search by full name");

# Check a specific velocity
$cat->reset_list;
my ($gl) = $cat->popstarbyid("GL490");
is($gl->coords->rv(), -12.5,"GL490 velocity");

# Check to see if line velocity range is defined.
my $misc = $gl->misc;
ok(! defined($misc->{'velocity_range'}), "GL490 line velocity range");

# Retrieve an object whose velocity range is defined.
$cat->reset_list;
my ($gl2477) = $cat->popstarbyid("GL2477");

is($gl2477->misc->{'velocity_range'}, '48.0', "GL2477 line velocity range");

# search for coords
$cat->reset_list;
@results = $cat->filter_by_cb(sub {substr($_[0]->ra,0,8) eq "02 22 39"});
is(scalar(@results), 1, "search by exact ra match");

# Write catalog
my $outcat = "catalog$$.dat";
$cat->reset_list;
$cat->write_catalog(Format => 'JCMT', File => "catalog$$.dat", removeduplicates => 0);
ok(-e $outcat, "Check catalog file was created");

# re-read it for comparison
my $cat3 = new Astro::Catalog(Format => 'JCMT', File => $outcat);

# Because of duplicates, we first go through and create a hash indexed by ID
my %hash1 = form_hash($cat);
my %hash2 = form_hash($cat3);
is(scalar keys %hash2, scalar keys %hash1, "Compare count");

for my $id (keys %hash1) {
    my $s1 = $hash1{$id};
    my $s2 = $hash2{$id};

    if (defined $s1 && defined $s2) {
        SKIP: {
            skip "HOLO source moves on the sky", 1 if ($id eq 'HOLO');
            my $d = $s1->coords->distance($s2->coords);
            ok($d->arcsec < 0.1, "Check coordinates $id");
        }
        SKIP: {
            skip "Only Equatorial coordinates have velocity", 5
                unless $s1->coords->type eq 'RADEC';
            is(sprintf("%.1f", $s2->coords->rv), sprintf("%.1f", $s1->coords->rv), "Compare velocity");
            is($s2->coords->vdefn, $s1->coords->vdefn, "Compare vel definition");
            is($s2->coords->vframe, $s1->coords->vframe, "Compare vel frame");

            my $s1misc = $s1->misc;
            my $s2misc = $s2->misc;
            skip "Neither entry has a misc hash", 2,
                unless (defined($s1misc) && defined($s2misc));

            SKIP: {
                skip "Entries do not have velocity range", 1,
                    unless (defined($s1misc->{'velocity_range'}) && defined($s2misc->{'velocity_range'}));
                is(sprintf( "%.2f", $s1misc->{'velocity_range'} ), sprintf( "%.2f", $s2misc->{'velocity_range'} ), "Compare line velocity range");
            }

            SKIP: {
                skip "Entries do not have flux", 1,
                    unless (defined($s1misc->{'flux850'}) && defined($s2misc->{'flux850'}));
                is(sprintf( "%.2f", $s1misc->{'flux850'} ), sprintf( "%.2f", $s2misc->{'flux850'} ), "Compare 850-micron flux");
            }
        }
    }
    else {
        # one of them is not defined
        if (!defined $s1 && !defined $s2) {
            ok(0, "ID $id exists in neither catalog");
        }
        elsif (!defined $s1) {
            ok(0, "ID $id does not exist in original catalog");
        }
        else {
            ok(0, "ID $id does not exist in new catalog");
        }

        SKIP: {
            skip "One of the coordinates is not defined", 3;
        }
    }
}

# and remove it
unlink $outcat;

# Test object constructor fails (should be in Astro::Catalog tests)
eval {my $cat2 = new Astro::Catalog(Format => 'JCMT', Data => {});};
ok($@, "Explicit object constructor failure - hash ref");

exit;

# my %hash = form_hash($cat);
sub form_hash {
    my $cat = shift;

    my %hash;
    for my $s ($cat->allstars) {
        my $id = $s->id;
        if (exists $hash{$id}) {
            my $c1 = $s->coords;
            my $c2 = $hash{$id}->coords;
            if ($c1->distance($c2) == 0) {
                # fine. The same coordinate
            }
            else {
                warn "ID matches $id but coords differ\n";
            }
        }
        else {
            $hash{$id} = $s;
        }
    }
    return %hash;
}

__DATA__
*                              JCMT_CATALOG
*                              ============
*
*  This catalogue is the new unified JCMT source catalogue. It can only be
*  used in software planes 136 or higher.
*
*  SOURCE NAME      (T1, A12)           source name
*  LONGITUDE        (T15,A,2I3,F7.3)    longitude (sign, hms/dms)
*  LATITUDE         (T30,A,2I3,F7.3)    latitude  (sign, dms)
*  COSYS            (T44,A2)            coordinate system code
*  VELOCITY         (T46,G12.2)         velocity (km/sec) (?f10.1)
*  FLUX             (n/a)               Flux [Jy/beam] or Peak antenna temperature [K]
*  VRANGE           (n/a)               velocity range of spectral line
*  VEL_DEF          (T70,A3)               velocity definition: LSR, HEL etc.
*  FRAME            (T75,A6)            velocity frame of reference RADIO, OPTICAL, RELATIVISTIC
*  COMMENTS         (n/a)               range of flux variations, integrated line intensity,
*                                       calibration standard, mode of observing etc.
*
*  NOTE:  The control task expects an entry for each column, even though some entries may never be used
*         (e.g. FLUX, which is informative only). If any of the columns: VELOCITY, FLUX, or VRANGE are
*         not applicable, PLEASE enter n/a in the appropriate column or 0.
*
*  The catalogue is organized in the following way:
*
*      CONTINUUM POINTING SOURCES
*          BLAZARS I - most of those in the previous catalog
*          BLAZARS II - new from the ICRF lists
*          BLAZARS III - bright (>0.3Jy), northern detections from m04bu23 (Ian Browne)
*          BLAZARS IV - from SMA catalog
*          COMPACT HII regions, AGB stars, PMS stars
*          Spectral-line 5-point sources also bright enough for continuum work
*      SPECTRAL LINE CALIBRATORS
*      SPECTRAL LINE FIVEPOINT SOURCES
*
*---------------------------------------------------------------------------------
*  Revisions :
*
* 1996 Jul 09 - original verison (?) (GS)
* 1996 Nov 24 - Modified holography source position (REH)
* 1997 Aug 29 - Modified holography position (RMP/GHLS)
* 1999 Nov 03 - updated coords to J2000, see notes (IMC - until next change)
* 2001 Feb 23 - updated 850um fluxes for 'new' blazars
* 2001 Mar 12 - add need for 120" chop for DG Tau
* 2001 Jul 02 - updated 0.85mm fluxes based on last 1.5years of data, for
*                - 76% of original blazars
*                - 51% of new blazars
*                - all but 5 continuum (non-blazar) sources
* 2002 Jan 04 - Several spectral-fivepoint objects were revealed as having
*               inaccurate coordinates. Previously, SIMBAD coordinates were used.
*               Size and sense of errors supported adoption of coordinates by
*               Loup et al (1993, A&AS 99, 291)
*               (which formed the basis of the 1950.0 version of this catalog).
*               Loup shows good correlation, for late type stars with HD numbers,
*               with the Hipparcos catalog.
*               Particular objects have caught the attention of observing staff
*               in the last couple of months (CIT6, V370Aur, V636Mon, all stars,
*               note) and in each case the Loup et al (1993) coordinates would
*               have provided better service. Previous updates for CIT6, IRC-10502,
*               GL865 superseded without loss of accuracy by Loup's coordinates.
*
* 2002 Apr 10 - updated HOLO position
* 2002 May 02 - 2 candidates from EIR added, 1622-2**
* 2002 Aug 20 - names of 0954+658 and 1739+522 correctly installed
* 2002 Nov 08 - coordinates for VYCMa & oh231.8 consolidated
* 2002 Dec 26 - Dec coords for o Ceti corrected - previousd update erroneous
* 2003 Jan 28 - Observatory program targets & Targets-Of-Opportunity removed
* 2003 Mar 20 - Addition of [c] [s] or [cs] as first characters of Comments field
*               to indicate utility as c-ontinuum or s-pectral-fivepoint
*               pointing sources. [cs] is for those suitable for both, with
*               a limiting brightness for normally [s] sources of 0.2Jy
* 2003 Jun 09 - 12 sp-line 5-point sources added (suggested by Thomas Lowe)
*             - 3 sp-line 5-pt sources (WXPsc, oCeti, CIT6) given [c] status also
* 2003 Jun 20 - VCyg coords consolidated
* 2004 Mar 29 - 5 additional CO:2-1 spectral-line sources added (courtesy TBL)
* 2004 May 04 - GL5379 removed - position uncertain by 11" (JW)
* 2004 Dec 13 - updated 850um fluxes
* 2004 Dec 14 - addition of bright (>0.3Jy) detections by m04bu23 (Ian Browne)
* 2004 Dec 19 - o Ceti coords updated to 2005.0 for proper motion
* 2005 Jan 28 - routine update of blazar brightnesses
* 2005 Mar 30 - routine update of blazar brightnesses
* 2005 Apr 19 - add BVP1 (courtesy V.Barnard)
* 2005 Jul 01 - rationalization of velocities for L1551-IRS1, OH231.8, NGC6334I
* 2005 Jul 12 - W3(OH) : position updated to that by ICRS
* 2005 Sep 12 - offset positions for W3(OH) & L1551-IRS5 corrected
* 2006 Feb 13 - include 1153+495 (thank you J.Hoge)
* 2007 Mar 02 - add possible maser source IRC+20326M
* 2007 May 04 - add comments for G45.1 = G45.07+0.13
* 2007 Jul 09 - update Loup sources for Hipparcos positions
*             - use p.m.s appropriate for 2010
*             - delete IRC+20326M (spurious); add NGC6563; correct VXSgr
* 2007 Jul 10 - add 3 stars from m07ai05
* 2007 Jul 17 - Notes for sp.line pointing sources to include
*               Loup class/quality and Hipparcos update if applicable
*
* 2007 Aug 30 - Add bright (IntInt>20K.km/s) Loup sources somehow not already in this catalog:
*             - NGC6072, & IRC+10401 to 'Loup-2', and V384Cep & IILup to L-3
* 2008 Jan 28 - clarify Int.Int.s for GL230
* 2008 Aug 28 - remove GL230, V1365Aql, V437Sct following analysis by J.Wouterloot
* 2008 Sep 09 - change s-pectral l-ine notation from [s] to [l]
* 2008 Oct 01 - remove GL2374 - duplicate of OH44.1
* 2009 May 30 - update positions of some spectral line sources to improved 2mass positions from II/246 catalog
*             - vl362Aql removed
* 2009 Jul 08 - oCeti coords brought into agreement.
* 2009 Aug 03 - NGC6072 removed
* 2009 Aug 26 - NGC6563 and NGC6302 removed
* 2009 Oct 05 - Revised coords for 3c111 and MWC349A
* 2009 Oct 05 - Added sources from SMA catalog : 0102+584, 0510+180, 2025+337
* 2009 Dec 09 - CAW change the holo source position
* 2010 Feb 09 - Adjusted coordinates for  W3(OH)
* 2012 Jan 12 - Add SCUBA-2 calibrators
* 2012 Oct 10 - Update CENA coords to match SMA
* 2012 Oct 10 - Add SMA fluxes to comments if over 1 Jy or SMA data taken in 2012.
* 2013 May 18 - J2056-472 added as a southern pointing source. Coords from SMA as slightly different from optical ICRS.
* 2014 Sep 09 - Removed GL2143, GL2316, GL5102, IRC+60041, OH17.2-2, OH104.9, OH44.8, OH63.3-10.2, RSct, RYMon,
*             - SLyr, STCam, UCyg, VXSgr, V636Mon, V1366Aql, WCMa, WYCas, XCnc, YHya, YTau, 01142+6303,
*             - 03313+6058, 19454+2920, 21554+6204, 23321+6545, because too weak or too much unrelated
*             - emission (VXSgr)
*             - Added KUAnd, SCas, HL278, GL341, Betelgeuse, GL971, YLyn, RSCnc, IWHya, IRC-10236, RCrt, HD102608,
*             - SWVir, RHya, OH338.1+6.4, 16594-4656, GL6815S, GL5379, RVAqr, TCep, EPAqr, GL3099
*             - Results from M13BN01 and M14AN01
* 2015 Sep 11 - New RxA data for Pi1Gru, 16594-4656, GL6815S, TCep, EPAqr
* 2015 Oct 21 - New RxA data for GL5379
* 2015 Oct 27 - new flux for 0528+134
* 2015 Nov 19 - new fluxes for blazars observed with SCUBA-2 between 20150301 and 20151116
* 2015 Nov 20 - corrected positions for 5 'desperate' continuum sources (CenA position was wrong since 2012 Oct 10)
*             - Corrected coordinate system for IRC+10401 and updated position (RJ instead of RL).
* 2015 Dec 07 - new fluxes for blazars observed with SCUBA-2 between 20151116 and 20151123
*             - removed heterodyne standard sources (these are not good for spectral line pointing)
*             - updated RxA info RVAqr
* 2016 Jan 20 - new fluxes for blazars observed with SCUBA-2 between 20151217 and 20160120
* 2016 Feb 22 - new fluxes for blazars observed with SCUBA-2 between 20160121 and 20160222
* 2016 Apr 23 - new fluxes for blazars observed with SCUBA-2 between 20160223 and 20160423
* 2016 May 26 - new fluxes for blazars observed with SCUBA-2 between 20160424 and 20160526
* 2016 Jun 23 - new fluxes for blazars observed with SCUBA-2 between 20160527 and 20160623
* 2016 Oct 10 - new fluxes for blazars observed with SCUBA-2 between 20160623 and 20161010
*               comment out duplicate name 3C454.3 (2251+158), second entries for MWC349A, V645Cyg
*               optical positions instead of SCUBA positions for Sandell 2011 sources
* 2016 Oct 26 - corrected position oCeti for proper motion to 2017.0
* 2016 Nov 21 - corrected star positions for proper motion to 2017.0, where available (indicated by pm)
* 2017 Jun 01 - new fluxes for blazars observed with SCUBA-2 between 20161011 and 20170531
* 2017 Jun 02 - removed duplicates PKS0106 (= 0106+013) and 3C120 (= 0430+052)
* 2017 Sep 18 - corrected coordinates GL2494 (were off -10.1, -2.4 arcsec - wrong 2MASS source position)
* 2017 Oct 03 - updated information for GL2494 after obtaining new data
* 2017 Oct 04 - new fluxes for blazars observed with SCUBA-2 between 20170601 and 20171004
* 2018 Mar 27 - new fluxes for blazars observed with SCUBA-2 between 20171004 and 20180309
* 2019 May 23 - new fluxes for blazars observed with SCUBA-2 between 20180310 and 20190522
* 2019 May 23 - added GL5552, V1426Cyg, and 08074-3615
* 2020 Dec 07 - added GL1822
* 2022 Mar 28 - removed VirgoA
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
* SCUBA-2 CALIBRATORS
* SOURCE        RA            DEC          EQUI  VEL    FLUX   RANGE FRAME DEF   Comments
*                                          NOX    -    0.85mm    -               [source of flux in col 5] [other comments]
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
HD135344B       15 15 48.411 - 37 09 16.44 RJ    n/a     0.53    n/a  LSR  RADIO [c] pm [S2] same from Sandell 2011
Arp220          15 34 57.272 + 23 30 10.48 RJ    n/a     0.81    n/a  LSR  RADIO [c]    [S2] same from BLAST SED curve
HD141569        15 49 57.727 - 03 55 16.67 RJ    n/a     0.01    n/a  LSR  RADIO [c] pm [Sandell 2011]
HD142666        15 56 40.009 - 22 01 40.40 RJ    n/a     0.3     n/a  LSR  RADIO [c] pm [Sandell 2011]
HR5999          16 08 34.273 - 39 06 18.72 RJ    n/a     0.06    n/a  LSR  RADIO [c] pm [Sandell 2011]
KKOph           17 10 08.135 - 27 15 19.09 RJ    n/a     0.1     n/a  LSR  RADIO [c] pm [Sandell 2011]
HD169142        18 24 29.776 - 29 46 50.05 RJ    n/a     0.58    n/a  LSR  RADIO [c] pm [S2] same from Sandell 2011
MWC349A         20 32 45.518 + 40 39 36.62 RJ    n/a     2.19    n/a  LSR  RADIO [c]    [S2] 2.6 Jy Sandell 2011
PVCep           20 45 53.943 + 67 57 38.66 RJ    n/a     1.35    n/a  LSR  RADIO [c]    [S2] 1.0 Jy Sandell 2011
V645Cyg         21 39 58.255 + 50 14 20.93 RJ    n/a     2.4     n/a  LSR  RADIO [c]    [Sandell 2011] Extended source (14".2 x 8".5)
BVP1            17 43 10.370 - 29 51 44.0  RJ    n/a     1.55    n/a  LSR  RADIO [c]    [S2]
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*  CONTINUUM POINTING SOURCES : BLAZARS
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*
*  Coordinates for blazars taken from
*     Kuhr et al.         1981 Astr. Ap. Suppl., 45, 367
*     Perley, R.A.        1982 A.J. 87, 859
*     Hewitt & Burbridge  1987 Ap.J. Suppl. 63, 1-246
*     Edelson R.A.        1987 A.J. 94, 1150
*
*  see http://www.jach.hawaii.edu/JACpublic/JCMT/pointing/point2000.html
*  for the contributions of each of these to this catalog, and for
*  the transformations etc leading to this version of the catalog.
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
* BLAZARS I
* SOURCE        RA            DEC          EQUI  VEL    FLUX   RANGE FRAME DEF   Comments
*                                          NOX    -    0.85mm    -               [source of flux in col 5] other comments
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
0003-066        00 06 13.893 - 06 23 35.33 RJ    n/a     1.03    n/a  LSR  RADIO [c] [S2] 20190509
0048-097        00 50 41.318 - 09 29 05.21 RJ    n/a     0.24    n/a  LSR  RADIO [c] [S2] 20181029
0133+476        01 36 58.595 + 47 51 29.10 RJ    n/a     0.59    n/a  LSR  RADIO [c] [S2] 20190117
0149+218        01 52 18.059 + 22 07 07.70 RJ    n/a     0.44    n/a  LSR  RADIO [c] [S2] 20181029
0202+319        02 05 04.925 + 32 12 30.10 RJ    n/a     0.29    n/a  LSR  RADIO [c] [S2] 20171118
0212+735        02 17 30.813 + 73 49 32.62 RJ    n/a     0.24    n/a  LSR  RADIO [c] [S2] 20181111
0215+015        02 17 48.955 + 01 44 49.70 RJ    n/a     0.51    n/a  LSR  RADIO [c] [S2] 20190111
0219+428        02 22 39.612 + 43 02 07.80 RJ    n/a     0.28    n/a  LSR  RADIO [c] [S2] 20180909
0221+067        02 24 28.428 + 06 59 23.34 RJ    n/a     0.42    n/a  LSR  RADIO [c] [S2] 20190111
0224+671        02 28 50.051 + 67 21 03.03 RJ    n/a     0.56    n/a  LSR  RADIO [c] [S2] 20180915
0234+285        02 37 52.406 + 28 48 08.99 RJ    n/a     1.04    n/a  LSR  RADIO [c] [S2] 20190102
0235+164        02 38 38.930 + 16 36 59.27 RJ    n/a     0.44    n/a  LSR  RADIO [c] [S2] 20181010
0300+471        03 03 35.242 + 47 16 16.28 RJ    n/a     0.86    n/a  LSR  RADIO [c] [S2] 20180915
0306+102        03 09 03.624 + 10 29 16.34 RJ    n/a     0.30    n/a  LSR  RADIO [c] [S2] 20181029
3C84            03 19 48.160 + 41 30 42.10 RJ    n/a     6.66    n/a  LSR  RADIO [c] [S2] 20190327
0336-019        03 39 30.938 - 01 46 35.80 RJ    n/a     0.38    n/a  LSR  RADIO [c] [S2] 20190404
0355+508        03 59 29.747 + 50 57 50.16 RJ    n/a     1.04    n/a  LSR  RADIO [c] [S2] 20181029
3C111           04 18 21.277 + 38 01 35.80 RJ    n/a     0.78    n/a  LSR  RADIO [c] [S2] 20190411
0420-014        04 23 15.801 - 01 20 33.07 RJ    n/a     2.02    n/a  LSR  RADIO [c] [S2] 20181012
0422+004        04 24 46.842 + 00 36 06.33 RJ    n/a     0.18    n/a  LSR  RADIO [c] [S2] 20181012
PKS0438         04 40 17.180 - 43 33 08.60 RJ    n/a     0.4     n/a  LSR  RADIO [c] [S1]
0454-234        04 57 03.179 - 23 24 52.02 RJ    n/a     0.57    n/a  LSR  RADIO [c] [S2] 20190115
0458-020        05 01 12.810 - 01 59 14.26 RJ    n/a     0.83    n/a  LSR  RADIO [c] [S2] 20190402
0521-365        05 22 57.985 - 36 27 30.85 RJ    n/a     2.01    n/a  LSR  RADIO [c] [S2] 20190308
0528+134        05 30 56.417 + 13 31 55.15 RJ    n/a     0.20    n/a  LSR  RADIO [c] [S2] 20181025
0529+075        05 32 38.998 + 07 32 43.35 RJ    n/a     0.55    n/a  LSR  RADIO [c] [S2] 20190311
PKS0537         05 38 50.362 - 44 05 08.94 RJ    n/a     0.83    n/a  LSR  RADIO [c] [S2] 20150929
0552+398        05 55 30.806 + 39 48 49.17 RJ    n/a     0.19    n/a  LSR  RADIO [c] [S2] 20180915
0605-085        06 07 59.699 - 08 34 49.98 RJ    n/a     0.61    n/a  LSR  RADIO [c] [S2] 20190311
0607-157        06 09 40.950 - 15 42 40.67 RJ    n/a     0.43    n/a  LSR  RADIO [c] [S2] 20180304
0642+449        06 46 32.026 + 44 51 16.59 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20190311
0716+714        07 21 53.448 + 71 20 36.36 RJ    n/a     1.12    n/a  LSR  RADIO [c] [S2] 20190311
0727-115        07 30 19.112 - 11 41 12.60 RJ    n/a     0.58    n/a  LSR  RADIO [c] [S2] 20181122
0735+178        07 38 07.394 + 17 42 19.00 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20190311
0736+017        07 39 18.034 + 01 37 04.62 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181230
0745+241        07 48 36.109 + 24 00 24.11 RJ    n/a     0.57    n/a  LSR  RADIO [c] [S2] 20190311
0748+126        07 50 52.046 + 12 31 04.83 RJ    n/a     0.45    n/a  LSR  RADIO [c] [S2] 20181121
0754+100        07 57 06.643 + 09 56 34.85 RJ    n/a     0.43    n/a  LSR  RADIO [c] [S2] 20181121
0829+046        08 31 48.877 + 04 29 39.09 RJ    n/a     0.55    n/a  LSR  RADIO [c] [S2] 20190418
0836+710        08 41 24.365 + 70 53 42.17 RJ    n/a     0.58    n/a  LSR  RADIO [c] [S2] 20190311
OJ287           08 54 48.875 + 20 06 30.64 RJ    n/a     1.96    n/a  LSR  RADIO [c] [S2] 20190402
0917+449        09 20 58.458 + 44 41 53.99 RJ    n/a     0.43    n/a  LSR  RADIO [c] [S2] 20190403
0923+392        09 27 03.014 + 39 02 20.85 RJ    n/a     0.80    n/a  LSR  RADIO [c] [S2] 20190411
0954+658        09 58 47.245 + 65 33 54.82 RJ    n/a     0.40    n/a  LSR  RADIO [c] [S2] 20180309
1034-293        10 37 16.080 - 29 34 02.81 RJ    n/a     0.56    n/a  LSR  RADIO [c] [S2] 20190107
1044+719        10 48 27.620 + 71 43 35.94 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180714
1055+018        10 58 29.605 + 01 33 58.82 RJ    n/a     2.03    n/a  LSR  RADIO [c] [S2] 20190504
1147+245        11 50 19.212 + 24 17 53.84 RJ    n/a     0.49    n/a  LSR  RADIO [c] [S2] 20180713
1153+495        11 53 24.467 + 49 31 08.83 RJ    n/a     0.27    n/a  LSR  RADIO [c] [S2] 20190427
1156+295        11 59 31.834 + 29 14 43.83 RJ    n/a     0.30    n/a  LSR  RADIO [c] [S2] 20190426
1213-172        12 15 46.752 - 17 31 45.40 RJ    n/a     0.58    n/a  LSR  RADIO [c] [S2] 20180714
3C273           12 29 06.700 + 02 03 08.60 RJ    n/a     2.86    n/a  LSR  RADIO [c] [S2] 20190507
3C279           12 56 11.167 - 05 47 21.52 RJ    n/a     3.77    n/a  LSR  RADIO [c] [S2] 20190502
1308+326        13 10 28.664 + 32 20 43.78 RJ    n/a     0.59    n/a  LSR  RADIO [c] [S2] 20180712
1313-333        13 16 07.986 - 33 38 59.17 RJ    n/a     0.86    n/a  LSR  RADIO [c] [S2] 20180723
1334-127        13 37 39.783 - 12 57 24.69 RJ    n/a     2.29    n/a  LSR  RADIO [c] [S2] 20190426
1413+135        14 15 58.817 + 13 20 23.71 RJ    n/a     0.53    n/a  LSR  RADIO [c] [S2] 20181210
1418+546        14 19 46.597 + 54 23 14.78 RJ    n/a     0.40    n/a  LSR  RADIO [c] [S2] 20190410
1510-089        15 12 50.533 - 09 05 59.83 RJ    n/a     1.06    n/a  LSR  RADIO [c] [S2] 20190426
1514-241        15 17 41.813 - 24 22 19.48 RJ    n/a     1.73    n/a  LSR  RADIO [c] [S2] 20190426
1538+149        15 40 49.492 + 14 47 45.88 RJ    n/a     0.17    n/a  LSR  RADIO [c] [S2] 20180713
1548+056        15 50 35.269 + 05 27 10.45 RJ    n/a     0.33    n/a  LSR  RADIO [c] [S2] 20180713
1606+106        16 08 46.203 + 10 29 07.78 RJ    n/a     0.24    n/a  LSR  RADIO [c] [S2] 20180713
1611+343        16 13 41.064 + 34 12 47.91 RJ    n/a     0.51    n/a  LSR  RADIO [c] [S2] 20190426
1622-253        16 25 46.892 - 25 27 38.33 RJ    n/a     0.35    n/a  LSR  RADIO [c] [S2] 20180713
1622-297        16 26 06.021 - 29 51 26.97 RJ    n/a     0.48    n/a  LSR  RADIO [c] [S2] 20180713
1633+382        16 35 15.493 + 38 08 04.50 RJ    n/a     0.79    n/a  LSR  RADIO [c] [S2] 20190425
3C345           16 42 58.810 + 39 48 36.99 RJ    n/a     1.99    n/a  LSR  RADIO [c] [S2] 20190425
1657-261        17 00 53.154 - 26 10 51.72 RJ    n/a     0.74    n/a  LSR  RADIO [c] [S2] 20190509
1730-130        17 33 02.706 - 13 04 49.55 RJ    n/a     0.89    n/a  LSR  RADIO [c] [S2] 20190424
1739+522        17 40 36.978 + 52 11 43.41 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180713
1741-038        17 43 58.856 - 03 50 04.62 RJ    n/a     1.36    n/a  LSR  RADIO [c] [S2] 20190508
1749+096        17 51 32.819 + 09 39 00.73 RJ    n/a     1.50    n/a  LSR  RADIO [c] [S2] 20190502
1749+701        17 48 32.840 + 70 05 50.77 RJ    n/a     0.37    n/a  LSR  RADIO [c] [S2] 20180713
1803+784        18 00 45.684 + 78 28 04.02 RJ    n/a     1.30    n/a  LSR  RADIO [c] [S2] 20180714
1807+698        18 06 50.681 + 69 49 28.11 RJ    n/a     1.43    n/a  LSR  RADIO [c] [S2] 20190510
1823+568        18 24 07.068 + 56 51 01.49 RJ    n/a     0.62    n/a  LSR  RADIO [c] [S2] 20190330
1908-202        19 11 09.653 - 20 06 55.11 RJ    n/a     0.96    n/a  LSR  RADIO [c] [S2] 20180723
1921-293        19 24 51.056 - 29 14 30.12 RJ    n/a     2.03    n/a  LSR  RADIO [c] [S2] 20190404
1923+210        19 25 59.605 + 21 06 26.16 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180723
1928+738        19 27 48.495 + 73 58 01.57 RJ    n/a     0.59    n/a  LSR  RADIO [c] [S2] 20180723
1958-179        20 00 57.090 - 17 48 57.67 RJ    n/a     0.76    n/a  LSR  RADIO [c] [S2] 20180723
2005+403        20 07 44.945 + 40 29 48.60 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180721
2007+776        20 05 30.999 + 77 52 43.25 RJ    n/a     0.33    n/a  LSR  RADIO [c] [S2] 20180723
2008-159        20 11 15.711 - 15 46 40.25 RJ    n/a     0.33    n/a  LSR  RADIO [c] [S2] 20180723
2021+317        20 23 19.017 + 31 53 02.31 RJ    n/a     0.38    n/a  LSR  RADIO [c] [S2] 20180722
2037+511        20 38 37.035 + 51 19 12.66 RJ    n/a     0.70    n/a  LSR  RADIO [c] [S2] 20180721
2059+034        21 01 38.834 + 03 41 31.32 RJ    n/a     0.62    n/a  LSR  RADIO [c] [S2] 20190501
2134+004        21 36 38.586 + 00 41 54.21 RJ    n/a     0.40    n/a  LSR  RADIO [c] [S2] 20180713
2145+067        21 48 05.459 + 06 57 38.60 RJ    n/a     0.53    n/a  LSR  RADIO [c] [S2] 20181213
2155-304        21 58 52.065 - 30 13 32.12 RJ    n/a     0.22    n/a  LSR  RADIO [c] [S2] 20180713
2155-152        21 58 06.282 - 15 01 09.33 RJ    n/a     0.81    n/a  LSR  RADIO [c] [S2] 20190407
BLLAC           22 02 43.291 + 42 16 39.98 RJ    n/a     1.58    n/a  LSR  RADIO [c] [S2] 20181003
2201+315        22 03 14.976 + 31 45 38.27 RJ    n/a     0.62    n/a  LSR  RADIO [c] [S2] 20190415
2223-052        22 25 47.259 - 04 57 01.39 RJ    n/a     0.41    n/a  LSR  RADIO [c] [S2] 20180723
2227-088        22 29 40.084 - 08 32 54.44 RJ    n/a     0.45    n/a  LSR  RADIO [c] [S2] 20190502
2230+114        22 32 36.409 + 11 43 50.90 RJ    n/a     1.19    n/a  LSR  RADIO [c] [S2] 20190426
2243-123        22 46 18.232 - 12 06 51.28 RJ    n/a     0.19    n/a  LSR  RADIO [c] [S2] 20181029
*3C454.3        22 53 57.748 + 16 08 53.56 RJ    n/a     3.17    n/a  LSR  RADIO [c] [S2] 20190315
2251+158        22 53 57.748 + 16 08 53.56 RJ    n/a     3.17    n/a  LSR  RADIO [c] [S2] 20190315
2255-282        22 58 05.963 - 27 58 21.26 RJ    n/a     2.37    n/a  LSR  RADIO [c] [S2] 20190508
2318+049        23 20 44.857 + 05 13 49.95 RJ    n/a     0.41    n/a  LSR  RADIO [c] [S2] 20181029
2345-167        23 48 02.609 - 16 31 12.02 RJ    n/a     1.19    n/a  LSR  RADIO [c] [S2] 20190421
*
* The 5 sources below were not carried over from the original (RB) version
* due to inaccuracies in their positions, but they are repeated here in
* case of desperation - 3c111 and CenA in particular are too strong to
* discard completely.
* On 20151120 updated to accurate RJ positions from NED database.
*
0954+556        09 57 38.184 + 55 22 57.77 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181114
1219+285        12 21 31.691 + 28 13 58.50 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180713
CENA            13 25 27.615 - 43 01 08.81 RJ    n/a     9.82    n/a  LSR  RADIO [c] [S2] 20181210
1716+686        17 16 13.938 + 68 36 38.74 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180713
CygA            19 59 28.357 + 40 44 02.10 RJ    n/a     0.41    n/a  LSR  RADIO [c] [S2] 20180721
*
* 76 of the next 78 blazars are new to this version of the catalog
* see http://www.jach.hawaii.edu/JACpublic/JCMT/pointing/point2000.html
* for a description of their inclusion.
* Two (0106+013 and 0430+052) are already listed above by their familiars
*      PKS0106  and   3c120).
* fluxes listed are either :
*      - the most recent determinations at 850um at JCMT
*        in which case the date of the last measure and the ranges of previous measures
*        are shown in the last column, or
*      - they are (the original) extrapolations from other wavelengths.
*        These proved to be overly optimistic by about x2,
*        so were reduced now by this factor, with a minimum of 0.2 Jy
*        so as to encourage at least one observation.
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
* BLAZARS II
* SOURCE        RA            DEC          EQUI  VEL    FLUX   RANGE FRAME DEF   Comments
*                                          NOX    -    0.85mm    -               [source of flux in col 5] [other comments]
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
0016+731        00 19 45.786 + 73 27 30.02 RJ    n/a     0.59    n/a  LSR  RADIO [c] [S2] 20180915
0035+413        00 38 24.844 + 41 37 06.00 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180909
0106+013        01 08 38.771 + 01 35 00.32 RJ    n/a     0.54    n/a  LSR  RADIO [c] [S2] 20190510
0112-017        01 15 17.100 - 01 27 04.58 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181029
0119+041        01 21 56.862 + 04 22 24.73 RJ    n/a     0.18    n/a  LSR  RADIO [c] [S2] 20181029
0134+329        01 37 41.299 + 33 09 35.13 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20151123
0135-247        01 37 38.347 - 24 30 53.89 RJ    n/a     1.27    n/a  LSR  RADIO [c] [S2] 20181212
0138-097        01 41 25.832 - 09 28 43.67 RJ    n/a     0.41    n/a  LSR  RADIO [c] [S2] 20181029
0229+131        02 31 45.894 + 13 22 54.72 RJ    n/a     0.14    n/a  LSR  RADIO [c] [S2] 20181010
0239+108        02 42 29.171 + 11 01 00.73 RJ    n/a     0.14    n/a  LSR  RADIO [c] [S2] 20181010
0333+321        03 36 30.108 + 32 18 29.34 RJ    n/a     0.70    n/a  LSR  RADIO [c] [S2] 20180915
0338-214        03 40 35.608 - 21 19 31.17 RJ    n/a     0.18    n/a  LSR  RADIO [c] [S2] 20190116
0414-189        04 16 36.544 - 18 51 08.34 RJ    n/a     0.15    n/a  LSR  RADIO [c] [S2] 20170802
0430+052        04 33 11.096 + 05 21 15.62 RJ    n/a     1.56    n/a  LSR  RADIO [c] [S2] 20181222
0511-220        05 13 49.114 - 21 59 16.09 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20170915
0518+165        05 21 09.886 + 16 38 22.05 RJ    n/a     0.16    n/a  LSR  RADIO [c] [S2] 20181025
0538+498        05 42 36.138 + 49 51 07.23 RJ    n/a     0.25    n/a  LSR  RADIO [c] [S2] 20190311
0539-057        05 41 38.083 - 05 41 49.43 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20190311
0648-165        06 50 24.582 - 16 37 39.73 RJ    n/a     0.36    n/a  LSR  RADIO [c] [S2] 20180304
0723-008        07 25 50.640 - 00 54 56.54 RJ    n/a     1.34    n/a  LSR  RADIO [c] [S2] 20190226
0742+103        07 45 33.060 + 10 11 12.69 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181121
0743-006        07 45 54.082 - 00 44 15.54 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181230
0808+019        08 11 26.707 + 01 46 52.22 RJ    n/a     0.37    n/a  LSR  RADIO [c] [S2] 20181230
0814+425        08 18 16.000 + 42 22 45.41 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181230
0818-128        08 20 57.448 - 12 58 59.17 RJ    n/a     0.15    n/a  LSR  RADIO [c] [S2] 20181122
0823+033        08 25 50.338 + 03 09 24.52 RJ    n/a     0.30    n/a  LSR  RADIO [c] [S2] 20190310
0828+493        08 32 23.217 + 49 13 21.04 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181229
0859+470        09 03 03.990 + 46 51 04.14 RJ    n/a     0.30    n/a  LSR  RADIO [c] [S2] 20181120
0859-140        09 02 16.831 - 14 15 30.88 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181122
0906+015        09 09 10.092 + 01 21 35.62 RJ    n/a     0.18    n/a  LSR  RADIO [c] [S2] 20190109
0917+624        09 21 36.231 + 62 15 52.18 RJ    n/a     0.39    n/a  LSR  RADIO [c] [S2] 20181114
0919-260        09 21 29.354 - 26 18 43.39 RJ    n/a     0.14    n/a  LSR  RADIO [c] [S2] 20181112
0925-203        09 27 51.824 - 20 34 51.23 RJ    n/a     0.16    n/a  LSR  RADIO [c] [S2] 20181112
0955+326        09 58 20.950 + 32 24 02.21 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181229
1011+250        10 13 53.429 + 24 49 16.44 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181229
1012+232        10 14 47.065 + 23 01 16.57 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181229
1053+815        10 58 11.535 + 81 14 32.68 RJ    n/a     0.3     n/a  LSR  RADIO [c] [S1] 0.3 -     Jy (2001 Feb)
1116+128        11 18 57.301 + 12 34 41.72 RJ    n/a     0.17    n/a  LSR  RADIO [c] [S2] 20180302
1124-186        11 27 04.392 - 18 57 17.44 RJ    n/a     0.36    n/a  LSR  RADIO [c] [S2] 20180302
1127-145        11 30 07.053 - 14 49 27.39 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180714
1128+385        11 30 53.283 + 38 15 18.55 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180714
1144+402        11 46 58.298 + 39 58 34.30 RJ    n/a     0.49    n/a  LSR  RADIO [c] [S2] 20190510
1148-001        11 50 43.871 - 00 23 54.20 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180714
1216+487        12 19 06.415 + 48 29 56.16 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180713
1222+037        12 24 52.422 + 03 30 50.29 RJ    n/a     0.67    n/a  LSR  RADIO [c] [S2] 20181219
1243-072        12 46 04.232 - 07 30 46.57 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180714
1244-255        12 46 46.802 - 25 47 49.29 RJ    n/a     0.60    n/a  LSR  RADIO [c] [S2] 20190427
1252+119        12 54 38.256 + 11 41 05.90 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180712
1302-102        13 05 33.015 - 10 33 19.43 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180714
1328+307        13 31 08.288 + 30 30 32.96 RJ    n/a     0.18    n/a  LSR  RADIO [c] [S2] 20180712
1345+125        13 47 33.362 + 12 17 24.24 RJ    n/a     0.22    n/a  LSR  RADIO [c] [S2] 20181211
1354-152        13 57 11.245 - 15 27 28.79 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20160605
1354+195        13 57 04.437 + 19 19 07.37 RJ    n/a     0.27    n/a  LSR  RADIO [c] [S2] 20190416
1502+106        15 04 24.980 + 10 29 39.20 RJ    n/a     1.22    n/a  LSR  RADIO [c] [S2] 20190501
1504-166        15 07 04.787 - 16 52 30.27 RJ    n/a     0.20    n/a  LSR  RADIO [c] [S2] 20160605
1511-100        15 13 44.893 - 10 12 00.26 RJ    n/a     0.38    n/a  LSR  RADIO [c] [S2] 20180713
1519-273        15 22 37.676 - 27 30 10.79 RJ    n/a     0.17    n/a  LSR  RADIO [c] [S2] 20160605
1600+335        16 02 07.263 + 33 26 53.07 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180712
1637+574        16 38 13.456 + 57 20 23.98 RJ    n/a     0.40    n/a  LSR  RADIO [c] [S2] 20180713
1638+398        16 40 29.633 + 39 46 46.03 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180712
1642+690        16 42 07.849 + 68 56 39.76 RJ    n/a     0.27    n/a  LSR  RADIO [c] [S2] 20180713
1655+077        16 58 09.011 + 07 41 27.54 RJ    n/a     0.30    n/a  LSR  RADIO [c] [S2] 20180720
1656+477        16 58 02.780 + 47 37 49.23 RJ    n/a     0.26    n/a  LSR  RADIO [c] [S2] 20180712
1717+178        17 19 13.048 + 17 45 06.44 RJ    n/a     0.38    n/a  LSR  RADIO [c] [S2] 20180720
1743+173        17 45 35.208 + 17 20 01.42 RJ    n/a     0.14    n/a  LSR  RADIO [c] [S2] 20180720
1758+388        18 00 24.765 + 38 48 30.70 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180712
1800+440        18 01 32.315 + 44 04 21.90 RJ    n/a     0.36    n/a  LSR  RADIO [c] [S2] 20180712
1842+681        18 42 33.642 + 68 09 25.23 RJ    n/a     0.24    n/a  LSR  RADIO [c] [S2] 20180303
1954+513        19 55 42.738 + 51 31 48.55 RJ    n/a     0.28    n/a  LSR  RADIO [c] [S2] 20180721
2021+614        20 22 06.682 + 61 36 58.80 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180721
2121+053        21 23 44.517 + 05 35 22.09 RJ    n/a     0.56    n/a  LSR  RADIO [c] [S2] 20180723
2128-123        21 31 35.262 - 12 07 04.80 RJ    n/a     0.21    n/a  LSR  RADIO [c] [S2] 20180713
2131-021        21 34 10.310 - 01 53 17.24 RJ    n/a     0.87    n/a  LSR  RADIO [c] [S2] 20180713
2210-257        22 13 02.498 - 25 29 30.08 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181029
2216-038        22 18 52.038 - 03 35 36.88 RJ    n/a     0.47    n/a  LSR  RADIO [c] [S2] 20180723
2229+695        22 30 36.470 + 69 46 28.08 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180722
2234+282        22 36 22.471 + 28 28 57.41 RJ    n/a     0.63    n/a  LSR  RADIO [c] [S2] 20190508
2344+092        23 46 36.839 + 09 30 45.51 RJ    n/a     0.15    n/a  LSR  RADIO [c] [S2] 20181029
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
* BLAZARS III  - coordinates from ICRF (Ma et al AJ 116, 516)
* SOURCE        RA            DEC          EQUI  VEL    FLUX   RANGE FRAME DEF   Comments
*                                          NOX    -    0.85mm    -               observed range at 850um
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
0010+405        00 13 31.13  + 40 51 37.14 RJ    n/a     0.37    n/a  LSR  RADIO [c] [S2] 20190117
0110+495        01 13 27.01  + 49 48 24.04 RJ    n/a     0.46    n/a  LSR  RADIO [c] [S2] 20180909
0218+357        02 21 05.47  + 35 56 13.70 RJ    n/a     0.12    n/a  LSR  RADIO [c] [S2] 20180909
0227+403        02 30 45.70  + 40 32 53.08 RJ    n/a     0.17    n/a  LSR  RADIO [c] [S2] 20180909
0309+411        03 13 01.96  + 41 20 01.19 RJ    n/a     0.69    n/a  LSR  RADIO [c] [S2] 20180915
0444+634        04 49 23.31  + 63 32 09.43 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181029
0707+476        07 10 46.10  + 47 32 11.14 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181229
0714+457        07 17 51.85  + 45 38 03.25 RJ    n/a     0.32    n/a  LSR  RADIO [c] [S2] 20190311
0749+540        07 53 01.38  + 53 52 59.64 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181230
0804+499        08 08 39.67  + 49 50 36.53 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20181229
1030+611        10 33 51.43  + 60 51 07.33 RJ    n/a     0.73    n/a  LSR  RADIO [c] [S2] 20190309
1053+704        10 56 53.62  + 70 11 45.92 RJ    n/a     0.25    n/a  LSR  RADIO [c] [S2] 20181214
1636+473        16 37 45.13  + 47 17 33.84 RJ    n/a     0.25    n/a  LSR  RADIO [c] [S2] 20180712
1700+685        17 00 09.29  + 68 30 06.96 RJ    n/a     0.76    n/a  LSR  RADIO [c] [S2] 20180713
1732+389        17 34 20.58  + 38 57 51.44 RJ    n/a     0.88    n/a  LSR  RADIO [c] [S2] 20190320
1849+670        18 49 16.07  + 67 05 41.68 RJ    n/a     0.42    n/a  LSR  RADIO [c] [S2] 20190409
1926+611        19 27 30.44  + 61 17 32.88 RJ    n/a     0.29    n/a  LSR  RADIO [c] [S2] 20180721
2023+760        20 22 35.58  + 76 11 26.18 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180723
2351+456        23 54 21.68  + 45 53 04.24 RJ    n/a     0.10    n/a  LSR  RADIO [c] [S2] 20180722
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
* BLAZARS IV  - coordinates from SMA catalog -  http://sma1.sma.hawaii.edu/callist/callist.html
*
* SOURCE        RA            DEC          EQUI  VEL    FLUX   RANGE FRAME DEF   Comments
*                                          NOX    -    0.85mm    -               observed range at 850um
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
0102+584        01 02 45.76  + 58 24 11.14 RJ    n/a     0.92    n/a  LSR  RADIO [c] [S2] 20181121
2025+337        20 25 10.84  + 33 43 00.21 RJ    n/a     0.83    n/a  LSR  RADIO [c] [S2] 20180722
0510+180        05 10 02.37  + 18 00 41.58 RJ    n/a     1.12    n/a  LSR  RADIO [c] [S2] 20181025
J2056-472       20 56 16.40  - 47 14 47.80 RJ    n/a     0.6     n/a  LSR  RADIO [c] [S2] 0.4 (JCMT 2013) - 0.9 (SMA 2012)
*
* - -- -- -- -- -- --  -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*  CONTINUUM SOURCES : Compact HII regions, ABG and PMS - stars
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*
*  A few of these are secondary calibrators for SCUBA, some also serve as spectral line standards
*  Coordinates are either c - derived by coco (co-ordinate transformation) from 1950.0 FK4
*                                    - this is usually the case for non-stellar sources, where
*                                      submm & opt/NIR peaks may not coincide
*                      or s - as listed by Simbad (2000.0 FK5)
*                                    - this is usually reserved for stellar sources
* Fluxes - 2001 Jul - changed to 0.85mm fluxes, based on last 18months data.
*                     data for HH1-2VLA, Hya, M8E, ON-1, V645Cyg are the old 1.1mm values
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
* SOURCE        RA            DEC          EQUI  VEL    FLUX   RANGE FRAME DEF   Comments
*                                          NOX    -    0.85mm    -               c = coco  s = simbad
* - -- -- -- -- -- -- --  -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
W3(OH)          02 27 03.85  + 61 52 24.8  RJ  -   45.0 35.0     n/a  LSR  RADIO [c] c
GL490           03 27 38.842 + 58 47 00.51 RJ  -   12.5  5.0     n/a  LSR  RADIO [c] c
TTau            04 21 59.453 + 19 32 06.19 RJ  +    7.5  1.3     n/a  LSR  RADIO [c] s pm T Tauri star
DGTau           04 27 04.702 + 26 06 16.00 RJ  +    5.0  0.9     n/a  LSR  RADIO [c] s pm T Tauri star; use 120" chop
L1551-IRS5      04 31 34.140 + 18 08 05.13 RJ  +    6.0  6.0     n/a  LSR  RADIO [c] c
HLTau           04 31 38.447 + 18 13 59.65 RJ  +    6.4  2.3     n/a  LSR  RADIO [c] s pm TTau-star - 2nd-ary flux calibrator
CRL618          04 42 53.672 + 36 06 53.17 RJ  -   21.7  4.5    90.0  LSR  RADIO [c] c Secondary flux calibrator
OMC1            05 35 14.373 - 05 22 32.35 RJ  +   10.0 99.9     n/a  LSR  RADIO [c] c use 150" chop for pointi
HH1-2VLA        05 36 22.837 - 06 46 06.57 RJ  +    8.0  0.8     n/a  LSR  RADIO [c] c
N2071IR         05 47 04.851 + 00 21 47.10 RJ  +    9.5 16.0     n/a  LSR  RADIO [c] c
VYCMa           07 22 58.336 - 25 46 03.35 RJ  +   19.0  1.7    70.0  LSR  RADIO [c] s pm
OH231.8         07 42 16.83  - 14 42 52.1  RJ  +   30.0  2.5   140.0  LSR  RADIO [c] c Secondary flux calibrator
IRC+10216       09 47 57.447 + 13 16 43.76 RJ  -   25.6  6.1    35.0  LSR  RADIO [c] c pm Secondary flux calibrator, var.
TWHya           11 01 51.816 - 34 42 17.03 RJ  +    0.0  0.8     n/a  LSR  RADIO [c] s pm T Tauri star
16293-2422      16 32 22.909 - 24 28 35.60 RJ  +    4.0 16.3     n/a  LSR  RADIO [c] c Secondary flux calibrator
G343.0          16 58 17.136 - 42 52 06.61 RJ  -   31.0 35.0     n/a  LSR  RADIO [c] c
NGC6334I        17 20 53.445 - 35 47 01.67 RJ  -    6.9 60.0     n/a  LSR  RADIO [c] c
*BVP1           17 43 10.32  - 29 51 43.5  RJ  -   20.0  1.5     n/a  LSR  RADIO [c] c
G5.89           18 00 30.376 - 24 04 00.48 RJ  +   10.0 48.0     n/a  LSR  RADIO [c] c
M8E             18 04 52.957 - 24 26 39.36 RJ  +   11.0  2.8     n/a  LSR  RADIO [c] c
G10.62          18 10 28.661 - 19 55 49.76 RJ  -    3.5 50.0     n/a  LSR  RADIO [c] c
G34.3           18 53 18.569 + 01 14 58.26 RJ  +   58.1 70.0     n/a  LSR  RADIO [c] c
G45.1           19 13 22.079 + 10 50 53.42 RJ  +   48.0 11.0     n/a  LSR  RADIO [c] c G45.07+0.13 needs chop EW >60". ApJ 478, 283
K3-50           20 01 45.689 + 33 32 43.52 RJ  -   23.7 20.0     n/a  LSR  RADIO [c] c
ON-1            20 10 09.146 + 31 31 37.67 RJ  +   11.8  4.7     n/a  LSR  RADIO [c] c
GL2591          20 29 24.719 + 40 11 18.87 RJ  -    5.8  3.0     n/a  LSR  RADIO [c] c
W75N            20 38 36.433 + 42 37 34.49 RJ  +   12.5 35.0     n/a  LSR  RADIO [c] c
*MWC349A        20 32 45.53  + 40 39 36.62 RJ  -    6.6  1.9     n/a  LSR  RADIO [c] s True point source
*PVCep          20 45 54.39  + 67 57 38.8  RJ  +    3.0  1.2     n/a  LSR  RADIO [c] s
CRL2688         21 02 18.75  + 36 41 37.80 RJ  -   35.4  5.9    80.0  LSR  RADIO [c] c Secondary flux calibrator
NGC7027         21 07 01.598 + 42 14 10.02 RJ  +   26.0  5.0    50.0  LSR  RADIO [c] c
*V645Cyg        21 39 58.2   + 50 14 22.   RJ  -   43.7  0.9     n/a  LSR  RADIO [c] s
LKHA234         21 43 06.170 + 66 06 56.09 RJ  -   10.0  5.0     n/a  LSR  RADIO [c] c Herbig Be star
N7538IRS1       23 13 45.346 + 61 28 10.32 RJ  -   58.0 33.0     n/a  LSR  RADIO [c] c
N7538IRS9       23 14 01.682 + 61 27 19.96 RJ  -   58.0  6.5     n/a  LSR  RADIO [c] c
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*
*   Sources for use in continuum mode originally intended only
*   for use in spectral-line 5-pointing mode. They have proven sufficiently
*   bright at 850um to qualify as 'continuum' sources.
*
WXPsc           01 06 25.98  + 12 35 53.0  RJ  +    8.5  0.2    35.0  LSR  RADIO [c]2-1 41.0 J3-2 51.2 4-3 23.2
oCeti           02 19 20.803 - 02 58 43.54 RJ  +   46.5  0.5    28.0  LSR  RADIO [c] pm 2-1 34.6 J3-2 48.2 4-3 46.2 J2005
CIT6            10 16 02.29  + 30 34 19.1  RJ  -    1.9  0.7    45.0  LSR  RADIO [c]2-1 111.3 3-2 194.9 4-3 1
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*   SOURCELIST for SPECTRAL LINE FIVEPOINTS
*   Positions taken from Loup et al. A&A Suppl. Ser 99, 291 (1993).
*   This section sub-divided according to positional accuracy flags by Loup et al.
*   except that
*     - 9 stars with HD numbers and flag=2 that differ by < approx 1"
*       from Hipparcos positions are in section 1.
*     - 6 weak or v.southern objects with Loup flags=1 appear in section 2,
*       since, in the cases where comparison with Hipparcos is possible -
*       the first two - differences of >1" are seen.
*       (R Hor, R Dor, V1362Aql, V1366Aql, GL2374, GL2885). (20020107)
*   VXSgr & RRAql added 20020107.
*   Note CRL2688 is in section 2 (?!).
*   See also K. Young (1995, ApJ 445, 872).
*   Other (flux) data often courtesy H. Matthews and J. Greaves.
*   Positions for objects in common with spectral line standards (CRL618,
*   CRL2688, NGC7027, section above) are left unchanged, but these are not
*   inconsistent with Loup.
*   Note that we still have not gone through all the sources in the list.!!
*
*   The catalogue gives T_A* (peak) for the 2-1 line. More informative, however, are the integrated line intensities
*   in the comment line (in K km/s), which largely determine how easy it is to detect a line. Note that JCMT 2-1
*   data followed by J are typically low by about a factor of 1.3 - 1.5 (telescope heavily deformed due to conebar
*   welding.
*
* 20070717 Notes reflect new positional accuracies : L1 L2 L3 original Loup qualities (<1", 1-5", >5");
*                                                  : /H and /T reflect updates by Hipparcos & Tycho (uncertainty of <1")
* 20060530 Notes reflect new positional accuracies : /2M reflect updates by 2MASS (catalog II/246)
*
* 20140910 Modifications based on M13BN01 and M14AN01:
*          Vlsr, Tpeak, Vrange derived from HARP CO(3-2) spectra
*          Under comments is indicated whether source is good for RxA, HARP, or both: A, H, AH
*          and Tpeak, Integrated intensity for CO(2-1) and CO(3-2)
*
*
*               RA & DEC                   Eq  Vlsr     Tpeak   Vrange           JCMT   comments
*- -- -- -- -- -- --  -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*- -- -- -- -- -- --  -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*
TCas            00 23 14.311 + 55 47 33.05 RJ  -    7.0  0.8    28.0  LSR  RADIO [l] H  L1/Hpm 0.35 5.8 ; 0.83 12.9
WXPsc           01 06 25.98  + 12 35 53.0  RJ  +    8.5  1.7    47.0  LSR  RADIO [l] AH L1/2M 1.3 36.9 ; 1.7 45.2
RScl            01 26 58.085 - 32 32 35.98 RJ  -   18.4  2.1    38.0  LSR  RADIO [l] AH L1/Hpm 1.9 50.6 ; 2.1 43.5
oCeti           02 19 20.803 - 02 58 43.54 RJ  +   46.5 14.4    19.0  LSR  RADIO [l] AH L1/Hpm 7.5 37.1 ; 14.4 75.1
UCam            03 41 48.183 + 62 38 54.33 RJ  +    7.1  1.0    72.0  LSR  RADIO [l] AH L1/Hpm 0.61 23.2 ; 1.0 43.8
NMLTau          03 53 28.87  + 11 24 21.7  RJ  +   30.5  3.0    56.0  LSR  RADIO [l] AH L1/2M 1.9 59.2 ; 3.0 87.2
CRL618          04 42 53.672 + 36 06 53.17 RJ  -   21.7  4.5    90.0  LSR  RADIO [l] AH L1+ 3.5 91.0 ; 4.5 118.3
RLep            04 59 36.358 - 14 48 22.60 RJ  +   12.8  1.2    40.0  LSR  RADIO [l] AH L1/Hpm 0.74 21.1 ; 1.2 33.1
NVAur           05 11 19.44  + 52 52 33.2  RJ  +    3.0  1.0    36.0  LSR  RADIO [l] AH L1/2M 0.75 19.5 ; 1.0 25.4
RAur            05 17 17.700 + 53 35 09.83 RJ  -    1.6  1.2    22.0  LSR  RADIO [l] AH L1/Hpm 0.71 9.9 ; 1.2 15.2
UUAur           06 36 32.836 + 38 26 43.47 RJ  +    7.0  1.1    26.0  LSR  RADIO [l] AH L1/Hpm 0.67 12.1 ; 1.1 20.8
VYCMa           07 22 58.336 - 25 46 03.35 RJ  +   19.0  2.6    92.0  LSR  RADIO [l] AH L1/Hpm 0.77 47.5 ; 2.6 161.4
M1-16           07 37 18.955 - 09 38 49.67 RJ  +   49.0  1.9    57.0  LSR  RADIO [l] AH L1+ 1.2 34.9 ; 1.9 59.0
M1-17           07 40 22.206 - 11 32 29.81 RJ  +   28.0  1.1    78.0  LSR  RADIO [l] AH L1+ 0.75 24.3 ; 1.1 41.3
OH231.8         07 42 16.83  - 14 42 52.1  RJ  +   37.0  2.0   160.0  LSR  RADIO [l] AH L1+ 1.1 71.5 ; 2.0 108.4
RLMi            09 45 34.289 + 34 30 42.68 RJ  +    0.1  0.9    20.0  LSR  RADIO [l] AH L1/Hpm 0.50 5.0 ; 0.85 10.0
RLeo            09 47 33.482 + 11 25 42.97 RJ  -    0.4  2.4    17.0  LSR  RADIO [l] AH L1/Hpm 1.0 10.8 ; 2.4 27.2
IRC+10216       09 47 57.447 + 13 16 43.76 RJ  -   25.6 31.8    35.0  LSR  RADIO [l] AH L1+pm  20.8 474 ; 31.8 702
CIT6            10 16 02.29  + 30 34 19.1  RJ  -    1.9  6.9    45.0  LSR  RADIO [l] AH L1/2M 4.2 113.8 ; 6.9 176.2
RTVir           13 02 38.023 + 05 11 08.08 RJ  +   18.0  0.8    20.0  LSR  RADIO [l] AH L1/Hpm 0.58 7.6 ; 0.76 9.7
WHya            13 49 01.934 - 28 22 04.50 RJ  +   41.3  2.0    20.0  LSR  RADIO [l] AH L1/Hpm 0.91 10.3 ; 2.0 26.1
RXBoo           14 24 11.654 + 25 42 12.58 RJ  +    1.1  2.3    22.0  LSR  RADIO [l] AH L1/Hpm 1.4 20.3 ; 2.3 33.5
SCrB            15 21 23.946 + 31 22 02.35 RJ  +    2.0  1.0    18.0  LSR  RADIO [l] AH L1/Hpm 0.55 5.7 ; 1.0 10.2
V814Her         17 44 55.474 + 50 02 39.27 RJ  -   35.0  0.6    30.0  LSR  RADIO [l] AH L1/Hpm 0.53 9.4 ; 0.64 12.6
V1111Oph        18 37 19.26  + 10 25 42.2  RJ  -   30.0  1.4    40.0  LSR  RADIO [l] AH L1/2M 0.85 22.1 ; 1.4 32.8
RAql            19 06 22.255 + 08 13 46.87 RJ  +   47.3  2.2    21.0  LSR  RADIO [l] AH L1/Hpm 1.3 15.6 ; 2.2 25.9
HD179821        19 13 58.610 + 00 07 31.86 RJ  +  100.0  1.3    83.0  LSR  RADIO [l] AH L1/Hpm 0.83 42.4 ; 1.3 66.5
V1302Aql        19 26 48.10  + 11 21 16.7  RJ  +   78.0  1.8    90.0  LSR  RADIO [l] AH L1/2M 0.97 56.0 ; 1.8 99.9
GYAql           19 50 06.316 - 07 36 52.30 RJ  +   34.0  1.3    28.0  LSR  RADIO [l] AH L1/Hpm 1.1 20.6 ; 1.3 24.7
KiCyg           19 50 33.897 + 32 54 49.96 RJ  +   10.0  4.1    23.0  LSR  RADIO [l] AH L1/Hpm 2.8 42.7 ; 4.1 59.4
RRAql           19 57 36.032 - 01 53 12.18 RJ  +   28.0  1.2    19.0  LSR  RADIO [l] AH L1/Hpm 0.69 8.2 ; 1.2 13.8
VCyg            20 41 18.258 + 48 08 28.70 RJ  +   14.0  3.7    25.0  LSR  RADIO [l] AH L1/Hpm 2.3 40.7 ; 3.7 63.2
NMLCyg          20 46 25.54  + 40 06 59.4  RJ  +    1.0  3.1    67.0  LSR  RADIO [l] AH L1/2M 1.5 65.3 ; 3.1 141.4
NGC7027         21 07 01.598 + 42 14 10.02 RJ  +   26.0 12.9    50.0  LSR  RADIO [l] AH L1+ 7.8 194.2 ; 12.9 276.0
SCep            21 35 12.881 + 78 37 28.21 RJ  -   16.0  0.8    63.0  LSR  RADIO [l] AH L1/Hpm 0.84 31.3 ; 0.77 25.3
RCas            23 58 25.028 + 51 23 20.00 RJ  +   25.0  4.1    31.0  LSR  RADIO [l] AH L1/Hpm 2.3 36.4 ; 4.1 65.9
*
*
RAnd            00 24 01.926 + 38 34 36.80 RJ  -   14.5  2.1    23.0  LSR  RADIO [l] AH L2/Hpm 1.2 17.0 ; 2.1 26.4
GL67            00 27 41.10  + 69 38 51.5  RJ  -   27.0  1.2    34.0  LSR  RADIO [l] AH L2/2M 1.0 24.5 ; 1.2 27.1
RHor            02 53 53.001 - 49 53 22.16 RJ  +   38.0  3.4    15.0  LSR  RADIO [l] ?H L2/Hpm tbd ; 3.4 25.2
V384Per         03 26 29.51  + 47 31 48.6  RJ  -   16.3  2.1    33.0  LSR  RADIO [l] AH L2/2M 1.6 34.6 ; 2.1 44.2
IRC+60144       04 35 17.54  + 62 16 23.8  RJ  -   48.0  0.6    40.0  LSR  RADIO [l] AH L2/2M 0.74 19.3 ; 0.64 15.4
RDor            04 36 45.423 - 62 04 39.09 RJ  +    7.0  2.5    13.0  LSR  RADIO [l] L2/Hpm away?
V370Aur         05 43 49.68  + 32 42 06.2  RJ  -   31.0  1.3    52.0  LSR  RADIO [l] AH L2/2M 0.79 31.2 ; 1.3 47.0
GL865           06 04 00.05  + 07 25 52.0  RJ  +   44.0  1.8    32.0  LSR  RADIO [l] AH L2/2M 1.3 26.6 ; 1.0 20.2
APLyn           06 34 33.41  + 60 56 27.8  RJ  -   23.0  1.1    33.0  LSR  RADIO [l] AH L2/2M 0.68 16.1 ; 1.1 24.8
M1-7            06 37 20.955 + 24 00 35.38 RJ  -   11.0  1.3    56.0  LSR  RADIO [l] AH L2+ 1.0 32.3 ; 1.3 50.6
GMCMa           06 41 15.08  - 22 16 43.5  RJ  +   48.0  0.6    40.0  LSR  RADIO [l] H L2/2M 0.39 7.8 ; 0.57 15.0
GXMon           06 52 47.04  + 08 25 19.2  RJ  -    9.0  1.8    40.0  LSR  RADIO [l] AH L2+/2M 1.4 62.6 ; 1.8 52.9
HD56126         07 16 10.257 + 09 59 48.03 RJ  +   73.0  2.1    23.0  LSR  RADIO [l] AH L2/T 1.2 17.4 ; 2.1 28.0
GL5254          09 13 53.95  - 24 51 25.2  RJ  +    0.1  2.6    30.0  LSR  RADIO [l] AH L2/2M 2.3 42.4 ; 2.6 45.7
VHya            10 51 37.244 - 21 15 00.28 RJ  -   17.4  3.1    52.0  LSR  RADIO [l] AH L2/Hpm 2.7 60.0 ; 3.1 82.1
XHer            16 02 39.059 + 47 14 26.38 RJ  -   73.0  1.8    22.0  LSR  RADIO [l] AH L2/Hpm 1.3 9.6 ; 1.8 13.2
GL1922          17 07 58.11  - 24 44 31.2  RJ  -    3.0  2.1    40.0  LSR  RADIO [l] AH L2/2M 1.6 42.8 ; 2.1 52.5
GL2135          18 22 34.68  - 27 06 29.4  RJ  +   50.5  1.5    45.0  LSR  RADIO [l] AH L2/2M 1.3 42.2 ; 1.5 46.9
GL2199          18 35 46.80  + 05 35 50.6  RJ  +   34.0  0.9    33.0  LSR  RADIO [l] AH L2/2M 0.63 13.3 ; 0.87 18.4
V821Her         18 41 54.54  + 17 41 08.5  RJ  +    0.0  2.4    30.0  LSR  RADIO [l] AH L2/2M 1.9 38.1 ; 2.4 45.3
IRC+00365       18 42 24.87  - 02 17 27.2  RJ  +    4.5  1.1    73.0  LSR  RADIO [l] AH L2/2M 0.60 35.2 ; 1.1 58.8
IRC+10401       19 03 18.44  + 07 30 45.3  RJ  +   14.0  0.9    56.0  LSR  RADIO [l] AH L2/2M 0.74 30.4 ; 0.91 42.3
WAql            19 15 23.380 - 07 02 50.25 RJ  -   23.5  3.2    41.0  LSR  RADIO [l] AH L2/2Mpm 2.4 66.5 ; 3.2 84.4
IRC-10502       19 20 18.12  - 08 02 12.0  RJ  +   21.0  0.9    58.0  LSR  RADIO [l] AH L2/2M 0.59 23.7 ; 0.92 38.6
V1965Cyg        19 34 10.05  + 28 04 08.5  RJ  -   11.0  1.2    52.0  LSR  RADIO [l] AH L2/2M 0.87 32.7 ; 1.2 41.6
HD187885        19 52 52.697 - 17 01 50.33 RJ  +   20.0  0.7    75.0  LSR  RADIO [l] AH L2/T 0.50 10.5 ; 0.74 22.0
CRL2688         21 02 18.75  + 36 41 37.80 RJ  -   35.4  9.4    80.0  LSR  RADIO [l] AH L2+ 6.1 158.7 ; 9.4 247.9
Pi1Gru          22 22 44.252 - 45 56 52.82 RJ  -   10.0  2.1    33.0  LSR  RADIO [l] AH L2/Hpm 1.7 37.6 ; 2.1 33.4
HD235858        22 29 10.375 + 54 51 06.33 RJ  -   28.0  2.9    22.0  LSR  RADIO [l] AH L2/T 2.0 24.6 ; 2.9 35.7
LPAnd           23 34 27.53  + 43 33 01.2  RJ  -   17.0  3.7    30.0  LSR  RADIO [l] AH L2/2M 2.7 53.5 ; 3.7 71.0
*
*
GL190           01 17 51.62  + 67 13 55.4  RJ  -   39.0  1.3    37.0  LSR  RADIO [l] AH L3 1.0 22.3 ; 1.3 27.5
GL482           03 23 37.168 + 70 27 04.67 RJ  -   14.0  1.1    24.0  LSR  RADIO [l] AH L3/2Mpm 1.1 13.5 ; 1.1 16.1
TXCam           05 00 51.22  + 56 10 54.2  RJ  +    9.2  1.9    45.0  LSR  RADIO [l] AH L3/2M 1.4 38.1; 1.9 50.7
BXCam           05 46 44.29  + 69 58 24.2  RJ  -    2.0  0.8    45.0  LSR  RADIO [l] AH L3/2M 0.59 16.1 ; 0.80 23.6
GL1235          08 10 48.863 - 32 52 06.31 RJ  -   20.3  1.1    48.0  LSR  RADIO [l] AH L3+/2M 0.79 25.7 ; 1.1 35.3
CRL4211         15 11 41.45  - 48 19 59.0  RJ  -    3.7  2.8    41.0  LSR  RADIO [l] AH L3/2M 1.7 42.6 ; 2.8 73.0
IILup           15 23 05.07  - 51 25 58.7  RJ  -   15.0  2.4    44.0  LSR  RADIO [l] AH L3/2M 2.6 83.6 ; 2.4 79.2
IRC+20326       17 31 55.30  + 17 45 21.0  RJ  -    4.0  1.7    34.0  LSR  RADIO [l] AH L3/2M 1.5 31.3 ; 1.7 33.9
GL2155          18 26 05.84  + 23 28 46.7  RJ  +   60.0  1.6    32.0  LSR  RADIO [l] AH L3+ 1.3 25.4 ; 1.6 30.9
GL2477          19 56 48.45  + 30 44 02.6  RJ  +    5.0  1.7    48.0  LSR  RADIO [l] AH L3+ 0.61 17.6 ; 0.61 17.2
GL2494          20 01 09.059 + 40 55 38.95 RJ  +   29.0  1.2    48.0  LSR  RADIO [l] AH L3/2M 1.8 51.7 ; 1.2 35.1
V1300Aql        20 10 27.87  - 06 16 13.6  RJ  -   18.0  1.2    34.0  LSR  RADIO [l] AH L3/2M 1.2 25.6 ; 1.2 25.2
GL2686          20 59 09.60  + 27 26 38.8  RJ  -    1.0  0.8    51.0  LSR  RADIO [l] AH L3/2M 0.66 24.7 ; 0.79 28.3
21282+5050      21 29 58.47  + 51 04 00.3  RJ  +   18.0  5.0    37.0  LSR  RADIO [l] AH L3/2M 2.8 58.2 ; 5.0 96.1
21318+5631      21 33 22.98  + 56 44 35.0  RJ  +    2.0  1.1    37.0  LSR  RADIO [l] AH L3 0.96 18.0 ; 1.1 23.4
V384Cep         22 25 53.48  + 60 20 43.5  RJ  -    7.0  0.9    65.0  LSR  RADIO [l] AH L3/2M 0.59 28.2 ; 0.89 40.3
GL3068          23 19 12.600 + 17 11 32.99 RJ  -   31.0  3.3    32.0  LSR  RADIO [l] AH L3/2Mpm 2.5 48.1 ; 3.3 58.7
23304+6147      23 32 44.79  + 62 03 49.1  RJ  -   17.0  0.6    40.0  LSR  RADIO [l] H L3/2M 0.43 6.9 ; 0.62 11.4
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*
* Further sources useful for spectral-line fivepointing
* at CO:2-1  ( and at CO:3-2 where noted).
* Sources identified by Thomas Lowe (2003).
* RFor thru TXPsc added 29 Mar 2004
*
RFor            02 29 15.320 - 26 05 55.72 RJ  -    2.0  0.6    37.0  LSR  RADIO [l] AH Hippm 2-1 0.50 13.0 ; 0.64 17.4
WOri            05 05 23.730 + 01 10 39.43 RJ  -    2.0  0.8    25.0  LSR  RADIO [l] H Hippm 0.36 5.9 ; 0.79 13.4
UHya            10 37 33.323 - 13 23 04.99 RJ  -   31.0  2.3    17.0  LSR  RADIO [l] AH Hippm 1.4 14.2 ; 2.3 23.2
YCVn            12 45 07.823 + 45 26 25.15 RJ  +   21.0  1.1    21.0  LSR  RADIO [l] AH Hippm 0.67 8.6 ; 1.1 13.9
RYDra           12 56 25.949 + 65 59 39.64 RJ  -    5.0  0.7    22.0  LSR  RADIO [l] H Hippm 0.22 3.0 ; 0.67 9.6
VCrB            15 49 31.318 + 39 34 17.70 RJ  -   99.0  0.5    17.0  LSR  RADIO [l] H Hippm 0.46 5.2 ; 0.55 5.8
TDra            17 56 23.239 + 58 13 06.46 RJ  -   14.0  0.9    29.0  LSR  RADIO [l] AH Hippm 0.71 14.3 ; 0.90 18.2
RVCyg           21 43 16.319 + 38 01 02.85 RJ  +   17.0  0.7    31.0  LSR  RADIO [l] H Hippm 0.39 8.5 ; 0.66 13.5
TXPsc           23 46 23.517 + 03 29 12.52 RJ  +   13.0  1.0    20.0  LSR  RADIO [l] AH Hippm 0.56 5.6 ; 1.0 7.4
*
GL1822          16 06 08.363 -30 49 33.99  RJ  -    3.0  0.5    35.0  LSR  RADIO [l]    2M 0.45 ; 0.54
*
* and 1 source observed at CO:3-2 by S.Ramstedt (m07ai05)
*
RCyg            19 36 49.386 + 50 11 59.31 RJ  -   17.0  1.0    24.0  LSR  RADIO [l] AH pm 0.64 9.6 ; 1.0 15.0
*
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*
* Loup et al. sources observed for M13BN01 and M14AN01 which are strong enough to be added:
*
KUAnd           00 06 52.740 + 43 05 02.18 RJ  -   21.0  1.0    42.0  LSR  RADIO [l] AH 0.84 22.7 ; 1.0 28.6
SCas            01 19 41.986 + 72 36 40.44 RJ  -   29.0  1.2    44.0  LSR  RADIO [l] AH pm 0.70 21.2 ; 1.2 35.3
GL278           01 58 44.393 + 45 26 06.92 RJ  -    2.0  2.1    22.0  LSR  RADIO [l] AH pm 1.6 13.9 ; 2.1 17.2
GL341           02 33 00.34  + 58 02 06.2  RJ  +    8.0  1.3    31.0  LSR  RADIO [l] AH 0.76 14.7 ; 1.3 25.8
Betelgeuse      05 55 10.336 + 07 24 25.62 RJ  +    4.0  1.5    31.0  LSR  RADIO [l] AH pm 0.55 12.3 ; 1.5 33.2
GL971           06 36 54.24  + 03 25 28.7  RJ  +    2.0  1.2    38.0  LSR  RADIO [l] AH 0.78 13.9 ; 1.2 21.4
YLyn            07 28 11.618 + 45 59 26.18 RJ  +    0.0  1.0    18.0  LSR  RADIO [l] H pm 0.56 6.9 ; 1.0 13.2
RSCnc           09 10 38.783 + 30 57 46.74 RJ  +    7.0  3.4    17.0  LSR  RADIO [l] AH pm 2.3 15.4 ; 3.4 21.2
08074-3615      08 09 20.256 - 36 24 26.76 RJ  +    7.0  1.0    51.0  LSR  RADIO [l] AH 0.80 17.5 ; 1.0 22.0
IWHya           09 45 15.24  - 22 01 45.3  RJ  +   40.0  0.8    29.0  LSR  RADIO [l] AH 0.69 12.6 ; 0.82 16.3
IRC-10236       10 17 00.556 - 14 39 30.07 RJ  +    2.0  2.5    20.0  LSR  RADIO [l] AH pm 1.9 25.5 ; 2.5 32.2
RCrt            11 00 33.819 - 18 19 29.62 RJ  +   11.0  1.4    25.0  LSR  RADIO [l] AH pm 0.81 14.9 ; 1.4 25.8
HD102608        11 48 39.209 - 35 59 13.03 RJ  -    4.0  0.8    17.0  LSR  RADIO [l] H pm 0.47 4.8 ; 0.82 10.4
SWVir           13 14 04.343 - 02 48 25.18 RJ  -   12.0  1.0    18.0  LSR  RADIO [l] AH pm 1.5 18.7 ; 0.96 11.3
RHya            13 29 42.711 - 23 16 52.55 RJ  -   10.0  2.5    19.0  LSR  RADIO [l] AH pm 0.91 8.2 ; 2.5 28.6
OH338.1+6.4     16 14 03.154 - 42 13 03.81 RJ  -   82.0  1.2    30.0  LSR  RADIO [l] AH 1.5 29.4 ; 1.2 24.1
16594-4656      17 03 10.08 -  47 00 27.7  RJ  -   26.0  2.4    35.0  LSR  RADIO [l] AH 1.7 36.6 ; 2.4 51.3
GL6815S         17 18 19.85  - 32 27 21.6  RJ  +   13.0  1.1    48.0  LSR  RADIO [l] H 0.57 12.8 ; 1.1 23.2
GL5379          17 44 24.01  - 31 55 35.5  RJ  -   23.0  1.9    52.0  LSR  RADIO [l] AH 1.1 33.1 ; 1.9 58.6
GL5552          19 03 02.409 - 39 42 55.3  RJ  +   15.0  1.2    60.0  LSR  RADIO [l] AH 1.1 32.6 ; 1.2 34.6
RVAqr           21 05 51.74  - 00 12 42.0  RJ  +    1.0  1.1    30.0  LSR  RADIO [l] AH 0.83 19.0 ; 1.1 26.5
TCep            21 09 31.646 + 68 29 26.43 RJ  -    3.0  1.5    11.0  LSR  RADIO [l] H pm 0.60 5.0 ; 1.5 9.8
V1426Cyg        21 34 07.480 + 39 04 15.89 RJ  -    5.0  1.5    39.0  LSR  RADIO [l] AH 0.93 18.2 ; 1.5 28.5
EPAqr           21 46 31.876 - 02 12 45.60 RJ  -   35.0  4.1    26.0  LSR  RADIO [l] AH pm 2.4 14.8 ; 4.1 23.3
GL3099          23 28 17.107 + 10 54 37.35 RJ  +   46.0  1.5    21.0  LSR  RADIO [l] AH 1.4 18.2 ; 1.5 19.3
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
*           MISCELLANEOUS SOURCES
*
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
HOLO            92 55 09.9   + 08 34 05.00 AZ    n/a      n/a    n/a  LSR  RADIO [c] Position for holography
* -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
