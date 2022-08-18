
=head1 NAME

SGN::Controller::AJAX::Stock - a REST controller class to provide the
backend for objects linked with stocks

=head1 DESCRIPTION

Add new stock properties, stock dbxrefs and so on.

=head1 AUTHOR

Lukas Mueller <lam87@cornell.edu>
Naama Menda <nm249@cornell.edu>

=cut

package SGN::Controller::AJAX::Stock;

use Moose;

use List::MoreUtils qw /any /;
use Data::Dumper;
use Try::Tiny;
use CXGN::Phenome::Schema;
use CXGN::Phenome::Allele;
use CXGN::Stock;
use CXGN::Page::FormattingHelpers qw/ columnar_table_html info_table_html html_alternate_show /;
use CXGN::Phenome::DumpGenotypes;
use CXGN::BreederSearch;
use Scalar::Util 'reftype';
use CXGN::BreedersToolbox::StocksFuzzySearch;
use CXGN::Stock::RelatedStocks;
use CXGN::BreederSearch;
use CXGN::Genotype::Search;
use JSON;
use CXGN::Cross;

use Bio::Chado::Schema;

use Scalar::Util qw(looks_like_number);
use DateTime;
use SGN::Model::Cvterm;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
   );


=head2 add_stockprop


L<Catalyst::Action::REST> action.

Stores a new stockprop in the database

=cut

sub add_stockprop : Path('/stock/prop/add') : ActionClass('REST') { }

sub add_stockprop_POST {
    my ( $self, $c ) = @_;
    my $response;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 'submitter', 0, 0);

    my $req = $c->req;
    my $stock_id = $c->req->param('stock_id');
    my $prop  = $c->req->param('prop');
    $prop =~ s/^\s+|\s+$//g; #trim whitespace from both ends
    my $prop_type = $c->req->param('prop_type');

    my $stock = $schema->resultset("Stock::Stock")->find( { stock_id => $stock_id } );

    if ($stock && $prop && $prop_type) {

        my $message = '';
        if ($prop_type eq 'stock_synonym') {
            my $fuzzy_accession_search = CXGN::BreedersToolbox::StocksFuzzySearch->new({schema => $schema});
            my $max_distance = 0.2;
            my $fuzzy_search_result = $fuzzy_accession_search->get_matches([$prop], $max_distance, 'accession');
            #print STDERR Dumper $fuzzy_search_result;
            my $found_accessions = $fuzzy_search_result->{'found'};
            my $fuzzy_accessions = $fuzzy_search_result->{'fuzzy'};
            if ($fuzzy_search_result->{'error'}){
                $c->stash->{rest} = { error => "ERROR: ".$fuzzy_search_result->{'error'} };
                $c->detach();
            }
            if (scalar(@$found_accessions) > 0){
                $c->stash->{rest} = { error => "Synonym not added: The synonym you are adding is already stored as its own unique stock or as a synonym." };
                $c->detach();
            }
            if (scalar(@$fuzzy_accessions) > 0){
                my @fuzzy_match_names;
                foreach my $a (@$fuzzy_accessions){
                    foreach my $m (@{$a->{'matches'}}) {
                        push @fuzzy_match_names, $m->{'name'};
                    }
                }
                $message = "CAUTION: The synonym you are adding is similar to these accessions and synonyms in the database: ".join(', ', @fuzzy_match_names).".";
            }
        }

        try {
            $stock->create_stockprops( { $prop_type => $prop }, { autocreate => 1 } );
            my $stock = CXGN::Stock->new({
                schema=>$schema,
                stock_id=>$stock_id,
                is_saving=>1,
                sp_person_id => $user_id,
                user_name => $user_name,
                modification_note => "Added property: $prop_type = $prop"
            });
            my $added_stock_id = $stock->store();

            my $dbh = $c->dbc->dbh();
            my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
            my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'stockprop', 'concurrent', $c->config->{basepath});

            $c->stash->{rest} = { message => "$message Stock_id $stock_id and type_id $prop_type have been associated with value $prop. ".$refresh->{'message'} };
        } catch {
            $c->stash->{rest} = { error => "Failed: $_" }
        };
    } else {
        $c->stash->{rest} = { error => "Cannot associate prop $prop_type: $prop with stock $stock_id " };
    }
    #$c->stash->{rest} = { message => 'success' };
}

sub add_stockprop_GET {
    my $self = shift;
    my $c = shift;
    return $self->add_stockprop_POST($c);
}


=head2 get_stockprops

 Usage:
 Desc:         Gets the stockprops of type type_id associated with a stock_id
 Ret:
 Args:
 Side Effects:
 Example:

=cut



sub get_stockprops : Path('/stock/prop/get') : ActionClass('REST') { }

sub get_stockprops_GET {
    my ($self, $c) = @_;
    my $stock_id = $c->req->param("stock_id");
    my $type_id = $c->req->param("type_id");
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');

    my $prop_rs = $schema->resultset("Stock::Stockprop")->search(
	{
	    stock_id => $stock_id,
	    #type_id => $type_id,
	}, { join => 'type', order_by => 'stockprop_id' } );

    my @propinfo = ();
    while (my $prop = $prop_rs->next()) {
	push @propinfo, { stockprop_id => $prop->stockprop_id, stock_id => $prop->stock_id, type_id => $prop->type_id(), type_name => $prop->type->name(), value => $prop->value() };
    }

    $c->stash->{rest} = \@propinfo;


}


sub delete_stockprop : Path('/stock/prop/delete') : ActionClass('REST') { }

sub delete_stockprop_GET {
    my $self = shift;
    my $c = shift;
    my $stockprop_id = $c->req->param("stockprop_id");
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 'submitter', 0, 0);

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $spr = $schema->resultset("Stock::Stockprop")->find( { stockprop_id => $stockprop_id });
    if (! $spr) {
	$c->stash->{rest} = { error => 'The specified prop does not exist' };
	return;
    }
    eval {
	$spr->delete();
    };
    if ($@) {
	$c->stash->{rest} = { error => "An error occurred during deletion: $@" };
	    return;
    }
    $c->stash->{rest} = { message => "The element was removed from the database." };

}

=head2 trait_autocomplete

