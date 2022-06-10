

package SGN::Controller::AJAX::Search::Cross;

use Moose;
use Data::Dumper;
use CXGN::Cross;
use CXGN::Stock;
use CXGN::List::Validate;
use CXGN::List;

BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
   );

sub search_cross_male_parents :Path('/ajax/search/cross_male_parents') :Args(0){
    my $self = shift;
    my $c = shift;
    my $cross_female_parent= $c->req->param("female_parent");
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    my $cross_male_parents = CXGN::Cross->get_cross_male_parents($schema, $cross_female_parent);

    $c->stash->{rest}={ data => $cross_male_parents};

}


sub search_cross_female_parents :Path('/ajax/search/cross_female_parents') :Args(0){
    my $self = shift;
    my $c = shift;
    my $cross_male_parent= $c->req->param("male_parent");
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    my $cross_female_parents = CXGN::Cross->get_cross_female_parents($schema, $cross_male_parent);

    $c->stash->{rest} = {data => $cross_female_parents};

}


sub search_crosses : Path('/ajax/search/crosses') Args(0) {
    my $self = shift;
    my $c = shift;

    my $female_parent = $c->req->param("female_parent");
    my $male_parent = $c->req->param("male_parent");
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    my $result = CXGN::Cross->get_cross_details($schema, $female_parent, $male_parent);
    my @cross_details;
    foreach my $r (@$result){
        my ($female_parent_id, $female_parent_name, $male_parent_id, $male_parent_name, $cross_entry_id, $cross_name, $cross_type, $family_id, $family_name, $project_id, $project_name) = @$r;
        push @cross_details, [ qq{<a href="/stock/$female_parent_id/view">$female_parent_name</a>},
            qq{<a href="/stock/$male_parent_id/view">$male_parent_name</a>},
            qq{<a href="/cross/$cross_entry_id">$cross_name</a>},
            $cross_type,
            qq{<a href="/stock/$family_id/view">$family_name</a>},
            qq{<a href="/breeders/trial/$project_id">$project_name</a>},
        ];
    }

    $c->stash->{rest}={ data=> \@cross_details};

}


sub search_pedigree_male_parents :Path('/ajax/search/pedigree_male_parents') :Args(0){
    my $self = shift;
    my $c = shift;
    my $pedigree_female_parent= $c->req->param("pedigree_female_parent");
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');

    my $pedigree_male_parents = CXGN::Cross->get_pedigree_male_parents($schema, $pedigree_female_parent);

    $c->stash->{rest}={ data=> $pedigree_male_parents};

}


sub search_pedigree_female_parents :Path('/ajax/search/pedigree_female_parents') :Args(0){
    my $self = shift;
    my $c = shift;
    my $pedigree_male_parent= $c->req->param("pedigree_male_parent");
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');

    my $pedigree_female_parents = CXGN::Cross->get_pedigree_female_parents($schema, $pedigree_male_parent);

    $c->stash->{rest} = {data=> $pedigree_female_parents};

}


sub search_progenies : Path('/ajax/search/progenies') Args(0) {
    my $self = shift;
    my $c = shift;

    my $pedigree_female_parent = $c->req->param("pedigree_female_parent");
    my $pedigree_male_parent = $c->req->param("pedigree_male_parent");

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $result = CXGN::Cross->get_progeny_info($schema, $pedigree_female_parent, $pedigree_male_parent);
    my @progenies;
    foreach my $r(@$result){
        my ($female_parent_id, $female_parent_name, $male_parent_id, $male_parent_name, $progeny_id, $progeny_name, $cross_type) = @$r;
        push @progenies, [ qq{<a href="/stock/$female_parent_id/view">$female_parent_name</a>},
        qq{<a href="/stock/$male_parent_id/view">$male_parent_name</a>},
        qq{<a href="/stock/$progeny_id/view">$progeny_name</a>}, $cross_type];
    }

    $c->stash->{rest}={ data=> \@progenies};

}


