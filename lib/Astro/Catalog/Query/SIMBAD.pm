package Astro::Catalog::Query::SIMBAD;

=head1 NAME

Astro::Catalog::Query::SIMBAD - A query request to the SIMBAD database

=head1 SYNOPSIS

    $sim = new Astro::Catalog::Query::SIMBAD(
            RA        => $ra,
            Dec       => $dec,
            Radius    => $radius,
            Target    => $target,
        );

    my $catalog = $sim->querydb();

=head1 DESCRIPTION

The module is an object orientated interface to the online SIMBAD
database. Designed to return information on a single object.

Target name overrides RA/Dec.

The object will by default pick up the proxy information from the
HTTP_PROXY and NO_PROXY environment variables, see the LWP::UserAgent
documentation for details.

See L<Astro::Catalog::Query> for the catalog-independent methods.

=cut

use strict;
use warnings;
use base qw/Astro::Catalog::Transport::REST/;

use Carp;

use Astro::Coords;
use Astro::Coords::Angle;
use Astro::Catalog;
use Astro::Catalog::Item;
use URI::Escape;

our $VERSION = '4.38';

=begin __PRIVATE_METHODS__

=head2 Private methods

These methods are for internal use only.

=over 4

=item B<_default_remote_host>

=cut

sub _default_remote_host {
    return 'simbad.cds.unistra.fr';
}

=item B<_default_url_scheme>

=cut

sub _default_url_scheme {
    return 'https';
}

=item B<_default_url_path>

=cut

sub _default_url_path {
    return 'simbad/sim-script?';
}

# SIMBAD documentation:
# Script queries: https://simbad.u-strasbg.fr/Pages/guide/sim-url.htx#script
# Output format: https://simbad.cds.unistra.fr/guide/sim-fscript.htx#Formats

our @_columns = qw/name type ra dec pmra pmdec plx spectype/;

sub _translate_options {
    my $self = shift;

    my $script = <<"END_SCRIPT";
output console=off script=off
format object "%IDLIST(1) | %OTYPE | %COO(:;A;ICRS;;) | %COO(:;D;ICRS;;) | %PM(A) | %PM(D) | %PLX(V) | %SP(S)"
END_SCRIPT

    my $object = $self->query_options('object');
    if (defined $object) {
        $script .= "query id $object";
    }
    else {
        die "No query options";
    }

    return (
        script => uri_escape($script),
    );
}

=item B<_get_allowed_options>

Returns a hash with keys, being the internal options supported
by this subclass, and values being the key name actually required
by the remote system (and to be included in the query).

=cut

sub _get_allowed_options {
    my $self = shift;
    return (
        ra => 'ra',
        dec => 'dec',
        object => 'Ident',
        radmax => 'Radius',
        nout => "output.max",
        bibyear1 => "Bibyear1",
        bibyear2 => "Bibyear2",
        _nbident => "NbIdent",
        _catall => "o.catall",
        _mesdisp => "output.mesdisp",

        radunits => "Radius.unit", # arcsec, arcmin or deg

        # These should not be published
        # Since we need to switch to Astro::Coords
        _coordframe => "CooFrame",  # FK5 or FK4
        _coordepoch => "CooEpoch",  # 2000
        _coordequi  => "CooEqui",   # 2000

        _frame1 => "Frame1",
        _equi1 => "Equi1",
        _epoch1 => "Epoch1",

        _frame2 => "Frame2",
        _equi2 => "Equi2",
        _epoch2 => "Epoch2",

        _frame3 => "Frame3",
        _equi3 => "Equi3",
        _epoch3 => "Epoch3",
    );
}

=item B<_get_default_options>

Get the default query state.

=cut