Public Path: /ajax/stock/trait_autocomplete

Autocomplete a trait name.  Takes a single GET param,
C<term>, responds with a JSON array of completions for that term.

=cut

sub trait_autocomplete : Local : ActionClass('REST') { }

sub trait_autocomplete_GET :Args(0) {
    my ( $self, $c ) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');
    # trim and regularize whitespace
    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;
    my $q = "SELECT DISTINCT cvterm.name FROM phenotype JOIN cvterm ON cvterm_id = observable_id WHERE cvterm.name ilike ? ORDER BY cvterm.name";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute( '%'.$term.'%');
    while  (my ($term_name) = $sth->fetchrow_array ) {
        push @response_list, $term_name;
    }
    $c->stash->{rest} = \@response_list;
}

=head2 project_autocomplete

Public Path: /ajax/stock/project_autocomplete

Autocomplete a project name.  Takes a single GET param,
C<term>, responds with a JSON array of completions for that term.
Finds only projects that are linked with a stock

=cut

sub project_autocomplete : Local : ActionClass('REST') { }

sub project_autocomplete_GET :Args(0) {
    my ( $self, $c ) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');
    # trim and regularize whitespace
    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;
    my $q = "SELECT  distinct project.name FROM project WHERE project.name ilike ? ORDER BY project.name LIMIT 100";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute( '%'.$term.'%');
    while  (my ($project_name) = $sth->fetchrow_array ) {
        push @response_list, $project_name;
    }
    $c->stash->{rest} = \@response_list;
}

=head2 project_year_autocomplete

Public Path: /ajax/stock/project_year_autocomplete

Autocomplete a project year value.  Takes a single GET param,
C<term>, responds with a JSON array of completions for that term.
Finds only year projectprops that are linked with a stock

=cut

sub project_year_autocomplete : Local : ActionClass('REST') { }

sub project_year_autocomplete_GET :Args(0) {
    my ( $self, $c ) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');
    # trim and regularize whitespace
    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;
    my $q = "SELECT  distinct value FROM
  nd_experiment_stock JOIN
  nd_experiment_project USING (nd_experiment_id) JOIN
  projectprop USING (project_id) JOIN
  cvterm on cvterm_id = projectprop.type_id
  WHERE cvterm.name ilike ? AND value ilike ?";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute( '%year%' , '%'.$term.'%');
    while  (my ($project_name) = $sth->fetchrow_array ) {
        push @response_list, $project_name;
    }
    $c->stash->{rest} = \@response_list;
}


=head2 seedlot_name_autocomplete

Public Path: /ajax/stock/seedlot_name_autocomplete

Autocomplete a seedlot name.  Takes a single GET param,
C<term>, responds with a JSON array of completions for that term.

=cut

sub seedlot_name_autocomplete : Local : ActionClass('REST') { }

sub seedlot_name_autocomplete_GET :Args(0) {
    my ( $self, $c ) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');
    # trim and regularize whitespace
    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $seedlot_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'seedlot', 'stock_type')->cvterm_id();

    my @response_list;
    my $q = "SELECT uniquename FROM stock where type_id = ? AND uniquename ilike ? LIMIT 1000";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute( $seedlot_cvterm_id , '%'.$term.'%');
    while  (my ($uniquename) = $sth->fetchrow_array ) {
        push @response_list, $uniquename;
    }
    $c->stash->{rest} = \@response_list;
}


=head2 stockproperty_autocomplete

Public Path: /ajax/stock/stockproperty_autocomplete

Autocomplete a stock property. Takes GET param for term and property,
C<term>, responds with a JSON array of completions for that term.
Finds stockprop values that are linked with a stock

=cut

sub stockproperty_autocomplete : Local : ActionClass('REST') { }

sub stockproperty_autocomplete_GET :Args(0) {
    my ( $self, $c ) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $term = $c->req->param('term');
    my $cvterm_name = $c->req->param('property');
    # trim and regularize whitespace
    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my $cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, $cvterm_name, 'stock_property')->cvterm_id();
    my @response_list;
    my $q = "SELECT distinct value FROM stockprop WHERE type_id=? and value ilike ?";
    my $sth = $schema->storage->dbh->prepare($q);
    $sth->execute( $cvterm_id, '%'.$term.'%');
    while  (my ($val) = $sth->fetchrow_array ) {
        push @response_list, $val;
    }
    $c->stash->{rest} = \@response_list;
}

=head2 geolocation_autocomplete

Public Path: /ajax/stock/geolocation_autocomplete

Autocomplete a geolocation description.  Takes a single GET param,
C<term>, responds with a JSON array of completions for that term.
Finds only locations that are linked with a stock

=cut

sub geolocation_autocomplete : Local : ActionClass('REST') { }

sub geolocation_autocomplete_GET :Args(0) {
    my ( $self, $c ) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');
    # trim and regularize whitespace
    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;
    my $q = "SELECT  distinct nd_geolocation.description FROM
  nd_experiment_stock JOIN
  nd_experiment USING (nd_experiment_id) JOIN
  nd_geolocation USING (nd_geolocation_id)
  WHERE nd_geolocation.description ilike ?";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute( '%'.$term.'%');
    while  (my ($location) = $sth->fetchrow_array ) {
        push @response_list, $location;
    }
    $c->stash->{rest} = \@response_list;
}

=head2 stock_autocomplete

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub stock_autocomplete : Local : ActionClass('REST') { }

sub stock_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $phenome_schema = $c->dbic_schema('CXGN::Phenome::Schema');
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');
    my $stock_type_id = $c->req->param('stock_type_id');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my $stock_search = CXGN::Stock::Search->new({
        bcs_schema=>$schema,
        people_schema=>$people_schema,
        phenome_schema=>$phenome_schema,
        subscription_model=>$c->config->{subscription_model},
        match_name=>$term,
        stock_type_id=>$stock_type_id,
        minimal_info=>1,
        sp_person_id=>$user_id,
        limit=>100
    });
    my ($result, $records_total) = $stock_search->search();

    my @response_list;
    foreach (@$result) {
        push @response_list, $_->{uniquename};
    }
    #print STDERR "stock_autocomplete RESPONSELIST = ".join ", ", @response_list;

    $c->stash->{rest} = \@response_list;
}