sub search_common_parents : Path('/ajax/search/common_parents') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $accession_list_id = $c->req->param("accession_list_id");

    my $accession_list = CXGN::List->new({dbh => $schema->storage->dbh, list_id => $accession_list_id});
    my $accession_items = $accession_list->retrieve_elements($accession_list_id);
    my @accession_names = @$accession_items;

    my $accession_type_id  =  SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();

    my %result_hash;
    my %accession_hash;
    foreach my $accession_name (@accession_names) {
        my $female_parent;
        my $male_parent;
        my $accession_rs = $schema->resultset("Stock::Stock")->find ({ 'uniquename' => $accession_name, 'type_id' => $accession_type_id });
        my $accession_id = $accession_rs->stock_id();
        $accession_hash{$accession_name} = $accession_id;
        my $stock = CXGN::Stock->new({schema => $schema, stock_id=>$accession_id});
        my $parents = $stock->get_parents();
        my $female_name = $parents->{'mother'};
        my $female_id = $parents->{'mother_id'};
        if ($female_name) {
            $female_parent = $female_name;
        } else {
            $female_parent = 'unknown';
        }
        $accession_hash{$female_parent} = $female_id;

        my $male_name = $parents->{'father'};
        my $male_id = $parents->{'father_id'};
        if ($male_name) {
            $male_parent = $male_name;
        } else {
            $male_parent = 'unknown';
        }

        $accession_hash{$male_parent} = $male_id;
        $result_hash{$female_parent}{$male_parent}{$accession_name}++;
    }

    my @formatted_results;
    foreach my $female (sort keys %result_hash) {
        my $female_id = $accession_hash{$female};
        my $female_ref = $result_hash{$female};
        my %female_hash = %{$female_ref};
        foreach my $male (sort keys %female_hash) {
            my $male_id = $accession_hash{$male};
            my @progenies = ();
            my $progenies_string;
            my $male_ref = $female_hash{$male};
            my %male_hash = %{$male_ref};
            foreach my $progeny (sort keys %male_hash) {
                my $progeny_id = $accession_hash{$progeny};
                my $progeny_link = qq{<a href="/stock/$progeny_id/view">$progeny</a>};
                push @progenies, $progeny_link;
            }
            my $number_of_accessions = scalar @progenies;
            $progenies_string = join("<br>", @progenies);
            push @formatted_results, {
                female_name => $female,
                female_id => $female_id,
                male_name => $male,
                male_id => $male_id,
                no_of_accessions => $number_of_accessions,
                progenies => $progenies_string
            };
        }
    }

    $c->stash->{rest}={ data=> \@formatted_results};

}


sub search_all_cross_entries : Path('/ajax/search/all_cross_entries') :Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $pollination_date_key;
    my $number_of_seeds_key;

    my $cross_property_db = $c->config->{cross_property_db};

    my $crosses = CXGN::Cross->new({schema => $schema});

    if ($cross_property_db) {
        $crosses->set_cross_property_db($cross_property_db);
    }

    my $result = $crosses->get_all_cross_entries();
    my @all_crosses;
    foreach my $r (@$result){
        my ($cross_id, $cross_name, $cross_type, $female_id, $female_name, $female_ploidy, $female_genome_structure, $male_id, $male_name, $male_ploidy, $male_genome_structure, $pollination_date, $number_of_seeds, $progeny_count, $project_id, $project_name, $project_description, $project_location ) =@$r;
        push @all_crosses, {
            cross_id => $cross_id,
            cross_name => $cross_name,
            cross_type => $cross_type,
            female_id => $female_id,
            female_name => $female_name,
            female_ploidy => $female_ploidy,
            female_genome_structure => $female_genome_structure,
            male_id => $male_id,
            male_name => $male_name,
            male_ploidy => $male_ploidy,
            male_genome_structure => $male_genome_structure,
            pollination_date => $pollination_date,
            number_of_seeds => $number_of_seeds,
            progeny_count => $progeny_count,
            project_id => $project_id,
            project_name => $project_name,
            project_description => $project_description,
            project_location => $project_location
        };
    }

    $c->stash->{rest} = { data => \@all_crosses };

}




1;
