package CXGN::Phenotypes::PhenotypeMatrix;

=head1 NAME

CXGN::Phenotypes::PhenotypeMatrix - an object to handle creating the phenotype matrix. Can return average values for repeated measurements on observationunits. Uses SearchFactory to handle searching native database or materialized views.

=head1 USAGE

my $phenotypes_search = CXGN::Phenotypes::PhenotypeMatrix->new(
    bcs_schema=>$schema,
    search_type=>$search_type,
    data_level=>$data_level,
    trait_list=>$trait_list,
    trial_list=>$trial_list,
    year_list=>$year_list,
    location_list=>$location_list,
    accession_list=>$accession_list,
    plot_list=>$plot_list,
    plant_list=>$plant_list,
    include_timestamp=>$include_timestamp,
    include_pedigree_parents=>$include_pedigree_parents,
    exclude_phenotype_outlier=>0,
    trait_contains=>$trait_contains,
    phenotype_min_value=>$phenotype_min_value,
    phenotype_max_value=>$phenotype_max_value,
    limit=>$limit,
    offset=>$offset,
    average_repeat_measurements=>0,
    return_only_first_measurement=>1
);
my @data = $phenotypes_search->get_phenotype_matrix();

=head1 DESCRIPTION


=head1 AUTHORS


=cut

use strict;
use warnings;
use Moose;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::Stock::StockLookup;
use CXGN::Phenotypes::SearchFactory;
use List::Util qw/sum/;

has 'bcs_schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1,
);

#PREFERRED MaterializedViewTable (MaterializedViewTable or Native)
has 'search_type' => (
    isa => 'Str',
    is => 'rw',
    required => 1,
);

#(plot, plant, or all)
has 'data_level' => (
    isa => 'Str|Undef',
    is => 'ro',
);

has 'trial_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'trait_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'accession_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'plot_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'plant_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'subplot_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'location_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'year_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'include_pedigree_parents' => (
    isa => 'Bool|Undef',
    is => 'ro',
    default => 0
);

has 'include_timestamp' => (
    isa => 'Bool|Undef',
    is => 'ro',
    default => 0
);

has 'exclude_phenotype_outlier' => (
    isa => 'Bool',
    is => 'ro',
    default => 0
);

has 'average_repeat_measurements' => (
    isa => 'Bool|Undef',
    is => 'ro',
    default => 0
);

has 'return_only_first_measurement' => (
    isa => 'Bool|Undef',
    is => 'ro',
    default => 1
);

has 'trait_contains' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw'
);

has 'phenotype_min_value' => (
    isa => 'Str|Undef',
    is => 'rw'
);

has 'phenotype_max_value' => (
    isa => 'Str|Undef',
    is => 'rw'
);

has 'limit' => (
    isa => 'Int|Undef',
    is => 'rw'
);

has 'offset' => (
    isa => 'Int|Undef',
    is => 'rw'
);