=head2 accession_autocomplete

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub accession_autocomplete : Local : ActionClass('REST') { }

sub accession_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my @response_list;
    my $q = "select distinct(stock.uniquename) from stock join cvterm on(type_id=cvterm_id) where stock.uniquename ilike ? and (cvterm.name='accession' or cvterm.name='vector_construct') ORDER BY stock.uniquename LIMIT 20";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my ($stock_name) = $sth->fetchrow_array) {
	push @response_list, $stock_name;
    }

    #print STDERR Dumper @response_list;

    $c->stash->{rest} = \@response_list;
}

=head2 accession_or_cross_autocomplete

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub accession_or_cross_autocomplete : Local : ActionClass('REST') { }

sub accession_or_cross_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my @response_list;
    my $q = "select distinct(stock.uniquename) from stock join cvterm on(type_id=cvterm_id) where stock.uniquename ilike ? and (cvterm.name='accession' or cvterm.name='cross') ORDER BY stock.uniquename LIMIT 20";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my ($stock_name) = $sth->fetchrow_array) {
	push @response_list, $stock_name;
    }

    #print STDERR Dumper @response_list;

    $c->stash->{rest} = \@response_list;
}

=head2 cross_autocomplete

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub cross_autocomplete : Local : ActionClass('REST') { }

sub cross_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my @response_list;
    my $q = "select distinct(stock.uniquename) from stock join cvterm on(type_id=cvterm_id) where stock.uniquename ilike ? and cvterm.name='cross' ORDER BY stock.uniquename LIMIT 20";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my ($stock_name) = $sth->fetchrow_array) {
        push @response_list, $stock_name;
    }

    #print STDERR Dumper @response_list;
    $c->stash->{rest} = \@response_list;
}

=head2 family_name_autocomplete

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub family_name_autocomplete : Local : ActionClass('REST') { }

sub family_name_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my @response_list;
    my $q = "select distinct(stock.uniquename) from stock join cvterm on(type_id=cvterm_id) where stock.uniquename ilike ? and cvterm.name='family_name' ORDER BY stock.uniquename LIMIT 20";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my ($stock_name) = $sth->fetchrow_array) {
        push @response_list, $stock_name;
    }

    #print STDERR Dumper @response_list;
    $c->stash->{rest} = \@response_list;
}


=head2 population_autocomplete

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub population_autocomplete : Local : ActionClass('REST') { }

sub population_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $population_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'population', 'stock_type')->cvterm_id();

    my @response_list;
    my $q = "select distinct(uniquename) from stock where uniquename ilike ? and type_id=? ORDER BY stock.uniquename";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%', $population_cvterm_id);
    while (my ($stock_name) = $sth->fetchrow_array) {
	push @response_list, $stock_name;
    }

    #print STDERR "stock_autocomplete RESPONSELIST = ".join ", ", @response_list;

    $c->stash->{rest} = \@response_list;
}

=head2 accession_population_autocomplete

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub accession_population_autocomplete : Local : ActionClass('REST') { }

sub accession_population_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my @response_list;
    my $q = "select distinct(stock.uniquename) from stock join cvterm on(type_id=cvterm_id) where stock.uniquename ilike ? and (cvterm.name='accession' or cvterm.name='population') ORDER BY stock.uniquename";
    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my ($stock_name) = $sth->fetchrow_array) {
	push @response_list, $stock_name;
    }

    #print STDERR "stock_autocomplete RESPONSELIST = ".join ", ", @response_list;

    $c->stash->{rest} = \@response_list;
}


=head2 pedigree_female_parent_autocomplete

Public Path: /ajax/stock/pedigree_female_parent_autocomplete

Autocomplete a female parent associated with pedigree.

=cut

sub pedigree_female_parent_autocomplete: Local : ActionClass('REST'){}

sub pedigree_female_parent_autocomplete_GET : Args(0){
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;

    my $q = "SELECT distinct (pedigree_female_parent.uniquename) FROM stock AS pedigree_female_parent
    JOIN stock_relationship ON (stock_relationship.subject_id = pedigree_female_parent.stock_id)
    JOIN cvterm AS cvterm1 ON (stock_relationship.type_id = cvterm1.cvterm_id) AND cvterm1.name = 'female_parent'
    JOIN stock AS check_type ON (stock_relationship.object_id = check_type.stock_id)
    JOIN cvterm AS cvterm2 ON (check_type.type_id = cvterm2.cvterm_id) AND cvterm2.name = 'accession'
    WHERE pedigree_female_parent.uniquename ilike ? ORDER BY pedigree_female_parent.uniquename";

    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my($pedigree_female_parent) = $sth->fetchrow_array){
      push @response_list, $pedigree_female_parent;
    }

  #print STDERR Dumper @response_list ;
    $c->stash->{rest} = \@response_list;

}


=head2 pedigree_male_parent_autocomplete

Public Path: /ajax/stock/pedigree_male_parent_autocomplete

Autocomplete a male parent associated with pedigree.

=cut

sub pedigree_male_parent_autocomplete: Local : ActionClass('REST'){}

sub pedigree_male_parent_autocomplete_GET : Args(0){
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;

    my $q = "SELECT distinct (pedigree_male_parent.uniquename) FROM stock AS pedigree_male_parent
    JOIN stock_relationship ON (stock_relationship.subject_id = pedigree_male_parent.stock_id)
    JOIN cvterm AS cvterm1 ON (stock_relationship.type_id = cvterm1.cvterm_id) AND cvterm1.name = 'male_parent'
    JOIN stock AS check_type ON (stock_relationship.object_id = check_type.stock_id)
    JOIN cvterm AS cvterm2 ON (check_type.type_id = cvterm2.cvterm_id) AND cvterm2.name = 'accession'
    WHERE pedigree_male_parent.uniquename ilike ? ORDER BY pedigree_male_parent.uniquename";

    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my($pedigree_male_parent) = $sth->fetchrow_array){
        push @response_list, $pedigree_male_parent;
    }

    $c->stash->{rest} = \@response_list;

}


=head2 cross_female_parent_autocomplete

Public Path: /ajax/stock/cross_female_parent_autocomplete

Autocomplete a female parent associated with cross.

