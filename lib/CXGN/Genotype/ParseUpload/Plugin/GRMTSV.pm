package CXGN::Genotype::ParseUpload::Plugin::GRMTSV;

use Moose::Role;
use Spreadsheet::ParseExcel;
use CXGN::Stock::StockLookup;
use SGN::Model::Cvterm;
use Data::Dumper;
use CXGN::List::Validate;

sub _validate_with_plugin {
    my $self = shift;
    my $filename = $self->get_filename();
    my $schema = $self->get_chado_schema();
    my @error_messages;
    my %errors;

    my $header;
    my $row_number = 1;
    my %seen_sample_names;
    open(my $F, "<", $filename) || die "Can't open file $filename\n";
        while (<$F>) {
            chomp;
            #print STDERR Dumper $_;

            if (!$header) {
                $header = $_;
                my @fields = split /\t/, $header;
                if ($fields[0] ne 'a_stock_uniquename'){
                    push @error_messages, 'Column 1 header must be "a_stock_uniquename".';
                }
                if ($fields[1] ne 'b_stock_uniquename'){
                    push @error_messages, 'Column 2 header must be "b_stock_uniquename".';
                }
                if ($fields[2] ne 'value'){
                    push @error_messages, 'Column 3 header must be "value".';
                }
            }
            else {
                my @fields = split /\t/, $_;
                my $a_stock_name = $fields[0];
                my $b_stock_name = $fields[1];
                my $value = $fields[2];

                if (!defined($a_stock_name)) {
                    push @error_messages, 'Column 1 "a_stock_uniquename" is missing on row '.$row_number.'.';
                }
                if (!defined($b_stock_name)) {
                    push @error_messages, 'Column 2 "b_stock_uniquename" is missing on row '.$row_number.'.';
                }
                if (!defined($value)) {
                    push @error_messages, 'Column 3 "value" is missing on row '.$row_number.'.';
                }

                $seen_sample_names{$a_stock_name}++;
                $seen_sample_names{$b_stock_name}++;

                $row_number++;
            }
        }
    close($F);

    my @observation_unit_names = sort keys %seen_sample_names;

    my $organism_id = $self->get_organism_id;
    my $accession_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();

    my $stock_type = $self->get_observation_unit_type_name;
    my @missing_stocks;
    my $validator = CXGN::List::Validate->new();
    if ($stock_type eq 'tissue_sample'){
        @missing_stocks = @{$validator->validate($schema, 'tissue_samples', \@observation_unit_names)->{'missing'}};
    } elsif ($stock_type eq 'accession'){
        @missing_stocks = @{$validator->validate($schema, 'accessions', \@observation_unit_names)->{'missing'}};
    } elsif ($stock_type eq 'stocks'){
        @missing_stocks = @{$validator->validate($schema, 'stocks', \@observation_unit_names)->{'missing'}};
    } else {
        push @error_messages, "You can only upload genotype data for a tissue_sample OR accession (including synonyms) OR stocks!"
    }

    my %unique_stocks;
    foreach (@missing_stocks){
        $unique_stocks{$_}++;
    }

    @missing_stocks = sort keys %unique_stocks;
    my @missing_stocks_return;
    foreach (@missing_stocks){
        if (!$self->get_create_missing_observation_units_as_accessions){
            push @missing_stocks_return, $_;
            print STDERR "WARNING! Observation unit name $_ not found for stock type $stock_type. You can pass an option to automatically create accessions.\n";
        } else {
            print STDERR "Adding new accession $_!\n";
            my $stock = $schema->resultset("Stock::Stock")->create({
                organism_id => $organism_id,
                name       => $_,
                uniquename => $_,
                type_id     => $accession_cvterm_id,
            });
        }
    }

    if (scalar(@missing_stocks_return)>0){
        $errors{'missing_stocks'} = \@missing_stocks_return;
        push @error_messages, "The following stocks are not in the database: ".join(',',@missing_stocks_return);
    }

    #store any errors found in the parsed file to parse_errors accessor
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

    my $header;
    my %grm_info;
    my %seen_sample_names;
    open(my $F, "<", $filename) || die "Can't open file $filename\n";
        while (<$F>) {
            chomp;
            #print STDERR Dumper $_;

            if (!$header) {
                $header = $_;
                my @fields = split /\t/, $header;
            }
            else {
                my @fields = split /\t/, $_;
                my $a_stock_name = $fields[0];
                my $b_stock_name = $fields[1];
                my $value = $fields[2];

                $grm_info{$a_stock_name}->{$b_stock_name} = $value;
                $seen_sample_names{$a_stock_name}++;
                $seen_sample_names{$b_stock_name}++;
            }
        }
    close($F);

    my @observation_unit_names = sort keys %seen_sample_names;

    my %parsed_data = (
        genotypes_info => \%grm_info,
        observation_unit_uniquenames => \@observation_unit_names
    );

    $self->_set_parsed_data(\%parsed_data);

    return 1;
}

1;