sub get_phenotype_matrix {
    my $self = shift;
    my $include_pedigree_parents = $self->include_pedigree_parents();
    my $include_timestamp = $self->include_timestamp;
    my $average_repeat_measurements = $self->average_repeat_measurements;
    my $return_only_first_measurement = $self->return_only_first_measurement;


    if ($return_only_first_measurement) {
        $average_repeat_measurements = 0;
    }

    if ($average_repeat_measurements) {
        $include_timestamp = 0;
    }
    my %trait_repeat_counter;

    print STDERR "GET PHENOMATRIX ".$self->search_type."\n";
    print STDERR Dumper [$return_only_first_measurement, $average_repeat_measurements];

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        $self->search_type,
        {
            bcs_schema=>$self->bcs_schema,
            data_level=>$self->data_level,
            trait_list=>$self->trait_list,
            trial_list=>$self->trial_list,
            year_list=>$self->year_list,
            location_list=>$self->location_list,
            accession_list=>$self->accession_list,
            plot_list=>$self->plot_list,
            plant_list=>$self->plant_list,
            subplot_list=>$self->subplot_list,
            include_timestamp=>$include_timestamp,
            exclude_phenotype_outlier=>$self->exclude_phenotype_outlier,
            trait_contains=>$self->trait_contains,
            phenotype_min_value=>$self->phenotype_min_value,
            phenotype_max_value=>$self->phenotype_max_value,
            limit=>$self->limit,
            offset=>$self->offset
        }
    );

    my ($data, $unique_traits);
    my @info;
    my @metadata_headers = ( 'studyYear', 'programDbId', 'programName', 'programDescription', 'studyDbId', 'studyName', 'studyDescription', 'studyDesign', 'plotWidth', 'plotLength', 'fieldSize', 'fieldTrialIsPlannedToBeGenotyped', 'fieldTrialIsPlannedToCross', 'plantingDate', 'harvestDate', 'locationDbId', 'locationName', 'germplasmDbId', 'germplasmName', 'germplasmSynonyms', 'observationLevel', 'observationUnitDbId', 'observationUnitName', 'replicate', 'blockNumber', 'plotNumber', 'rowNumber', 'colNumber', 'entryType', 'plantNumber');

    if ($self->search_type eq 'MaterializedViewTable'){
        ($data, $unique_traits) = $phenotypes_search->search();

        print STDERR "No of lines retrieved: ".scalar(@$data)."\n";
        print STDERR "Construct Pheno Matrix Start:".localtime."\n";

        my @line = @metadata_headers;
        push @line, ('plantedSeedlotStockDbId', 'plantedSeedlotStockUniquename', 'plantedSeedlotCurrentCount', 'plantedSeedlotCurrentWeightGram', 'plantedSeedlotBoxName', 'plantedSeedlotTransactionCount', 'plantedSeedlotTransactionWeight', 'plantedSeedlotTransactionDescription', 'availableGermplasmSeedlotUniquenames');

        if ($include_pedigree_parents){
            push @line, ('germplasmPedigreeFemaleParentName', 'germplasmPedigreeFemaleParentDbId', 'germplasmPedigreeMaleParentName', 'germplasmPedigreeMaleParentDbId');
        }

        my %trait_plot_counter;
        foreach my $obs_unit (@$data){
            my $observations = $obs_unit->{observations};
            foreach (@$observations){
                $trait_plot_counter{$obs_unit->{observationunit_stock_id}}->{$_->{trait_name}}++;
            }
        }
        while(my($stock_id, $o) = each %trait_plot_counter) {
            while(my($trait, $number) = each %$o) {
                if (exists($trait_repeat_counter{$trait})) {
                    if ($number > $trait_repeat_counter{$trait}) {
                        $trait_repeat_counter{$trait} = $number;
                    }
                }
                else {
                    $trait_repeat_counter{$trait} = $number;
                }
            }
        }
        print STDERR Dumper \%trait_repeat_counter;

        my @sorted_traits = sort keys(%$unique_traits);
        foreach my $trait (@sorted_traits) {
            if (!$average_repeat_measurements && !$return_only_first_measurement) {
                my $repeat_number = $trait_repeat_counter{$trait};
                if ($repeat_number > 1) {
                    for my $i (1..$repeat_number) {
                        push @line, $trait."|".$i;
                    }
                }
                else {
                    push @line, $trait;
                }
            } else {
                push @line, $trait;
            }
        }
        push @line, 'notes';
        push @info, \@line;

        foreach my $obs_unit (@$data){
            my $entry_type = $obs_unit->{obsunit_is_a_control} ? 'check' : 'test';
            my $synonyms = $obs_unit->{synonyms};
            my $synonym_string = $synonyms ? join ("," , @$synonyms) : '';
            my $available_germplasm_seedlots = $obs_unit->{available_germplasm_seedlots};
            my %available_germplasm_seedlots_uniquenames;
            foreach (@$available_germplasm_seedlots){
                $available_germplasm_seedlots_uniquenames{$_->{stock_uniquename}}++;
            }
            my $available_germplasm_seedlots_uniquenames = join ' AND ', (keys %available_germplasm_seedlots_uniquenames);

            my $trial_name = $obs_unit->{trial_name};
            my $trial_desc = $obs_unit->{trial_description};

            $trial_name =~ s/\s+$//g;
            $trial_desc =~ s/\s+$//g;

            my @line = ($obs_unit->{year}, $obs_unit->{breeding_program_id}, $obs_unit->{breeding_program_name}, $obs_unit->{breeding_program_description}, $obs_unit->{trial_id}, $trial_name, $trial_desc, $obs_unit->{design}, $obs_unit->{plot_width}, $obs_unit->{plot_length}, $obs_unit->{field_size}, $obs_unit->{field_trial_is_planned_to_be_genotyped}, $obs_unit->{field_trial_is_planned_to_cross}, $obs_unit->{planting_date}, $obs_unit->{harvest_date}, $obs_unit->{trial_location_id}, $obs_unit->{trial_location_name}, $obs_unit->{germplasm_stock_id}, $obs_unit->{germplasm_uniquename}, $synonym_string, $obs_unit->{observationunit_type_name}, $obs_unit->{observationunit_stock_id}, $obs_unit->{observationunit_uniquename}, $obs_unit->{obsunit_rep}, $obs_unit->{obsunit_block}, $obs_unit->{obsunit_plot_number}, $obs_unit->{obsunit_row_number}, $obs_unit->{obsunit_col_number}, $entry_type, $obs_unit->{obsunit_plant_number}, $obs_unit->{seedlot_stock_id}, $obs_unit->{seedlot_uniquename}, $obs_unit->{seedlot_current_count}, $obs_unit->{seedlot_current_weight_gram}, $obs_unit->{seedlot_box_name}, $obs_unit->{seedlot_transaction_amount}, $obs_unit->{seedlot_transaction_weight_gram}, $obs_unit->{seedlot_transaction_description}, $available_germplasm_seedlots_uniquenames);

            if ($include_pedigree_parents) {
                my $germplasm = CXGN::Stock->new({schema => $self->bcs_schema, stock_id=>$obs_unit->{germplasm_stock_id}});
                my $parents = $germplasm->get_parents();
                push @line, ($parents->{'mother'}, $parents->{'mother_id'}, $parents->{'father'}, $parents->{'father_id'});
            }

            my $observations = $obs_unit->{observations};
            my %trait_observations;
            foreach (@$observations){
                my $collect_date = $_->{collect_date};
                my $timestamp = $_->{timestamp};
                if ($include_timestamp && $timestamp) {
                    push @{$trait_observations{$_->{trait_name}}}, "$_->{value},$timestamp";
                }
                elsif ($include_timestamp && $collect_date) {
                    push @{$trait_observations{$_->{trait_name}}}, "$_->{value},$collect_date";
                }
                else {
                    push @{$trait_observations{$_->{trait_name}}}, $_->{value};
                }
            }
            foreach my $trait (@sorted_traits) {
                my $obs = $trait_observations{$trait};
                if ($average_repeat_measurements) {
                    my $val;
                    if ($obs) {
                        $val = sum(@$obs)/scalar(@$obs);
                    }
                    push @line, $val;
                }
                elsif ($return_only_first_measurement) {
                    push @line, $obs->[0];
                }
                else {
                    my $repeat_number = $trait_repeat_counter{$trait};
                    foreach my $i (0..$repeat_number-1) {
                        push @line, $obs->[$i];
                    }
                }
            }
            push @line, $obs_unit->{notes};
            push @info, \@line;
        }
    } else {
        $data = $phenotypes_search->search();
        #print STDERR Dumper $data;

        my %obsunit_data;
        my %traits;

        print STDERR "No of lines retrieved: ".scalar(@$data)."\n";
        print STDERR "Construct Pheno Matrix Start:".localtime."\n";
        my @unique_obsunit_list = ();
        my %seen_obsunits;

        my %trait_plot_counter;
        foreach my $d (@$data){
            $trait_plot_counter{$d->{obsunit_stock_id}}->{$d->{trait_name}}++;
        }
        while(my($stock_id, $o) = each %trait_plot_counter) {
            while(my($trait, $number) = each %$o) {
                if (exists($trait_repeat_counter{$trait})) {
                    if ($number > $trait_repeat_counter{$trait}) {
                        $trait_repeat_counter{$trait} = $number;
                    }
                }
                else {
                    $trait_repeat_counter{$trait} = $number;
                }
            }
        }
        print STDERR Dumper \%trait_repeat_counter;

        foreach my $d (@$data) {
            my $cvterm = $d->{trait_name};
            if ($cvterm){
                my $obsunit_id = $d->{obsunit_stock_id};
                if (!exists($seen_obsunits{$obsunit_id})) {
                    push @unique_obsunit_list, $obsunit_id;
                    $seen_obsunits{$obsunit_id} = 1;
                }

                my $timestamp_value = $d->{timestamp};
                my $value = $d->{phenotype_value};

                if ($include_timestamp && $timestamp_value) {
                    push @{$obsunit_data{$obsunit_id}->{$cvterm}}, "$value,$timestamp_value";
                } else {
                    push @{$obsunit_data{$obsunit_id}->{$cvterm}}, $value;
                }

                $obsunit_data{$obsunit_id}->{'notes'} = $d->{notes};

                my $synonyms = $d->{synonyms};
                my $synonym_string = $synonyms ? join ("," , @$synonyms) : '';
                my $entry_type = $d->{is_a_control} ? 'check' : 'test';

                my $trial_name = $d->{trial_name};
                my $trial_desc = $d->{trial_description};

                $trial_name =~ s/\s+$//g;
                $trial_desc =~ s/\s+$//g;

                $obsunit_data{$obsunit_id}->{metadata} = [
                    $d->{year},
                    $d->{breeding_program_id},
                    $d->{breeding_program_name},
                    $d->{breeding_program_description},
                    $d->{trial_id},
                    $trial_name,
                    $trial_desc,
                    $d->{design},
                    $d->{plot_width},
                    $d->{plot_length},
                    $d->{field_size},
                    $d->{field_trial_is_planned_to_be_genotyped},
                    $d->{field_trial_is_planned_to_cross},
                    $d->{planting_date},
                    $d->{harvest_date},
                    $d->{location_id},
                    $d->{location_name},
                    $d->{accession_stock_id},
                    $d->{accession_uniquename},
                    $synonym_string,
                    $d->{obsunit_type_name},
                    $d->{obsunit_stock_id},
                    $d->{obsunit_uniquename},
                    $d->{rep},
                    $d->{block},
                    $d->{plot_number},
                    $d->{row_number},
                    $d->{col_number},
                    $entry_type,
                    $d->{plant_number}
                ];
                $traits{$cvterm}++;
            }
        }
        #print STDERR Dumper \%plot_data;
        #print STDERR Dumper \%traits;

        my @line = @metadata_headers;

        my @sorted_traits = sort keys(%traits);

        foreach my $trait (@sorted_traits) {
            if (!$average_repeat_measurements && !$return_only_first_measurement) {
                my $repeat_number = $trait_repeat_counter{$trait};
                if ($repeat_number > 1) {
                    for my $i (1..$repeat_number) {
                        push @line, $trait."|".$i;
                    }
                }
                else {
                    push @line, $trait;
                }
            } else {
                push @line, $trait;
            }
        }

        push @line, 'notes';
        push @info, \@line;

        foreach my $p (@unique_obsunit_list) {
            my @line = @{$obsunit_data{$p}->{metadata}};

            foreach my $trait (@sorted_traits) {
                my $obs = $obsunit_data{$p}->{$trait};
                if ($average_repeat_measurements) {
                    my $val;
                    if ($obs) {
                        $val = sum(@$obs)/scalar(@$obs);
                    }
                    push @line, $val;
                }
                elsif ($return_only_first_measurement) {
                    push @line, $obs->[0];
                }
                else {
                    my $repeat_number = $trait_repeat_counter{$trait};
                    foreach my $i (0..$repeat_number-1) {
                        push @line, $obs->[$i];
                    }
                }
            }
            push @line,  $obsunit_data{$p}->{'notes'};
            push @info, \@line;
        }
    }

    #print STDERR Dumper \@info;
    print STDERR "Construct Pheno Matrix End:".localtime."\n";
    return @info;
}

1;