=cut

sub cross_female_parent_autocomplete: Local : ActionClass('REST'){}

sub cross_female_parent_autocomplete_GET : Args(0){
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;

    my $q = "SELECT distinct (cross_female_parent.uniquename) FROM stock AS cross_female_parent
    JOIN stock_relationship ON (stock_relationship.subject_id = cross_female_parent.stock_id)
    JOIN cvterm AS cvterm1 ON (stock_relationship.type_id = cvterm1.cvterm_id) AND cvterm1.name = 'female_parent'
    JOIN stock AS check_type ON (stock_relationship.object_id = check_type.stock_id)
    JOIN cvterm AS cvterm2 ON (check_type.type_id = cvterm2.cvterm_id) AND cvterm2.name = 'cross'
    WHERE cross_female_parent.uniquename ilike ? ORDER BY cross_female_parent.uniquename";

    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my($cross_female_parent) = $sth->fetchrow_array){
      push @response_list, $cross_female_parent;
    }

  #print STDERR Dumper @response_list ;
    $c->stash->{rest} = \@response_list;

}


=head2 cross_male_parent_autocomplete

Public Path: /ajax/stock/cross_male_parent_autocomplete

Autocomplete a male parent associated with cross.

=cut

sub cross_male_parent_autocomplete: Local : ActionClass('REST'){}

sub cross_male_parent_autocomplete_GET : Args(0){
    my ($self, $c) = @_;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $term = $c->req->param('term');

    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;
    my @response_list;

    my $q = "SELECT distinct (cross_male_parent.uniquename) FROM stock AS cross_male_parent
    JOIN stock_relationship ON (stock_relationship.subject_id = cross_male_parent.stock_id)
    JOIN cvterm AS cvterm1 ON (stock_relationship.type_id = cvterm1.cvterm_id) AND cvterm1.name = 'male_parent'
    JOIN stock AS check_type ON (stock_relationship.object_id = check_type.stock_id)
    JOIN cvterm AS cvterm2 ON (check_type.type_id = cvterm2.cvterm_id) AND cvterm2.name = 'cross'
    WHERE cross_male_parent.uniquename ilike ? ORDER BY cross_male_parent.uniquename";

    my $sth = $c->dbc->dbh->prepare($q);
    $sth->execute('%'.$term.'%');
    while (my($cross_male_parent) = $sth->fetchrow_array){
        push @response_list, $cross_male_parent;
    }

    $c->stash->{rest} = \@response_list;

}


sub parents : Local : ActionClass('REST') {}

sub parents_GET : Path('/ajax/stock/parents') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $stock_id = $c->req->param("stock_id");

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');

    my $female_parent_type_id = $schema->resultset("Cv::Cvterm")->find( { name=> "female_parent" } )->cvterm_id();

    my $male_parent_type_id = $schema->resultset("Cv::Cvterm")->find( { name=> "male_parent" } )->cvterm_id();

    my %parent_types;
    $parent_types{$female_parent_type_id} = "female";
    $parent_types{$male_parent_type_id} = "male";

    my $parent_rs = $schema->resultset("Stock::StockRelationship")->search( { 'me.type_id' => { -in => [ $female_parent_type_id, $male_parent_type_id] }, object_id => $stock_id })->search_related("subject");

    my @parents;
    while (my $p = $parent_rs->next()) {
	push @parents, [
	    $p->get_column("stock_id"),
	    $p->get_column("uniquename"),
	];

    }
    $c->stash->{rest} = {
	stock_id => $stock_id,
	parents => \@parents,
    };
}

sub remove_stock_parent : Local : ActionClass('REST') { }

sub remove_parent_GET : Path('/ajax/stock/parent/remove') Args(0) {
    my ($self, $c) = @_;
    my $stock_id = $c->req->param("stock_id");
    my $parent_id = $c->req->param("parent_id");
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 'submitter', 0, 0);

    if (!$stock_id || ! $parent_id) {
        $c->stash->{rest} = { error => "No stock and parent specified" };
        return;
    }

    my $q = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado")->resultset("Stock::StockRelationship")->find( { object_id => $stock_id, subject_id=> $parent_id });

    eval {
	$q->delete();
    };
    if ($@) {
	$c->stash->{rest} = { error => $@ };
	return;
    }

    $c->stash->{rest} = { success => 1 };
}



=head2 add_stock_parent

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub add_stock_parent : Local : ActionClass('REST') { }

sub add_stock_parent_GET :Args(0) {
    my ($self, $c) = @_;
    print STDERR "Add_stock_parent function...\n";
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 'submitter', 0, 0);

    my $stock_id = $c->req->param('stock_id');
    my $parent_name = $c->req->param('parent_name');
    my $parent_type = $c->req->param('parent_type');

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    my $cvterm_name = "";
    my $cross_type = "";
    if ($parent_type eq "male") {
        $cvterm_name = "male_parent";
    }
    elsif ($parent_type eq "female") {
        $cvterm_name = "female_parent";
        $cross_type = $c->req->param('cross_type');
    }

    my $type_id_row = SGN::Model::Cvterm->get_cvterm_row($schema, $cvterm_name, "stock_relationship" )->cvterm_id();

    # check if a parent of this parent_type is already associated with this stock
    #
    my $previous_parent = $schema->resultset("Stock::StockRelationship")->find({
        type_id => $type_id_row,
        object_id => $stock_id
    });

    if ($previous_parent) {
	print STDERR "The stock ".$previous_parent->subject_id." is already associated with stock $stock_id - returning.\n";
	$c->stash->{rest} = { error => "A $parent_type parent with id ".$previous_parent->subject_id." is already associated with this stock. Please specify another parent." };
	return;
    }

    print STDERR "PARENT_NAME = $parent_name STOCK_ID $stock_id  $cvterm_name\n";

    my $stock = $schema->resultset("Stock::Stock")->find( { stock_id => $stock_id });

   my $parent = $schema->resultset("Stock::Stock")->find( { uniquename => $parent_name } );



    if (!$stock) {
	$c->stash->{rest} = { error => "Stock with $stock_id is not found in the database!"};
	return;
    }
    if (!$parent) {
	$c->stash->{rest} = { error => "Stock with uniquename $parent_name was not found, Either this is not unique name or it is not in the database!"};
	return;     }

    my $new_row = $schema->resultset("Stock::StockRelationship")->new(
	{
	    subject_id => $parent->stock_id,
	    object_id  => $stock->stock_id,
	    type_id    => $type_id_row,
        value => $cross_type
	});

    eval {
	$new_row->insert();
    };

    if ($@) {
	$c->stash->{rest} = { error => "An error occurred: $@"};
    }
    else {
	$c->stash->{rest} = { error => '', };
    }
}


