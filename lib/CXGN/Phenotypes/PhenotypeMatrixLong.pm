package CXGN::Phenotypes::PhenotypeMatrixLong;

=head1 NAME

CXGN::Phenotypes::PhenotypeMatrixLong - an object to handle creating the phenotype matrix in long format. Can return average values for repeated measurements on observationunits. Uses SearchFactory to handle searching native database or materialized views.

=head1 USAGE

my $phenotypes_search = CXGN::Phenotypes::PhenotypeMatrixLong->new(
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
    return_only_first_measurement=>1,
    include_accession_entry_numbers=>0
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

has 'include_accession_entry_numbers' => (
    isa => 'Bool|Undef',
    is => 'ro',
    default => 0
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
    my $schema = $self->bcs_schema;
    my $include_pedigree_parents = $self->include_pedigree_parents();
    my $include_timestamp = $self->include_timestamp;
    my $average_repeat_measurements = $self->average_repeat_measurements;
    my $return_only_first_measurement = $self->return_only_first_measurement;
    my $include_accession_entry_numbers = $self->include_accession_entry_numbers;

    if ($return_only_first_measurement) {
        $average_repeat_measurements = 0;
    }

    $include_timestamp = 1;

    print STDERR Dumper [$self->search_type, $return_only_first_measurement, $average_repeat_measurements];

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        $self->search_type,
        {
            bcs_schema=>$schema,
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
    if ($include_accession_entry_numbers) {
        @metadata_headers = ( 'studyYear', 'programDbId', 'programName', 'programDescription', 'studyDbId', 'studyName', 'studyDescription', 'studyDesign', 'plotWidth', 'plotLength', 'fieldSize', 'fieldTrialIsPlannedToBeGenotyped', 'fieldTrialIsPlannedToCross', 'plantingDate', 'harvestDate', 'locationDbId', 'locationName', 'germplasmDbId', 'germplasmName', 'germplasmSynonyms', 'germplasmEntryNumber', 'observationLevel', 'observationUnitDbId', 'observationUnitName', 'replicate', 'blockNumber', 'plotNumber', 'rowNumber', 'colNumber', 'entryType', 'plantNumber');
    }
    my @values_headers = ('notes', 'createDate', 'collectDate', 'timestamp', 'observationVariableName', 'value');

    if ($self->search_type eq 'MaterializedViewTable'){
        ($data, $unique_traits) = $phenotypes_search->search();
        my @unique_traits_sorted = sort keys %$unique_traits;

        print STDERR "No of lines retrieved: ".scalar(@$data)."\n";
        print STDERR "Construct Pheno Matrix Long MaterializedViewTable Start:".localtime."\n";

        my @header_line = @metadata_headers;
        push @header_line, ('plantedSeedlotStockDbId', 'plantedSeedlotStockUniquename', 'plantedSeedlotCurrentCount', 'plantedSeedlotCurrentWeightGram', 'plantedSeedlotBoxName', 'plantedSeedlotTransactionCount', 'plantedSeedlotTransactionWeight', 'plantedSeedlotTransactionDescription', 'availableGermplasmSeedlotUniquenames');

        if ($include_pedigree_parents){
            push @header_line, ('germplasmPedigreeFemaleParentName', 'germplasmPedigreeFemaleParentDbId', 'germplasmPedigreeMaleParentName', 'germplasmPedigreeMaleParentDbId');
        }

        push @header_line, @values_headers;
        push @info, \@header_line;

        my %trial_entry_numbers;
        if ($include_accession_entry_numbers) {
            my %seen_trial_ids;
            foreach my $obs_unit (@$data){
                $seen_trial_ids{$obs_unit->{trial_id}}++;
            }
            foreach my $trial_id (sort keys %seen_trial_ids) {
                my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $trial_id });
                $trial_entry_numbers{$trial_id} = $trial->get_entry_numbers();
            }
        }

        foreach my $obs_unit (@$data){
            my $entry_type = $obs_unit->{obsunit_is_a_control} ? 'check' : 'test';
            my $synonyms = $obs_unit->{germplasm_synonyms};
            my $synonym_string = $synonyms ? join ("," , @$synonyms) : '';
            my $available_germplasm_seedlots = $obs_unit->{available_germplasm_seedlots};
            my %available_germplasm_seedlots_uniquenames;
            foreach (@$available_germplasm_seedlots){
                $available_germplasm_seedlots_uniquenames{$_->{stock_uniquename}}++;
            }
            my $available_germplasm_seedlots_uniquenames = join ' AND ', (keys %available_germplasm_seedlots_uniquenames);

            my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
            my $trial_id = $obs_unit->{trial_id};
            my $trial_name = $obs_unit->{trial_name};
            my $trial_desc = $obs_unit->{trial_description};

            $trial_name =~ s/\s+$//g;
            $trial_desc =~ s/\s+$//g;

            my @obsunit_line = ($obs_unit->{year}, $obs_unit->{breeding_program_id}, $obs_unit->{breeding_program_name}, $obs_unit->{breeding_program_description}, $trial_id, $trial_name, $trial_desc, $obs_unit->{design}, $obs_unit->{plot_width}, $obs_unit->{plot_length}, $obs_unit->{field_size}, $obs_unit->{field_trial_is_planned_to_be_genotyped}, $obs_unit->{field_trial_is_planned_to_cross}, $obs_unit->{planting_date}, $obs_unit->{harvest_date}, $obs_unit->{trial_location_id}, $obs_unit->{trial_location_name}, $germplasm_stock_id, $obs_unit->{germplasm_uniquename}, $synonym_string);

            if ($include_accession_entry_numbers) {
                my $entry_number = $trial_entry_numbers{$trial_id}{$germplasm_stock_id} || '';
                push @obsunit_line, $entry_number;
            }

            push @obsunit_line, ($obs_unit->{observationunit_type_name}, $obs_unit->{observationunit_stock_id}, $obs_unit->{observationunit_uniquename}, $obs_unit->{obsunit_rep}, $obs_unit->{obsunit_block}, $obs_unit->{obsunit_plot_number}, $obs_unit->{obsunit_row_number}, $obs_unit->{obsunit_col_number}, $entry_type, $obs_unit->{obsunit_plant_number}, $obs_unit->{seedlot_stock_id}, $obs_unit->{seedlot_uniquename}, $obs_unit->{seedlot_current_count}, $obs_unit->{seedlot_current_weight_gram}, $obs_unit->{seedlot_box_name}, $obs_unit->{seedlot_transaction_amount}, $obs_unit->{seedlot_transaction_weight_gram}, $obs_unit->{seedlot_transaction_description}, $available_germplasm_seedlots_uniquenames);

            if ($include_pedigree_parents) {
                my $germplasm = CXGN::Stock->new({schema => $self->bcs_schema, stock_id=>$obs_unit->{germplasm_stock_id}});
                my $parents = $germplasm->get_parents();
                push @obsunit_line, ($parents->{'mother'}, $parents->{'mother_id'}, $parents->{'father'}, $parents->{'father_id'});
            }

            push @obsunit_line, $obs_unit->{notes};

            my $observations = $obs_unit->{observations};

            if ($return_only_first_measurement || $average_repeat_measurements) {
                my %trait_observations;
                foreach (@$observations) {
                    push @{$trait_observations{$_->{trait_name}}}, $_->{value};
                }

                foreach my $trait_name (@unique_traits_sorted) {
                    my $values = $trait_observations{$trait_name} || ['NA'];
                    my $val;
                    if ($return_only_first_measurement) {
                        $val = $values->[0];
                    }
                    elsif ($average_repeat_measurements) {
                        $val = sum(@$values)/scalar(@$values);
                    }
                    push @info, [@obsunit_line, undef, undef, undef, $trait_name, $val];
                }
            }
            else {
                foreach (@$observations){
                    push @info, [@obsunit_line, $_->{create_date}, $_->{collect_date}, $_->{timestamp}, $_->{trait_name}, $_->{value}];
                }
            }
        }
    } else {
        $data = $phenotypes_search->search();
        #print STDERR Dumper $data;

        print STDERR "No of lines retrieved: ".scalar(@$data)."\n";
        print STDERR "Construct Pheno Matrix Native Long Start:".localtime."\n";

        my @line = @metadata_headers;
        push @line, @values_headers;
        push @info, \@line;

        my %trial_entry_numbers;
        if ($include_accession_entry_numbers) {
            my %seen_trial_ids;
            foreach my $obs_unit (@$data){
                $seen_trial_ids{$obs_unit->{trial_id}}++;
            }
            foreach my $trial_id (sort keys %seen_trial_ids) {
                my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $trial_id });
                $trial_entry_numbers{$trial_id} = $trial->get_entry_numbers();
            }
        }

        if ($return_only_first_measurement || $average_repeat_measurements) {
            my %trait_observations;
            my %stock_info;
            my %seen_traits;
            foreach my $d (@$data) {
                my $cvterm = $d->{trait_name};
                my $stock_id = $d->{obsunit_stock_id};
                if ($cvterm){
                    push @{$trait_observations{$stock_id}->{$cvterm}}, $d->{phenotype_value};
                    $stock_info{$stock_id} = $d;
                    $seen_traits{$cvterm}++;
                }
            }
            my @traits_sorted = sort keys %seen_traits;

            my @stock_objs;
            foreach (values %stock_info) {
                push @stock_objs, {
                    obsunit_name => $_->{obsunit_uniquename},
                    obsunit_stock_id => $_->{obsunit_stock_id},
                    trial_id => $_->{trial_id}
                };
            }
            @stock_objs = sort { $a->{trial_id} <=> $b->{trial_id} || $a->{obsunit_name} cmp $b->{obsunit_name} } @stock_objs;

            foreach my $stock_obj (@stock_objs) {
                my $stock_id = $stock_obj->{obsunit_stock_id};
                my $d = $stock_info{$stock_id};

                my $synonyms = $d->{synonyms};
                my $synonym_string = $synonyms ? join ("," , @$synonyms) : '';
                my $entry_type = $d->{is_a_control} ? 'check' : 'test';

                my $germplasm_stock_id = $d->{accession_stock_id};
                my $trial_id = $d->{trial_id};
                my $trial_name = $d->{trial_name};
                my $trial_desc = $d->{trial_description};

                $trial_name =~ s/\s+$//g;
                $trial_desc =~ s/\s+$//g;

                my @obsunit_line = ($d->{year}, $d->{breeding_program_id}, $d->{breeding_program_name}, $d->{breeding_program_description}, $trial_id, $trial_name, $trial_desc, $d->{design}, $d->{plot_width}, $d->{plot_length}, $d->{field_size}, $d->{field_trial_is_planned_to_be_genotyped}, $d->{field_trial_is_planned_to_cross}, $d->{planting_date}, $d->{harvest_date}, $d->{location_id}, $d->{location_name}, $germplasm_stock_id, $d->{accession_uniquename}, $synonym_string);

                if ($include_accession_entry_numbers) {
                    my $entry_number = $trial_entry_numbers{$trial_id}{$germplasm_stock_id} || '';
                    push @obsunit_line, $entry_number;
                }

                push @obsunit_line, ($d->{obsunit_type_name}, $d->{obsunit_stock_id}, $d->{obsunit_uniquename}, $d->{rep}, $d->{block}, $d->{plot_number}, $d->{row_number}, $d->{col_number}, $entry_type, $d->{plant_number}, $d->{notes});

                foreach my $trait_name (@traits_sorted) {
                    my $values = $trait_observations{$stock_id}->{$trait_name} || ['NA'];
                    my $val;
                    if ($return_only_first_measurement) {
                        $val = $values->[0];
                    }
                    elsif ($average_repeat_measurements) {
                        $val = sum(@$values)/scalar(@$values);
                    }
                    push @info, [@obsunit_line, undef, undef, undef, $trait_name, $val];
                }
            }
        }
        else {
            foreach my $d (@$data) {
                my $cvterm = $d->{trait_name};
                if ($cvterm){
                    my $synonyms = $d->{synonyms};
                    my $synonym_string = $synonyms ? join ("," , @$synonyms) : '';
                    my $entry_type = $d->{is_a_control} ? 'check' : 'test';

                    my $germplasm_stock_id = $d->{accession_stock_id};
                    my $trial_id = $d->{trial_id};
                    my $trial_name = $d->{trial_name};
                    my $trial_desc = $d->{trial_description};

                    $trial_name =~ s/\s+$//g;
                    $trial_desc =~ s/\s+$//g;

                    my @line = ($d->{year}, $d->{breeding_program_id}, $d->{breeding_program_name}, $d->{breeding_program_description}, $trial_id, $trial_name, $trial_desc, $d->{design}, $d->{plot_width}, $d->{plot_length}, $d->{field_size}, $d->{field_trial_is_planned_to_be_genotyped}, $d->{field_trial_is_planned_to_cross}, $d->{planting_date}, $d->{harvest_date}, $d->{location_id}, $d->{location_name}, $germplasm_stock_id, $d->{accession_uniquename}, $synonym_string);

                    if ($include_accession_entry_numbers) {
                        my $entry_number = $trial_entry_numbers{$trial_id}{$germplasm_stock_id} || '';
                        push @line, $entry_number;
                    }

                    push @line, ($d->{obsunit_type_name}, $d->{obsunit_stock_id}, $d->{obsunit_uniquename}, $d->{rep}, $d->{block}, $d->{plot_number}, $d->{row_number}, $d->{col_number}, $entry_type, $d->{plant_number}, $d->{notes}, $d->{create_date}, $d->{collect_date}, $d->{timestamp}, $cvterm, $d->{phenotype_value});

                    push @info, \@line;
                }
            }
        }
    }

    #print STDERR Dumper \@info;
    print STDERR "Construct Pheno Matrix End:".localtime."\n";
    return @info;
}

1;
