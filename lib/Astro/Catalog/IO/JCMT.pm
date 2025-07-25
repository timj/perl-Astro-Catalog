package Astro::Catalog::IO::JCMT;

=head1 NAME

Astro::Catalog::IO::JCMT - JCMT catalog I/O for Astro::Catalog

=head1 SYNOPSIS

    $cat = Astro::Catalog::IO::JCMT->_read_catalog(\@lines);
    $arrref = Astro::Catalog::IO::JCMT->_write_catalog($cat, %options);
    $filename = Astro::Catalog::IO::JCMT->_default_file();

=head1 DESCRIPTION

This class provides read and write methods for catalogs in the JCMT
pointing catalog format. The methods are not public and should, in general,
only be called from the C<Astro::Catalog> C<write_catalog> and C<read_catalog>
methods.

=cut

use warnings;
use warnings::register;
use Carp;
use strict;

use Astro::Telescope;
use Astro::Coords;
use Astro::Catalog;
use Astro::Catalog::Item;

use base qw/Astro::Catalog::IO::ASCII/;

our $VERSION = '4.38';
our $DEBUG   = 0;

# Name must be limited to 15 characters on write
use constant MAX_SRC_LENGTH => 15;

# Default location for a JCMT catalog
my $defaultCatalog = "/local/progs/etc/poi.dat";

# Planets appended to the catalog
my @PLANETS = qw/mercury mars uranus saturn jupiter venus neptune/;

=over 4

=item B<clean_target_name>

Method to take a general target name and clean it up
so that it is suitable for writing in a JCMT source catalog.
This routine is used by the catalog writing code but can also
be used publically in order to make sure that a target name
to be written to the catalog is guaranteed to match that used
in another location (e.g. when writing an a document to accompany
the catalog which refers to targets within it).

The source name can be truncated.

    $cleaned = Astro::Catalog::IO::JCMT->clean_target_name($dirty);

Will return undef if the argument is not defined.

Punctuation such as "," and ";" are replaced with underscores.
".", "()" and "+-" are allowed.

=cut