=head2 action get_stock_trials()

 Usage:        /stock/<stock_id>/datatables/trials
 Desc:         retrieves trials associated with the stock
 Ret:          a table in json suitable for datatables
 Args:
 Side Effects:
 Example:

=cut

sub get_stock_trials :Chained('/stock/get_stock') PathPart('datatables/trials') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my @trials = $c->stash->{stock}->get_trials();

    my @formatted_trials;
    foreach my $t (@trials) {
	push @formatted_trials, [ '<a href="/breeders/trial/'.$t->[0].'">'.$t->[1].'</a>', $t->[3], '<a href="javascript:show_stock_trial_detail('.$c->stash->{stock}->stock_id().', \''.$c->stash->{stock}->name().'\' ,'.$t->[0].',\''.$t->[1].'\')">Details</a>' ];
    }
    $c->stash->{rest} = { data => \@formatted_trials };
}


=head2 action get_stock_trait_list()

 Usage:        /stock/<stock_id>/datatables/traitlist
 Desc:         retrieves the list of traits assayed on the stock
 Ret:          json in a table format, suitable for datatables
 Args:
 Side Effects:
 Example:

=cut

sub get_stock_trait_list :Chained('/stock/get_stock') PathPart('datatables/traitlist') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $stock = CXGN::Stock->new({schema => $schema, stock_id =>$c->stash->{stock_id}});

    my @trait_list = $stock->get_trait_list();

    my @formatted_list;
    foreach my $t (@trait_list) {
        # print STDERR Dumper($t);
        my $avg = $t->[3] ? $t->[3] : '0.0';
        my $std = $t->[4] ? $t->[4] : '0.0';
        push @formatted_list, [ '<a href="/cvterm/'.$t->[0].'/view">'.$t->[1].'</a>', $t->[2], sprintf("%3.1f", $avg), sprintf("%3.1f", $std), sprintf("%.0f", $t->[5])];
    }
    # print STDERR Dumper(\@formatted_list);

    $c->stash->{rest} = { data => \@formatted_list };
}

sub get_phenotypes_by_stock_and_trial :Chained('/stock/get_stock') PathPart('datatables/trial') Args(1) {
    my $self = shift;
    my $c = shift;
    my $trial_id = shift;
    my $stock_type = $c->stash->{stock}->type();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $q;
    if ($stock_type eq 'accession'){
        $q = "SELECT stock.stock_id, stock.uniquename, cvterm_id, cvterm.name, avg(phenotype.value::REAL), stddev(phenotype.value::REAL), count(phenotype.value::REAL)
            FROM stock
            JOIN stock_relationship ON (stock.stock_id=stock_relationship.object_id)
            JOIN nd_experiment_phenotype_bridge ON (nd_experiment_phenotype_bridge.stock_id=stock_relationship.subject_id)
            JOIN phenotype USING(phenotype_id)
            JOIN cvterm ON (phenotype.cvalue_id=cvterm.cvterm_id)
            WHERE project_id=? AND stock.stock_id=?
            GROUP BY stock.stock_id, stock.uniquename, cvterm_id, cvterm.name";
    } else {
        $q = "SELECT stock.stock_id, stock.uniquename, cvterm_id, cvterm.name, avg(phenotype.value::REAL), stddev(phenotype.value::REAL), count(phenotype.value::REAL)
            FROM stock
            JOIN nd_experiment_phenotype_bridge USING(stock_id)
            JOIN phenotype USING(phenotype_id)
            JOIN cvterm ON (phenotype.cvalue_id=cvterm.cvterm_id)
            WHERE project_id=? AND stock.stock_id=?
            GROUP BY stock.stock_id, stock.uniquename, cvterm_id, cvterm.name";
    }

    my $h = $c->dbc->dbh->prepare($q);
    $h->execute($trial_id, $c->stash->{stock}->stock_id());

    my @phenotypes;
    while (my ($stock_id, $stock_name, $cvterm_id, $cvterm_name, $avg, $stddev, $count) = $h->fetchrow_array()) {
        $stddev = $stddev || 0;
        push @phenotypes, [ "<a href=\"/cvterm/$cvterm_id/view\">$cvterm_name</a>", sprintf("%.2f", $avg), sprintf("%.2f", $stddev), $count ];
    }
    $c->stash->{rest} = { data => \@phenotypes };
}

sub get_pedigree_string :Chained('/stock/get_stock') PathPart('pedigree') Args(0) {
    my $self = shift;
    my $c = shift;
    my $level = $c->req->param("level");
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $stock = CXGN::Stock->new(
        schema => $c->dbic_schema("Bio::Chado::Schema", "sgn_chado"),
        stock_id => $c->stash->{stock}->stock_id()
    );
    my $parents = $stock->get_pedigree_string($level);
    print STDERR "Parents are: ".Dumper($parents)."\n";

    $c->stash->{rest} = { pedigree_string => $parents };
}


