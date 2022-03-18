
package SGN::Controller::AJAX::Search::Trait;

use Moose;
use Data::Dumper;
use CXGN::Trait;
use CXGN::Trait::Search;
use CXGN::BreederSearch;


BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
);

sub search : Path('/ajax/search/traits') Args(0) {
    my $self = shift;
    my $c    = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $params = $c->req->params() || {};
    #print STDERR Dumper $params;

    my $user_id;
    my $user_name;
    my $user_role;
    my $session_id = $c->req->param("sgn_session_id");

    if ($session_id){
        my $dbh = $c->dbc->dbh;
        my @user_info = CXGN::Login->new($dbh)->query_from_cookie($session_id);
        if (!$user_info[0]){
            $c->stash->{rest} = {error=>'You must be logged in to do this!'};
            $c->detach();
        }
        $user_id = $user_info[0];
        $user_role = $user_info[1];
        my $p = CXGN::People::Person->new($dbh, $user_id);
        $user_name = $p->get_username;
    } else {
        if (!$c->user){
            $c->stash->{rest} = {error=>'You must be logged in to do this!'};
            $c->detach();
        }
        $user_id = $c->user()->get_object()->get_sp_person_id();
        $user_name = $c->user()->get_object()->get_username();
        $user_role = $c->user->get_object->get_user_type();
    }

    my $ontology_db_ids;
    if ($params->{'ontology_db_id[]'}){
        $ontology_db_ids = ref($params->{'ontology_db_id[]'}) eq 'ARRAY' ? $params->{'ontology_db_id[]'} : [$params->{'ontology_db_id[]'}];
    }

    my $rows = $params->{length};
    my $offset = $params->{start};
    my $limit = defined($offset) && defined($rows) ? ($offset+$rows)-1 : undef;

    my $trait_search_list_id = $params->{trait_search_list_id};

    my $subset_traits = [];
    if ($trait_search_list_id){
        my $list = CXGN::List->new({ dbh => $c->dbc->dbh, list_id => $trait_search_list_id });
        foreach (@{$list->elements()}){
            my @trait = split '\|', $_;
            pop @trait;
            my $trait_name = join '\|', @trait;
            push @$subset_traits, $trait_name;
        }
    }

    if ($params->{trait_any_name}){
        push @$subset_traits, $params->{trait_any_name};
    }

    my $definitions;
    if ($params->{trait_definition}){
        push @$definitions, $params->{trait_definition};
    }

    my $trait_search = CXGN::Trait::Search->new({
        bcs_schema=>$schema,
	is_variable=>1,
        ontology_db_id_list => $ontology_db_ids,
        limit => $limit,
        offset => $offset,
        trait_name_list => $subset_traits,
        trait_definition_list => $definitions
    });
    my ($data, $records_total) = $trait_search->search();
    my @result;

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh } );

    foreach (@$data){
        my $db_name = $_->{db_name};
        my $accession = $_->{accession};
        my $trait_id = $_->{trait_id};
        my $trait_accession = $db_name .":". $accession ;
        my $trait_usage = "<em>None</em>";

        # Get the number of trials that observed the trait
        my $trial_criteria_list  = ['traits', 'trials'];
        my $trial_dataref = {
            'trials' => {
                'traits' => $trait_id
            }
        };
        my $trial_queryref = {
            'trials' => {
                'traits' => 0
            }
        };
        my $trial_results_ref = $bs->metadata_query($trial_criteria_list, $trial_dataref, $trial_queryref);
        my $trials = $trial_results_ref->{results};
        my $trial_count = $#{$trials} + 1;

        # Get the number of plots that observed the trait
        if ( $trial_count && $trial_count > 0 ) {
            my $plot_criteria_list  = ['traits', 'plots'];
            my $plot_dataref = {
                'plots' => {
                    'traits' => $trait_id
                }
            };
            my $plot_queryref = {
                'plots' => {
                    'traits' => 0
                }
            };
            my $plot_results_ref = $bs->metadata_query($plot_criteria_list, $plot_dataref, $plot_queryref);
            my $plots = $plot_results_ref->{results};
            my $plot_count = $#{$plots} + 1;

            $trait_usage = "Trials:&nbsp;$trial_count<br />Plots:&nbsp;$plot_count";
        }


        push @result,
            [
                '',
                "<a href=\"/cvterm/$_->{trait_id}/view\">$trait_accession</a>",
                "<a href=\"/cvterm/$_->{trait_id}/view\">$_->{trait_name}</a>",
                $_->{trait_definition},
                $trait_usage,
                $_->{trait_name},
                $trait_accession
            ];
    }
    #print STDERR Dumper \@result;

    my $draw = $params->{draw};
    if ($draw){
        $draw =~ s/\D//g; # cast to int
    }

    $c->stash->{rest} = { data => [ @result ], draw => $draw, recordsTotal => $records_total,  recordsFiltered => $records_total };
}