sub _get_default_options {
    return  (
        # Target information
        ra => undef,
        dec => undef,
        object => undef,
        radmax => 0.1,
        radunits => "arcmin", # For consistency
        nout => "all",

        _coordepoch => "2000",
        _coordequi  => "2000",
        _coordframe => "FK5",
        _nbident    => "around",
        _nbident    => "around",
        _catall     => "on",
        _mesdisp    => "A",

        bibyear1    => 1983,
        bibyear2    => 2003,

        # Frame 1, 2 and 3
        # Frame 1 FK5 2000/2000
        _frame1      => "FK5",
        _equi1       => "2000.0",
        _epoch1      => "2000.0",

        # Frame 2 FK4 1950/1950
        _frame2      => "FK4",
        _equi2       => "1950.0",
        _epoch2      => "1950.0",

        # Frame 3 Galactic
        _frame3      => "G",
        _equi3       => "2000.0",
        _epoch3      => "2000.0",
    );
}

=item B<_parse_query>

Private function used to parse the results returned in a SIMBAD query.
Should not be called directly. Instead use the querydb() assessor
method to make and parse the results.

    $cat = $q->_parse_query();

Returns an Astro::Catalog object.

=cut

sub _parse_query {
    my $self = shift;

    # get a local copy of the current BUFFER
    my @buffer = split /\n/, $self->{BUFFER};
    chomp @buffer;

    # create an Astro::Catalog object to hold the search results
    my $catalog = new Astro::Catalog();

    # loop round the returned buffer
    # ...and stuff the contents into Object objects
    foreach my $line (@buffer) {
        next unless $line;

        # create a temporary place holder object
        my $star = new Astro::Catalog::Item();

        # split each line using the "pipe" symbol separating
        # the table columns
        my @separated = split /\s*\|\s*/, $line;
        my %column;  @column{@_columns} = map {/^~$/ ? undef : $_} @separated;

        # FRAME
        # grab the current co-ordinate frame from the query object itself
        # Assume J2000 for now.

        # NAME
        # get the object name from the same section
        my $name = $column{'name'};

        # push it into the object
        $star->id($name);

        # TYPE
        my $type = $column{'type'};

        # dump leading spaces
        $type =~ s/^\s+//g;

        # push it into the object
        $star->startype( $type );

        # RA
        # remove leading spaces
        my $ra = $column{'ra'};
        $ra =~ s/^\s+//g;

        # DEC
        my $dec = $column{'dec'};

        # PM & Parallax
        my %extra = ();
        if (defined $column{'pmra'} and defined $column{'pmdec'}) {
            # Convert to arcseconds, with RA as coordinate angle.

            my $decang = Astro::Coords::Angle->new($dec, units => 's');

            $extra{'pm'} = [
                $column{'pmra'} / (1000.0 * cos($decang->radians)),
                $column{'pmdec'} / 1000.0,
            ];
        }

        if (defined $column{'plx'} ) {
            $extra{'parallax'} = $column{'plx'} / 1000.0;
        }

        # Store the coordinates
        $star->coords(new Astro::Coords(
                name => $name,
                ra => $ra,
                dec => $dec,
                type => "J2000",
                units => "s",
                %extra,
        ));

        # SPECTRAL TYPE
        my $spectral = $column{'spectype'};

        # remove leading and trailing spaces
        $spectral =~ s/^\s+//g;
        $spectral =~ s/\s+$//g;

        # push it into the object
        $star->spectype($spectral);

        # Add the target object to the Astro::Catalog::Item object
        $catalog->pushstar( $star );
        }

    # Field centre?

    # return the catalog
    return $catalog;
}

1;

__END__

=end __PRIVATE_METHODS__

=head1 SEE ALSO

L<Astro::Catalog>, L<Astro::Catalog::Item>, L<Astro::Catalog::Query>.

Derived from L<Astro::SIMBAD> on CPAN.

=head1 COPYRIGHT

Copyright (C) 2001-2003 University of Exeter. All Rights Reserved.
Some modifications copyright (C) 2003 Particle Physics and Astronomy
Research Council. All Rights Reserved.

This program was written as part of the eSTAR project and is free software;
you can redistribute it and/or modify it under the terms of the GNU Public
License.

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>,
Tim Jenness E<lt>tjenness@cpan.orgE<gt>

=cut