sub get_pedigree_string_ :Chained('/stock/get_stock') PathPart('pedigreestring') Args(0) {
    my $self = shift;
    my $c = shift;
    my $level = $c->req->param("level");
    my $stock_id = $c->stash->{stock}->stock_id();
    my $stock_name = $c->stash->{stock}->name();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $pedigree_string;

    my %pedigree = _get_pedigree_hash($c,[$stock_id]);

    if ($level eq "Parents") {
        my $mother = $pedigree{$stock_name}{'1'}{'mother'} || 'NA';
        my $father = $pedigree{$stock_name}{'1'}{'father'} || 'NA';
        $pedigree_string = "$mother/$father" ;
    }
    elsif ($level eq "Grandparents") {
        my $maternal_mother = $pedigree{$pedigree{$stock_name}{'1'}{'mother'}}{'2'}{'mother'} || 'NA';
        my $maternal_father = $pedigree{$pedigree{$stock_name}{'1'}{'mother'}}{'2'}{'father'} || 'NA';
        my $paternal_mother = $pedigree{$pedigree{$stock_name}{'1'}{'father'}}{'2'}{'mother'} || 'NA';
        my $paternal_father = $pedigree{$pedigree{$stock_name}{'1'}{'father'}}{'2'}{'father'} || 'NA';
        my $maternal_parent_string = "$maternal_mother/$maternal_father";
        my $paternal_parent_string = "$paternal_mother/$paternal_father";
        $pedigree_string =  "$maternal_parent_string//$paternal_parent_string";
    }
    elsif ($level eq "Great-Grandparents") {
        my $m_maternal_mother = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'mother'}}{'2'}{'mother'}}{'3'}{'mother'} || 'NA';
        my $m_maternal_father = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'mother'}}{'2'}{'father'}}{'3'}{'mother'} || 'NA';
        my $p_maternal_mother = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'mother'}}{'2'}{'mother'}}{'3'}{'father'} || 'NA';
        my $p_maternal_father = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'mother'}}{'2'}{'father'}}{'3'}{'father'} || 'NA';
        my $m_paternal_mother = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'father'}}{'2'}{'mother'}}{'3'}{'mother'} || 'NA';
        my $m_paternal_father = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'father'}}{'2'}{'father'}}{'3'}{'mother'} || 'NA';
        my $p_paternal_mother = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'father'}}{'2'}{'mother'}}{'3'}{'father'} || 'NA';
        my $p_paternal_father = $pedigree{$pedigree{$pedigree{$stock_name}{'1'}{'father'}}{'2'}{'father'}}{'3'}{'father'} || 'NA';
        my $mm_parent_string = "$m_maternal_mother/$m_maternal_father";
        my $mf_parent_string = "$p_maternal_mother/$p_maternal_father";
        my $pm_parent_string = "$m_paternal_mother/$m_paternal_father";
        my $pf_parent_string = "$p_paternal_mother/$p_paternal_father";
        $pedigree_string =  "$mm_parent_string//$mf_parent_string///$pm_parent_string//$pf_parent_string";
    }
    $c->stash->{rest} = { pedigree_string => $pedigree_string };
}

sub _get_pedigree_hash {
    my ($c, $accession_ids, $format) = @_;

    my $placeholders = join ( ',', ('?') x @$accession_ids );
    my $query = "
        WITH RECURSIVE included_rows(child, child_id, mother, mother_id, father, father_id, type, depth, path, cycle) AS (
                SELECT c.uniquename AS child,
                c.stock_id AS child_id,
                m.uniquename AS mother,
                m.stock_id AS mother_id,
                f.uniquename AS father,
                f.stock_id AS father_id,
                m_rel.value AS type,
                1,
                ARRAY[c.stock_id],
                false
                FROM stock c
                LEFT JOIN stock_relationship m_rel ON(c.stock_id = m_rel.object_id and m_rel.type_id = (SELECT cvterm_id FROM cvterm WHERE name = 'female_parent'))
                LEFT JOIN stock m ON(m_rel.subject_id = m.stock_id)
                LEFT JOIN stock_relationship f_rel ON(c.stock_id = f_rel.object_id and f_rel.type_id = (SELECT cvterm_id FROM cvterm WHERE name = 'male_parent'))
                LEFT JOIN stock f ON(f_rel.subject_id = f.stock_id)
                WHERE c.stock_id IN ($placeholders)
                GROUP BY 1,2,3,4,5,6,7,8,9,10
            UNION
                SELECT c.uniquename AS child,
                c.stock_id AS child_id,
                m.uniquename AS mother,
                m.stock_id AS mother_id,
                f.uniquename AS father,
                f.stock_id AS father_id,
                m_rel.value AS type,
                included_rows.depth + 1,
                path || c.stock_id,
                c.stock_id = ANY(path)
                FROM included_rows, stock c
                LEFT JOIN stock_relationship m_rel ON(c.stock_id = m_rel.object_id and m_rel.type_id = (SELECT cvterm_id FROM cvterm WHERE name = 'female_parent'))
                LEFT JOIN stock m ON(m_rel.subject_id = m.stock_id)
                LEFT JOIN stock_relationship f_rel ON(c.stock_id = f_rel.object_id and f_rel.type_id = (SELECT cvterm_id FROM cvterm WHERE name = 'male_parent'))
                LEFT JOIN stock f ON(f_rel.subject_id = f.stock_id)
                WHERE c.stock_id IN (included_rows.mother_id, included_rows.father_id) AND NOT cycle
                GROUP BY 1,2,3,4,5,6,7,8,9,10
        )
        SELECT child, mother, father, type, depth
        FROM included_rows
        GROUP BY 1,2,3,4,5
        ORDER BY 5,1;";

    my $sth = $c->dbc->dbh->prepare($query);
    $sth->execute(@$accession_ids);

    my %pedigree;
    no warnings 'uninitialized';
    while (my ($name, $mother, $father, $cross_type, $depth) = $sth->fetchrow_array()) {
        $pedigree{$name}{$depth}{'mother'} = $mother;
        $pedigree{$name}{$depth}{'father'} = $father;
    }
    return %pedigree;
}

sub stock_lookup : Path('/stock_lookup/') Args(2) ActionClass('REST') { }

sub stock_lookup_POST {
    my $self = shift;
    my $c = shift;
    my $lookup_from_field = shift;
    my $lookup_field = shift;
    my $value_to_lookup = $c->req->param($lookup_from_field);
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    #print STDERR $lookup_from_field;
    #print STDERR $lookup_field;
    #print STDERR $value_to_lookup;

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $s = $schema->resultset("Stock::Stock")->find( { $lookup_from_field => $value_to_lookup } );
    my $value;
    if ($s && $lookup_field eq 'stock_id') {
        $value = $s->stock_id();
    }
    $c->stash->{rest} = { $lookup_from_field => $value_to_lookup, $lookup_field => $value };
}