sub clean_target_name {
    my $class = shift;
    my $dirty = shift;
    return unless defined $dirty;

    # Remove spaces [compress]
    $dirty =~ s/\s+//g;

    # Remove disallowed characters
    # and replace with dashes
    $dirty =~ s/[,;:'"`]/-/g;

    # Truncate it to the allowed length
    # Name must be limited to MAX_SRC_LENGTH characters
    $dirty = substr($dirty, 0, MAX_SRC_LENGTH);

    # Return the cleaned name
    return $dirty;
}


=item B<_default_file>

Returns the location of the default JCMT pointing catalog at the
JCMT itself. This is purely for convenience of the caller when they
are at the JCMT and wish to use the default catalog without having
to know explicitly where it is.

    $filename = Astro::Catalog::IO::JCMT->_default_file();

Returns empty list/undef if the file is not available.

If the environment variable ASTRO_CATALOG_JCMT is defined (and exists)
this will be used as the default.

=cut

sub _default_file {
    my $class = shift;
    return $ENV{ASTRO_CATALOG_JCMT}
        if (exists $ENV{ASTRO_CATALOG_JCMT} && -e $ENV{ASTRO_CATALOG_JCMT});
    return (-e $defaultCatalog ? $defaultCatalog : ());
}

=item B<_read_catalog>

Parses the catalog lines and returns a new C<Astro::Catalog>
object containing the catalog entries.

    $cat = Astro::Catalog::IO::JCMT->_read_catalog(\@lines, %options);

Supported options (with defaults) are:

    telescope => Name of telescope to associate with each coordinate entry
                 (defaults to JCMT). If the telescope option is specified
                 but is undef or empty string, no telescope is used.

    incplanets => Append planets to catalog entries (default is true)

    inccomments => Read comment lines into misc entries (default: false)

=cut

sub _read_catalog {
    my $class = shift;
    my $lines = shift;

    # Default options
    my %defaults = (
        telescope => 'JCMT',
        incplanets => 1,
        inccomments => 0,
        respacecomments => 1,
    );

    my %options = (%defaults, @_);

    croak "Must supply catalog contents as a reference to an array"
        unless ref($lines) eq 'ARRAY';

    # Create a new telescope to associate with this
    my $tel;
    $tel = new Astro::Telescope($options{telescope})
        if $options{telescope};

    # Go through each line and parse it
    # and store in the array if we had a successful read
    my $parse_buff = $options{'inccomments'} ? {} : undef;
    my @stars = map {$class->_parse_line($_, $tel, $parse_buff, \%options);} @$lines;

    $stars[-1]->misc->{'_jcmt_com_after'} = delete $parse_buff->{'comments'}
        if ((defined $parse_buff)
            and (scalar @stars)
            and (exists $parse_buff->{'comments'}));

    # Add planets if required
    if ($options{incplanets}) {
        # create coordinate objects for the planets
        my @planets = map {new Astro::Coords(planet => $_)} @PLANETS;

        # And associate a telescope
        if ($tel) {
            for (@planets) {
                $_->telescope($tel);
            }
        }

        # And create the star objects
        push(@stars, map {new Astro::Catalog::Item(
            field => 'JCMT',
            id => $_->name,
            coords => $_,
            comment => 'Added automatically',
            )} @planets);
    }

    # Create the catalog object
    return new Astro::Catalog(
        Stars => \@stars,
        Origin => 'JCMT',
    );
}

=item B<_write_catalog>

Write the catalog to an array and return it. Returning a reference to
an array provides more flexibility to the caller.

    $ref = Astro::Catalog::IO::JCMT->_write_catalog($cat, %options);

Spaces are removed from source names. The contents of the catalog
are sanity checked.

Supported options (with defaults) are:

=over 4

=item incheader

Add a comment header to the start of the catalog.  [default: true]

=item removeduplicates

Check for duplicates.  Remove if the coordinates match.  Add suffix
to disambiguate otherwise.  [default: true]

=back

=cut

sub _write_catalog {
    my $class = shift;
    my $cat = shift;

    # Default options
    my %defaults = (
        incheader => 1,
        removeduplicates => 1,
    );

    my %options = (%defaults, @_);

    # Would make more sense to use the array ref here
    my @sources = $cat->stars;

    # Counter for unknown targets
    my $unk = 1;

    # Hash for storing target information
    # so that we can search for duplicates
    my %targets;

    # Create hash of all unique target names present
    # after cleaning. We need this so that we can make sure
    # a generated name derived from a duplication (with target mismatch)
    # does not generate a name that already existed explicitly.
    my %allnames = map {$class->clean_target_name($_->coords->name), undef}
        @sources;

    # Loop over each source and extract catalog information
    # Make sure that we remove unique entries
    # BUT THAT WE RETAIN THE ORDER OF THE SOURCES IN THE CATALOG
    # Hence an array for the information
    my @processed;
    for my $star (@sources) {
        # Extract the coordinate object
        my $src = $star->coords;

        # Get the name but do not deal with undef yet
        # in case the type is not valid
        my $name = $src->name;

        # Somewhere to store the extracted information
        my %srcdata;

        # Store the name (stripped of spaces) and
        # treat srcdata{name} as the primary name from here on
        $srcdata{name} = $class->clean_target_name($name);

        # Store a comment
        $srcdata{comment} = $star->comment;

        # prepopulate the default velocity settings
        $srcdata{rv}    = 'n/a';
        $srcdata{vdefn}  = 'RADIO';
        $srcdata{vframe} = 'LSR';

        # Default proper motion and parallax.
        $srcdata{'pm1'} = 'n/a';
        $srcdata{'pm2'} = 'n/a';
        $srcdata{'parallax'} = 'n/a';

        # Get the miscellaneous data.
        my $misc = $star->misc;
        if (defined $misc) {
            $srcdata{vrange} = ((defined $misc->{'velocity_range'})
                ? sprintf("%s", $misc->{'velocity_range'})
                : "n/a");
            $srcdata{flux850} = ((defined $misc->{'flux850'})
                ?  sprintf("%s", $misc->{'flux850'})
                : "n/a" );
        }
        else {
            $srcdata{vrange} = "n/a";
            $srcdata{flux850} = "n/a";
        }

        foreach (qw/_jcmt_com_before _jcmt_com_after/) {
            $srcdata{$_} = $misc->{$_} if exists $misc->{$_};
        }

        # Get the type of source
        my $type = $src->type;
        if ($type eq 'RADEC') {
            $srcdata{system} = "RJ";

            # Need to get the space separated RA/Dec and the sign
            $srcdata{long} = $src->ra2000(format => 'array');
            $srcdata{lat} = $src->dec2000(format => 'array');

            # Get the velocity information
            my $rv = $src->rv;
            if ($rv) {
                my $vdefn = $src->vdefn;
                $srcdata{rv}    = ($vdefn eq 'REDSHIFT') ? $src->redshift : $rv;
                $srcdata{vdefn}  = $vdefn;
                $srcdata{vframe} = $src->vframe;

                # JCMT compatibility
                $srcdata{vframe} = "LSR" if $srcdata{vframe} eq 'LSRK';

            }

            my $parallax = $src->parallax;
            my @pm = $src->pm;
            if (scalar @pm) {
                if (not $parallax) {
                    my $errname = (defined $srcdata{name} ? $srcdata{name} : "<undefined>");
                    warnings::warnif "Proper motion for target $errname specified without parallax";
                }
                $srcdata{'pm1'} = $pm[0] * 1000.0;
                $srcdata{'pm2'} = $pm[1] * 1000.0;
            }
            if ($parallax) {
                $srcdata{'parallax'} = $parallax * 1000.0;
            }

        }
        elsif ($type eq 'PLANET') {
            # Planets are not supported in catalog form. Skip them
            next;

        }
        elsif ($type eq 'FIXED') {
            $srcdata{system} = "AZ";

            $srcdata{long} = $src->az(format => 'array');
            $srcdata{lat} = $src->el(format => 'array');

            # Need to remove + sign from long/AZ since we are not expecting
            # it in RA/DEC. This is probably a bug in Astro::Coords
            shift(@{$srcdata{long}}) if $srcdata{long}->[0] eq '+';

        }
        else {
            my $errname = (defined $srcdata{name} ? $srcdata{name} : "<undefined>");
            warnings::warnif "Coordinate of type $type for target $errname not supported in JCMT catalog files\n";
            next;
        }

        # Generate a name if not defined
        if (!defined $srcdata{name}) {
            $srcdata{name} = "UNKNOWN$unk";
            $unk++;
        }

        # See if we already have this source and that it is really the
        # same source Note that we do not see whether this name is the
        # same as one of the derived names. Eg if CRL618 is in the
        # pointing catalog 3 times with identical coords and we add a
        # new CRL618 with different coords then we trigger 3 warning
        # messages rather than 1 because we do not check that CRL618_2 is
        # the same as CRL618_1

        # Note that velocity specification is included in this comparison

        if ($options{'removeduplicates'} and exists $targets{$srcdata{name}}) {
            my $previous = $targets{$srcdata{name}};

            # Create stringified form of previous coordinate with same name
            # and current coordinate
            my $prevcoords = join(" ",@{$previous->{long}},@{$previous->{lat}},
                    $previous->{rv}, $previous->{vdefn}, $previous->{vframe});
            my $curcoords = join(" ",@{$srcdata{long}},@{$srcdata{lat}},
                    $srcdata{rv}, $srcdata{vdefn}, $srcdata{vframe});

            if ($prevcoords eq $curcoords) {
                # This is the same target so we can ignore it
            }
            else {
                # Make up a new name. Use a counter for this.
                my $oldname = $srcdata{name};

                # loop for 100 times
                my $count;
                while (1) {
                    # protection loop
                    $count++;

                    # Try to construct a new name based on the counter.
                    my $suffix = "_$count";

                    # Abort if we have gone round too many times
                    if ($count > 100) {
                        $srcdata{name} = substr($oldname, 0, int(MAX_SRC_LENGTH / 2)) .
                            int(rand(10000) + 1000);
                        warn "Uncontrollable looping (or unfeasibly large number of duplicate sources with different coordinates). Panicked and generated random source name of $srcdata{name}\n";
                        last;
                    }

                    # Assume the old name will do fine
                    my $root = $oldname;

                    # Do not want to truncate the _XX off the end later on
                    if (length($oldname) > MAX_SRC_LENGTH - length($suffix)) {
                        # This may well be confusing but we have no choice. Since
                        # _XX is unique the only time we will get a name clash by
                        # simply chopping the string is if we have a duplicate
                        # that is too long along with a target name that includes
                        # _XX amd matches the truncated source name!
                        $root = substr($oldname, 0, (MAX_SRC_LENGTH - length($suffix)) );
                    }

                    # Form the new name
                    my $newname = $root . $suffix;

                    # check to see if this name is in the existing target list
                    unless ((exists $allnames{$newname}) or (exists $targets{$newname})) {
                        # Store it in the targets array and exit loop
                        $srcdata{name} = $newname;
                        last;
                    }
                }

                # different target
                warn "Found target with the same name [$oldname] but with different coordinates, renaming it to $srcdata{name}\n";

                $targets{$srcdata{name}} = \%srcdata;

                # Store it in the array
                push @processed, \%srcdata;
            }
        }
        else {
            # Store in hash for easy lookup for duplicates
            $targets{$srcdata{name}} = \%srcdata;

            # Store it in the array
            push @processed, \%srcdata;
        }
    }

    # Output array for new catalog lines
    my @lines;

    if ($options{'incheader'}) {
        # Write a header
        push @lines, "*\n";
        push @lines, "* Catalog written automatically by class ". __PACKAGE__ ."\n";
        push @lines, "* on date " . gmtime . "UT\n";
        push @lines, "* Origin of catalog: ". $cat->origin ."\n";
        push @lines, "*\n";
    }

    # Now need to go through the targets and write them to disk
    for my $src (@processed) {
        if (exists $src->{'_jcmt_com_before'}) {
            push @lines, '*' . $_ foreach @{$src->{'_jcmt_com_before'}};
        }

        my $name    = $src->{name};
        my $long    = $src->{long};
        my $lat     = $src->{lat};
        my $system  = $src->{system};
        my $comment = $src->{comment};
        my $rv      = $src->{rv};
        my $vdefn   = $src->{vdefn};
        my $vframe  = $src->{vframe};
        my $vrange  = $src->{vrange};
        my $flux850 = $src->{flux850};
        my $pm1     = $src->{'pm1'};
        my $pm2     = $src->{'pm2'};
        my $px      = $src->{'parallax'};

        $comment = '' unless defined $comment;

        # Velocity can not easily be done with a sprintf since it can be either
        # a string or a 2 column number
        if ($vdefn ne 'REDSHIFT') {
            $rv  = ' ' . _format_value($rv, '%6.1f', '  n/a   ', 1);
        }
        else {
            $rv  = _format_value($rv, '%8.6f', '  n/a   ', 2);
        }

        # Similarly format proper motion and parallax.
        $pm1 = _format_value($pm1, '%8.3f', '   n/a    ', 1);
        $pm2 = _format_value($pm2, '%8.3f', '   n/a    ', 1);
        $px  = _format_value($px,  '%8.4f', '  n/a   ', 0);

        # Name must be limited to MAX_SRC_LENGTH characters
        # [this should be taken care of by clean_target_name but
        # if we have appended _X....
        $name = substr($name,0,MAX_SRC_LENGTH);

        # Maybe shift flux by 1 space to align decimal point in
        # 1dp values with that in 2dp values and also middle of n/a.
        $flux850 .= ' ' if $flux850 =~ /(?:\.\d|n\/a)$/ and 5 > length $flux850;

        push @lines, sprintf(
            "%-" . MAX_SRC_LENGTH .  "s %02d %02d %06.3f %1s %02d %02d %05.2f %2s %s %5s  %5s  %-4s %5.5s %s %s %s %s\n",
            $name, @$long, @$lat, $system,
            $rv, $flux850, $vrange, $vframe, $vdefn,
            $pm1, $pm2, $px,
            $comment);

        if (exists $src->{'_jcmt_com_after'}) {
            push @lines, '*' . $_ foreach @{$src->{'_jcmt_com_after'}};
        }
    }

    return \@lines;
}

=item B<_format_value>

Format a value for inclusion in a JCMT format catalog.

C<$signed> can be 1 (sign plus space) or 2 (sign and no space).

=cut

sub _format_value {
    my ($val, $fmt, $na, $signed) = @_;

    if (lc($val) eq 'n/a') {
        return $na;
    }

    my $sign = ($val >= 0 ? '+' : '-');
    $val = abs($val);

    unless ($signed) {
        warnings::warnif "Unsigned value is negative" unless $sign eq '+';
        return sprintf($fmt, $val);
    }
    return $sign . ($signed == 2 ? '' : ' ') . sprintf($fmt, $val);
}

=item B<_parse_line>

Parse a line from a JCMT format catalog and return a corresponding
C<Astro::Catalog::Item> object. Returns empty list if the line can not
be parsed or refers to a comment line (so that map can be used in the
caller).

    $star = Astro::Catalog::IO::JCMT->_parse_line($line, $tel, \%status_buffer, \%options);

where C<$line> is the line to be parsed and (optional) C<$tel>
is an C<Astro::Telescope> object to be associated with the
coordinate objects.

A reference to a hash can be provided to track parsing status between lines.
This is currently used to store comments read from the catalog.

The line is parsed using a pattern match.

=cut

sub _parse_line {
    my $class = shift;
    my $line = shift;
    my $tel = shift;
    my $parse_buff = shift;
    my $options = shift;
    chomp $line;

    # Skip commented and blank lines
    return if ($line =~ /^\s*$/);
    if ($line =~ s/^\s*[\*\%]//) {
        push @{$parse_buff->{'comments'}}, $line if $parse_buff;
        return;
    }

    # Use a pattern match parser
    my @match = ($line =~ m/
        ^(.*?)  # Target name (non greedy)
        \s*   # optional trailing space
        (\d{1,2}) # 1 or 2 digits [RA:h] [greedy]
        \s+       # separator
        (\d{1,2}) # 1 or 2 digits [RA:m]
        \s+       # separator
        (\d{1,2}(?:\.\d*)?) # 1|2 digits opt .fraction [RA:s]
        # no capture on fraction
        \s+
        ([+-]?\s*\d{1,2}) # 1|2 digit [dec:d] inc sign
        \s+
        (\d{1,2}) # 1|2 digit [dec:m]
        \s+
        (\d{1,2}(?:\.\d*)?) # arcsecond (optional fraction)
        # no capture on fraction
        \s+
        (RJ|RB|GA|AZ) # coordinate type
        # most everything else is optional
        # [sign]velocity, flux,vrange,vel_def,frame,comments
        \s*
        (n\/a|[+-]\s*\d+(?:\.\d*)?)?  # velocity [8]
        \s*
        (n\/a|\d+(?:\.\d*)?)?    # flux [9]
        \s*
        (n\/a|\d+(?:\.\d*)?)?    # vel range [10]
        \s*
        ([\w\/]+)?               # vel frame [11]
        \s*
        ([\w\/]+)?               # vel defn [12]
        \s*
        (n\/a|[+-]\s*\d+(?:\.\d*)?)?  # pm1 [13]
        \s*
        (n\/a|[+-]\s*\d+(?:\.\d*)?)?  # pm2 [14]
        \s*
        (n\/a|\d+(?:\.\d*)?)?    # parallax [15]
        \s*
        (.*)$                    # comment [16]
        /xi);

    # Abort if we do not have matches for the first 8 fields
    for (0..7) {
        return unless defined $match[$_];
    }

    # Read the values
    my $target = $match[0];
    my $ra = join ":", @match[1..3];
    my $dec = join ":", @match[4..6];
    $dec =~ s/\s//g; # remove  space between the sign and number
        my $epoc = $match[7];

    print "Creating a new source in _parse_line: $target\n" if $DEBUG;

    # need to translate JCMT epoch to normal epoch
    my %coords;
    $epoc = uc($epoc);
    $coords{name} = $target;
    if ($epoc eq 'RJ') {
        $coords{ra} = $ra;
        $coords{dec} = $dec;
        $coords{type} = "j2000"
    }
    elsif ($epoc eq 'RB') {
        $coords{ra} = $ra;
        $coords{dec} = $dec;
        $coords{type} = "b1950";
    }
    elsif ($epoc eq 'GA') {
        $coords{long} = $ra;
        $coords{lat}  = $dec;
        $coords{type} = "galactic";
    }
    elsif ($epoc eq 'AZ') {
        $coords{az}   = $ra;
        $coords{el}   = $dec;
        $coords{units} = 'sexagesimal';
    }
    else {
        warnings::warnif "Unknown coordinate type: '$epoc' for target $target. Ignoring line.";
        return;
    }

    # catalog comments are space delimited
    my $ccol = 16;
    my $cat_comm = (defined $match[$ccol] ? $match[$ccol] : '');

    # Replace multiple spaces in comment with single space
    $cat_comm =~ s/\s+/ /g if $options->{'respacecomments'};

    # velocity
    $coords{vdefn} = "RADIO";
    $coords{vframe} = "LSR";
    if (defined $match[8] && $match[8] !~ /n/) {
        $match[8] =~ s/\s//g; # remove spaces

        my $vdefn = $match[12];

        if (defined $vdefn and $vdefn =~ /^RED/i) {
            $coords{redshift} = $match[8];
        }
        else {
            $coords{rv} = $match[8];
            $coords{vdefn} = $vdefn;
            $coords{vframe} = $match[11];
        }
    }

    if ((defined $match[13]) and (defined $match[14])
            and ($match[13] !~ /n/) and ($match[14] !~ /n/)) {
        $match[13] =~ s/\s//g; # remove spaces
        $match[14] =~ s/\s//g; # remove spaces
        # Convert components of proper motion from mas/year to arcsec/year.
        $coords{'pm'} = [$match[13] / 1000.0, $match[14] / 1000.0];
    }

    if ((defined $match[15]) and ($match[15] !~ /n/)) {
        # Convert parallax from mas to arcsec.
        $coords{'parallax'} = $match[15] / 1000.0;
    }

    # create the source object
    my $source = new Astro::Coords(%coords);

    unless (defined $source) {
        if ($DEBUG) {
            print "failed to create source for '$target' and $ra and $dec and $epoc\n";
            return;
        }
        else {
            croak "Error parsing line. Unable to create source date for target '$target' at RA '$ra' Dec '$dec' and Epoch '$epoc'\n";
        }
    }

    $source->telescope($tel) if $tel;
    $source->comment($cat_comm);

    # Field name should simply be linked to the telescope
    my $field = (defined $tel ? $tel->name : '<UNKNOWN>');

    my %misc;
    # Grab the line's velocity range, if it isn't "n/a".
    if (defined $match[10] && $match[10] !~ /n\/a/) {
        $misc{'velocity_range'} = $match[10];
    }

    # Grab the 850-micron flux, if it isn't "n/a".
    if (defined $match[9] && $match[9] !~ /n\/a/) {
        $misc{'flux850'} = $match[9];
    }

    $misc{'_jcmt_com_before'} = delete $parse_buff->{'comments'}
        if exists $parse_buff->{'comments'};

    print "Created a new source in _parse_line: $target in field $field\n" if $DEBUG;

    # Now create the star object
    return new Astro::Catalog::Item(
        id => $target,
        coords => $source,
        field => $field,
        comment => $cat_comm,
        misc => \%misc,
    );
}

1;

__END__

=back

=head1 NOTES

Coordinates are stored as C<Astro::Coords> objects inside
C<Astro::Catalog::Item> objects.

=head1 GLOBAL VARIABLES

The following global variables can be modified to control the state of the
module:

=over 4

=item $DEBUG

Controls debugging messages. Default state is false.

=back

=head1 CONSTANTS

The following constants are available for querying:

=over 4

=item MAX_SRC_LENGTH

The maximum length of sourcenames writable to a JCMT source catalog.

=back

=head1 COPYRIGHT

Copyright (C) 1999-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHORS

Tim Jenness E<lt>tjenness@cpan.orgE<gt>

=cut
