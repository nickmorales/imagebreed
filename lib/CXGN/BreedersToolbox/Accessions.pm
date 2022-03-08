
package CXGN::BreedersToolbox::Accessions;

=head1 NAME

CXGN::BreedersToolbox::Accessions - functions for managing accessions

=head1 USAGE

 my $accession_manager = CXGN::BreedersToolbox::Accessons->new(schema=>$schema);

=head1 DESCRIPTION


=head1 AUTHORS

 Jeremy D. Edwards (jde22@cornell.edu)

=cut

use strict;
use warnings;
use Data::Dumper;
use Moose;
use SGN::Model::Cvterm;

has 'schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw'
);

has 'people_schema' => (
    isa => 'CXGN::People::Schema',
    is => 'rw'
);

has 'phenome_schema' => (
    isa => 'CXGN::Phenome::Schema',
    is => 'rw'
);

sub get_all_accessions {
    my $self = shift;
    my $schema = $self->schema();

    my $accession_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type');

    my $rs = $self->schema->resultset('Stock::Stock')->search({'me.is_obsolete' => { '!=' => 't' }, type_id => $accession_cvterm->cvterm_id});
    #my $rs = $self->schema->resultset('Stock::Stock')->search( { 'projectprops.type_id'=>$breeding_program_cvterm_id }, { join => 'projectprops' }  );
    my @accessions = ();



    while (my $row = $rs->next()) {
	push @accessions, [ $row->stock_id, $row->name, $row->description ];
    }

    return \@accessions;
}

sub get_all_populations {
    my $self = shift;
    my $schema = $self->schema();

    my $accession_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'accession','stock_type');

    my $population_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'population', 'stock_type');

    my $population_member_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'member_of', 'stock_relationship');

    my $populations_rs = $schema->resultset("Stock::Stock")->search({
        'type_id' => $population_cvterm->cvterm_id(),
        'is_obsolete' => 'f'
    });

    my @accessions_by_population;

    while (my $population_row = $populations_rs->next()) {
	my %population_info;
	$population_info{'name'}=$population_row->name();
	$population_info{'description'}=$population_row->description();
	$population_info{'stock_id'}=$population_row->stock_id();

	push @accessions_by_population, \%population_info;
    }

    return \@accessions_by_population;
}

sub get_population_members {
    my $self = shift;
    my $population_stock_id = shift;
    my $schema = $self->schema();
    my $population_member_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'member_of', 'stock_relationship');

    my @accessions_in_population;
    my $population_members = $schema->resultset("Stock::Stock")->search(
    {
        'object.stock_id'=> $population_stock_id,
        'stock_relationship_subjects.type_id' => $population_member_cvterm->cvterm_id()
    },
    {join => {'stock_relationship_subjects' => 'object'}, order_by => { -asc => 'stock_id'}, '+select'=>['stock_relationship_subjects.stock_relationship_id'], '+as'=>['stock_relationship_id']}
    );

    while (my $population_member_row = $population_members->next()) {
        my %accession_info;
        $accession_info{'stock_relationship_id'}=$population_member_row->get_column('stock_relationship_id');
        $accession_info{'name'}=$population_member_row->name();
        $accession_info{'description'}=$population_member_row->description();
        $accession_info{'stock_id'}=$population_member_row->stock_id();
        my $synonyms_rs;
        $synonyms_rs = $population_member_row->search_related('stockprops', {'type.name' => {ilike => '%synonym%' } }, { join => 'type' });
        my @synonyms;
        if ($synonyms_rs) {
            while (my $synonym_row = $synonyms_rs->next()) {
                push @synonyms, $synonym_row->value();
            }
        }
        $accession_info{'synonyms'}=\@synonyms;
        push @accessions_in_population, \%accession_info;
    }
    return \@accessions_in_population;
}

sub get_possible_seedlots {
    my $self = shift;
    my $uniquenames = shift; #array ref to list of accession unique names
    my $type = shift;
    my $schema = $self->schema();
    my $phenome_schema = $self->phenome_schema();
    my $people_schema = $self->people_schema();
    my $sp_person_id = $self->sp_person_id;
    my $subscription_model = $self->subscription_model;

    my $accessions;
    my $crosses;
    if ($type eq 'accessions'){
        $accessions = $uniquenames;
    }
    if ($type eq 'crosses'){
        $crosses = $uniquenames;
    }

    my ($list, $records_total) = CXGN::Stock::Seedlot->list_seedlots(
        $schema,
        $people_schema,
        $phenome_schema,
        undef, #offset
        undef, #limit
        undef, #seedlot name
        undef, #breeding program
        undef, #location
        undef, #minimum count
        $accessions,
        $crosses,
        1, #exact match
        undef, #minimum weight
        undef, #seedlot ids
        undef, #accession ids
        undef, #quality
        undef, #only good quality
        undef, #box name
        $sp_person_id,
        $subscription_model,
        undef #private company ids
    );

    my %seedlot_hash;
    foreach my $sl (@$list) {
        push @{$seedlot_hash{$sl->{source_stocks}->[0]->[1]}}, {
            breeding_program_id => $sl->{breeding_program_id},
            program => $sl->{breeding_program_name},
            seedlot => [$sl->{seedlot_stock_uniquename}, $sl->{seedlot_stock_id}],
            contents => [$sl->{source_stocks}->[0]->[1], $sl->{source_stocks}->[0]->[0]],
            location => $sl->{location},
            count => $sl->{current_count},
            weight_gram => $sl->{current_weight_gram}
        };
    }
    return \%seedlot_hash;
}

1;