sub get_trial_related_stock:Chained('/stock/get_stock') PathPart('datatables/trial_related_stock') Args(0){
    my $self = shift;
    my $c = shift;
    my $stock_id = $c->stash->{stock_row}->stock_id();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema("Bio::Chado::Schema", 'sgn_chado');

    my $trial_related_stock = CXGN::Stock::RelatedStocks->new({dbic_schema => $schema, stock_id =>$stock_id});
    my $result = $trial_related_stock->get_trial_related_stock();
    my @stocks;
    foreach my $r (@$result){
      my ($stock_id, $stock_name, $cvterm_name) = @$r;
      my $url;
      if ($cvterm_name eq 'seedlot'){
          $url = qq{<a href = "/breeders/seedlot/$stock_id">$stock_name</a>};
      } else {
          $url = qq{<a href = "/stock/$stock_id/view">$stock_name</a>};
      }
      push @stocks, [$url, $cvterm_name, $stock_name];
    }

    $c->stash->{rest}={data=>\@stocks};
}

sub get_progenies:Chained('/stock/get_stock') PathPart('datatables/progenies') Args(0){
    my $self = shift;
    my $c = shift;
    my $stock_id = $c->stash->{stock_row}->stock_id();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema("Bio::Chado::Schema", 'sgn_chado');
    my $progenies = CXGN::Stock::RelatedStocks->new({dbic_schema => $schema, stock_id =>$stock_id});
    my $result = $progenies->get_progenies();
    my @stocks;
    foreach my $r (@$result){
      my ($cvterm_name, $stock_id, $stock_name) = @$r;
      push @stocks, [$cvterm_name, qq{<a href = "/stock/$stock_id/view">$stock_name</a>}, $stock_name];
    }

    $c->stash->{rest}={data=>\@stocks};
}

sub get_siblings:Chained('/stock/get_stock') PathPart('datatables/siblings') Args(0){
    my $self = shift;
    my $c = shift;
    my $stock_id = $c->stash->{stock_row}->stock_id();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema("Bio::Chado::Schema", 'sgn_chado');
    my $stock = CXGN::Stock->new({schema => $schema, stock_id=>$stock_id});
    my $parents = $stock->get_parents();
    my $female_parent = $parents->{'mother'};
    my $male_parent = $parents->{'father'};

    my @siblings;
    if ($female_parent) {
        my $family = CXGN::Cross->get_progeny_info($schema, $female_parent, $male_parent);
        foreach my $sib(@$family){
            my ($female_parent_id, $female_parent_name, $male_parent_id, $male_parent_name, $sibling_id, $sibling_name, $cross_type) = @$sib;
            if ($sibling_id != $stock_id) {
                push @siblings, [ qq{<a href="/stock/$sibling_id/view">$sibling_name</a>},
                qq{<a href="/stock/$female_parent_id/view">$female_parent_name</a>},
                qq{<a href="/stock/$male_parent_id/view">$male_parent_name</a>}, $cross_type, $sibling_name ];
            }
        }
    }
    $c->stash->{rest}={data=>\@siblings};
}

sub get_group_and_member:Chained('/stock/get_stock') PathPart('datatables/group_and_member') Args(0){
    my $self = shift;
    my $c = shift;
    my $stock_id = $c->stash->{stock_row}->stock_id();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema("Bio::Chado::Schema", 'sgn_chado');

    my $related_groups = CXGN::Stock::RelatedStocks->new({dbic_schema => $schema, stock_id =>$stock_id});
    my $result = $related_groups->get_group_and_member();
    my @group;

    foreach my $r (@$result){
        my ($stock_id, $stock_name, $cvterm_name) = @$r;
        if ($cvterm_name eq "cross"){
            push @group, [qq{<a href=\"/cross/$stock_id\">$stock_name</a>}, $cvterm_name, $stock_name];
        } else {
            push @group, [qq{<a href = "/stock/$stock_id/view">$stock_name</a>}, $cvterm_name, $stock_name];
        }
    }

    $c->stash->{rest}={data=>\@group};

}

sub get_stock_for_tissue:Chained('/stock/get_stock') PathPart('datatables/stock_for_tissue') Args(0){
    my $self = shift;
    my $c = shift;
    my $stock_id = $c->stash->{stock_row}->stock_id();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema("Bio::Chado::Schema", 'sgn_chado');

    my $tissue_stocks = CXGN::Stock::RelatedStocks->new({dbic_schema => $schema, stock_id =>$stock_id});
    my $result = $tissue_stocks->get_stock_for_tissue();
    my @stocks;
    foreach my $r (@$result){

      my ($stock_id, $stock_name, $cvterm_name) = @$r;

      push @stocks, [qq{<a href = "/stock/$stock_id/view">$stock_name</a>}, $cvterm_name, $stock_name];
    }

    $c->stash->{rest}={data=>\@stocks};

}

sub get_stock_datatables_genotype_data : Chained('/stock/get_stock') :PathPart('datatables/genotype_data') : ActionClass('REST') { }

sub get_stock_datatables_genotype_data_GET  {
    my $self = shift;
    my $c = shift;
    my $limit = $c->req->param('length') || 1000;
    my $offset = $c->req->param('start') || 0;
    my $stock_id = $c->stash->{stock_row}->stock_id();
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $schema = $c->dbic_schema("Bio::Chado::Schema", 'sgn_chado');
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $stock = CXGN::Stock->new({schema => $schema, stock_id => $stock_id});
    my $stock_type = $stock->type();

    my %genotype_search_params = (
        bcs_schema=>$schema,
        people_schema=>$people_schema,
        cache_root=>$c->config->{cache_file_path},
        genotypeprop_hash_select=>[],
        protocolprop_top_key_select=>[],
        protocolprop_marker_hash_select=>[],
        genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
    );
    if ($stock_type eq 'accession') {
        $genotype_search_params{accession_list} = [$stock_id];
    } elsif ($stock_type eq 'tissue_sample') {
        $genotype_search_params{tissue_sample_list} = [$stock_id];
    }
    my $genotypes_search = CXGN::Genotype::Search->new(\%genotype_search_params);
    my $file_handle = $genotypes_search->get_cached_file_search_json($c->config->{cluster_shared_tempdir}, 1); #only gets metadata and not all genotype data!

    my @result;
    my $counter = 0;

    open my $fh, "<& :encoding(UTF-8)", $file_handle or die "Can't open output file: $!";
    my $header_line = <$fh>;
    if ($header_line) {
        my $marker_objects = decode_json $header_line;

        my $start_index = $offset;
        my $end_index = $offset + $limit;
        # print STDERR Dumper [$start_index, $end_index];

        while (my $gt_line = <$fh>) {
            if ($counter >= $start_index && $counter < $end_index) {
                my $g = decode_json $gt_line;

                push @result, [
                    '<a href = "/breeders_toolbox/trial/'.$g->{genotypingDataProjectDbId}.'">'.$g->{genotypingDataProjectName}.'</a>',
                    $g->{genotypingDataProjectDescription},
                    $g->{analysisMethod},
                    $g->{genotypeDescription},
                    '<a href="/stock/'.$stock_id.'/genotypes?genotype_id='.$g->{genotypeDbId}.'">Download</a>'
                ];
            }
            $counter++;
        }
    }

    my $draw = $c->req->param('draw');
    if ($draw){
        $draw =~ s/\D//g; # cast to int
    }

    $c->stash->{rest} = { data => \@result, draw => $draw, recordsTotal => $counter,  recordsFiltered => $counter };
}

=head2 make_stock_obsolete

L<Catalyst::Action::REST> action.

Makes a stock entry obsolete in the database

=cut

sub stock_obsolete : Path('/stock/obsolete') : ActionClass('REST') { }

sub stock_obsolete_GET {
    my ( $self, $c ) = @_;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 'curator', 0, 0);

    my $stock_id = $c->req->param('stock_id');
    my $is_obsolete  = $c->req->param('is_obsolete');

	my $stock = $schema->resultset("Stock::Stock")->find( { stock_id => $stock_id } );

    if ($stock) {

        try {
            my $stock = CXGN::Stock->new({
                schema=>$schema,
                stock_id=>$stock_id,
                is_saving=>1,
                sp_person_id => $user_id,
                user_name => $user_name,
                modification_note => "Obsolete at ".localtime,
                is_obsolete => $is_obsolete
            });
            my $saved_stock_id = $stock->store();

            my $dbh = $c->dbc->dbh();
            my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
            my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'stockprop', 'concurrent', $c->config->{basepath});

            $c->stash->{rest} = { message => "Stock obsoleted" };
        } catch {
            $c->stash->{rest} = { error => "Failed: $_" }
        };
    } else {
	    $c->stash->{rest} = { error => "Not a valid stock $stock_id " };
	}

    #$c->stash->{rest} = { message => 'success' };
}


