package CXGN::Trial::ParseUpload::Plugin::EarthSenseTXTPointCloudsToPlotNamesCSV;

use Moose::Role;
use CXGN::Stock::StockLookup;
use Text::CSV;
use SGN::Model::Cvterm;
use Data::Dumper;
use CXGN::List::Validate;
use Scalar::Util qw(looks_like_number);

sub _validate_with_plugin {
    my $self = shift;
    my $filename = $self->get_filename();
    my $schema = $self->get_chado_schema();
    my $trial_id = $self->get_trial_id();
    my @error_messages;
    my %errors;
    my %parse_errors;

    my $csv = Text::CSV->new({ sep_char => ',' });

    open(my $fh, '<', $filename)
        or die "Could not open file '$filename' $!"."<br>";

    if (!$fh) {
        push @error_messages, "Could not read file."."<br>";
        print STDERR "Could not read file.\n";
        $parse_errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%parse_errors);
        return;
    }

    my $header_row = <$fh>;
    my @columns;
    if ($csv->parse($header_row)) {
        @columns = $csv->fields();
    } else {
        push @error_messages, "Could not parse header row."."<br>";
        print STDERR "Could not parse header.\n";
        $parse_errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%parse_errors);
        return;
    }

    my $num_cols = scalar(@columns);

    if ( $columns[0] ne "plot_name" ||
        $columns[1] ne "point_cloud_filename" ) {
            push @error_messages, 'File contents incorrect. Header row must contain: plot_name,point_cloud_filename <br>';
            print STDERR "File contents incorrect.\n";
            $parse_errors{'error_messages'} = \@error_messages;
            $self->_set_parse_errors(\%parse_errors);
            return;
    }

    my %seen_plot_names;
    while ( my $row = <$fh> ){
        my @columns;
        if ($csv->parse($row)) {
            @columns = $csv->fields();
        } else {
            push @error_messages, "Could not parse row $row."."<br>";
            print STDERR "Could not parse row $row.\n";
        }

        if (scalar(@columns) != $num_cols){
            push @error_messages, "All lines must have same number of columns as header! Error on row: $row"."<br>";
            print STDERR "Line $row does not have complete columns.\n";
        }

        $seen_plot_names{$columns[0]}++;
    }
    if (scalar(@error_messages) >= 1) {
        $parse_errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%parse_errors);
        return;
    }
    close($fh);

    my @plots = keys %seen_plot_names;
    my $plots_validator = CXGN::List::Validate->new();
    my @plots_missing = @{$plots_validator->validate($schema,'plots',\@plots)->{'missing'}};

    if (scalar(@plots_missing) > 0) {
        push @error_messages, "The following plots are not in the database:<br>".join(", ",@plots_missing)."<br>";
    }

    if (scalar(@error_messages) >= 1) {
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }

    return 1; #returns true if validation is passed
}


sub _parse_with_plugin {
    my $self = shift;
    my $filename = $self->get_filename();
    my $schema = $self->get_chado_schema();
    my %parsed_entries;

    my $csv = Text::CSV->new({ sep_char => ',' });

    open(my $fh, '<', $filename)
        or die "Could not open file '$filename' $!";

    my $header_row = <$fh>;

    while ( my $row = <$fh> ){
        my @columns;
        if ($csv->parse($row)) {
            @columns = $csv->fields();
        }
        my $plot_name = $columns[0];
        my $point_cloud_filename = $columns[1];

        $parsed_entries{$plot_name} = {
            plot_name => $plot_name,
            point_cloud_filename => $point_cloud_filename,
        };
    }
    close($fh);

    $self->_set_parsed_data(\%parsed_entries);
    return 1;
}


1;