sub get_accessions_with_pedigree : Path('/ajax/stock/accessions_with_pedigree') : ActionClass('REST') { }

sub get_accessions_with_pedigree_GET {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 0, 0, 0);

    my $result = CXGN::Cross->get_progeny_info($schema);

    my @accessions_with_pedigree;
    foreach my $accession_info (@$result){
        my ($female_id, $female_name, $male_id, $male_name, $accession_id, $accession_name, $cross_type) =@$accession_info;
        push @accessions_with_pedigree, [ qq{<a href="/stock/$accession_id/view">$accession_name</a>},
            qq{<a href="/stock/$female_id/view">$female_name</a>},
            qq{<a href="/stock/$male_id/view">$male_name</a>}, $cross_type, $accession_name ];
    }
    print STDERR "ACCESSIONS =".Dumper(\@accessions_with_pedigree)."\n";
    $c->stash->{rest} = { data => \@accessions_with_pedigree };
}

sub stock_edit_details : Local : ActionClass('REST') { }
sub stock_edit_details_POST :Args(0) {
    my ($self, $c) = @_;
    # print STDERR Dumper $c->req->params();
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $phenome_schema = $c->dbic_schema('CXGN::Phenome::Schema');
    my ($user_id, $user_name, $user_role) = _check_user_login_stock($c, 'submitter', 0, 0);

    my $stock_id = $c->req->param('stock_id');
    my $private_company_id = $c->req->param('private_company_id');
    my $uniquename = $c->req->param('uniquename');
    my $description = $c->req->param('description');
    my $species = $c->req->param('species');
    my $is_private = $c->req->param('is_private') eq 'True' ? 1 : 0;

    my $stock = CXGN::Stock->new({
        schema => $schema,
        phenome_schema => $phenome_schema,
        stock_id => $stock_id
    });
    my $original_private_company_id = $stock->private_company_id();

    my $private_companies = CXGN::PrivateCompany->new( { schema=> $schema } );
    my ($private_companies_array, $private_companies_ids, $allowed_private_company_ids_hash, $allowed_private_company_access_hash, $private_company_access_is_private_hash) = $private_companies->get_users_private_companies($user_id, 0);

    if (!exists($allowed_private_company_ids_hash->{$original_private_company_id})) {
        $c->stash->{rest} = {error => "You are not in the company that owns this stock!"};
        $c->detach();
    }
    elsif ($allowed_private_company_access_hash->{$original_private_company_id} ne 'curator_access' && $allowed_private_company_access_hash->{$original_private_company_id} ne 'submitter_access') {
        $c->stash->{rest} = {error =>  "You do not have submitter or curator access in this company and cannot edit these details!" };
        return;
    }

    my $stock_store = CXGN::Stock->new({
        schema => $schema,
        is_saving => 1,
        phenome_schema => $phenome_schema,
        stock_id => $stock_id,
        species => $species,
        private_company_id => $private_company_id,
        private_company_stock_is_private => $is_private,
        uniquename => $uniquename,
        description => $description
    });
    my $return = $stock_store->store();

    $c->stash->{rest} = $return;
}

sub _check_user_login_stock {
    my $c = shift;
    my $check_priv = shift;
    my $original_private_company_id = shift;
    my $user_access = shift;

    my $login_check_return = CXGN::Login::_check_user_login($c, $check_priv, $original_private_company_id, $user_access);
    if ($login_check_return->{error}) {
        $c->stash->{rest} = $login_check_return;
        $c->detach();
    }
    my ($user_id, $user_name, $user_role) = @{$login_check_return->{info}};

    return ($user_id, $user_name, $user_role);
}

1;
