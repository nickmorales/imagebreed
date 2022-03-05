
package SGN::Controller::AJAX::Search::Trial;

use Moose;
use Data::Dumper;
use CXGN::Trial;
use CXGN::Trial::Search;
use JSON;
use CXGN::PrivateCompany;

BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
);

sub search : Path('/ajax/search/trials') Args(0) {
    my $self = shift;
    my $c    = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login($c);

    my @location_ids;
    my $location_id = $c->req->param('location_id');
    if ($location_id && $location_id ne 'not_provided'){
        #print STDERR "location id: " . $location_id . "\n";
        push @location_ids, $location_id;
    }

    my $checkbox_select_name = $c->req->param('select_checkbox_name');
    my $field_trials_only = $c->req->param('field_trials_only') || 1;
    my $trial_design_list = $c->req->param('trial_design') ? [$c->req->param('trial_design')] : [];
    my $private_company_ids_array = $c->req->param('private_company_ids') ? $c->req->param('private_company_ids') : [];

    if (scalar(@$private_company_ids_array)==0) {
        my $private_companies = CXGN::PrivateCompany->new( { schema=> $schema } );
        my ($private_companies_array, $private_companies_ids) = $private_companies->get_users_private_companies($user_id, 0);
        $private_company_ids_array = $private_companies_ids;
    }

    my $trial_search = CXGN::Trial::Search->new({
        bcs_schema=>$schema,
        location_id_list=>\@location_ids,
        field_trials_only=>$field_trials_only,
        trial_design_list=>$trial_design_list,
        private_company_ids_list=>$private_company_ids_array,
        sp_person_id=>$user_id,
        subscription_model=>$c->config->{subscription_model}
    });
    my ($data, $total_count) = $trial_search->search();
    my @result;
    my %selected_columns = ('plot_name'=>1, 'plot_id'=>1, 'block_number'=>1, 'plot_number'=>1, 'rep_number'=>1, 'row_number'=>1, 'col_number'=>1, 'accession_name'=>1, 'is_a_control'=>1);
    my $selected_columns_json = encode_json \%selected_columns;
    foreach (@$data){
        my $folder_string = '';
        if ($_->{folder_name}){
            $folder_string = "<a href=\"/folder/$_->{folder_id}\">$_->{folder_name}</a>";
        }
        my @res;
        if ($checkbox_select_name){
            push @res, "<input type='checkbox' name='$checkbox_select_name' value='$_->{trial_id}'>";
        }
        push @res, (
            "<a href=\"/breeders_toolbox/trial/$_->{trial_id}\">$_->{trial_name}</a>",
            $_->{description},
            "<a href=\"/company/$_->{private_company_id}\">$_->{private_company_name}</a>",
            "<a href=\"/breeders/program/$_->{breeding_program_id}\">$_->{breeding_program_name}</a>",
            $folder_string,
            $_->{year},
            $_->{location_name},
            $_->{trial_type},
            $_->{design},
            $_->{project_planting_date},
            $_->{project_harvest_date},
            "<a class='btn btn-sm btn-default' href='/breeders/trial/$_->{trial_id}/download/layout?format=csv&dataLevel=plots&selected_columns=$selected_columns_json'>Download Plot Layout</a>"
        );
        push @result, \@res;
    }
    #print STDERR Dumper \@result;

    $c->stash->{rest} = { data => \@result };
}

sub _check_user_login {
    my $c = shift;
    my $user_id;
    my $user_name;
    my $user_role;
    my $session_id = $c->req->param("sgn_session_id");

    if ($session_id){
        my $dbh = $c->dbc->dbh;
        my @user_info = CXGN::Login->new($dbh)->query_from_cookie($session_id);
        if (!$user_info[0]){
            $c->stash->{rest} = {error=>'You must be logged in!'};
            $c->detach();
        }
        $user_id = $user_info[0];
        $user_role = $user_info[1];
        my $p = CXGN::People::Person->new($dbh, $user_id);
        $user_name = $p->get_username;
    } else{
        if (!$c->user){
            $c->stash->{rest} = {error=>'You must be logged in!'};
            $c->detach();
        }
        $user_id = $c->user()->get_object()->get_sp_person_id();
        $user_name = $c->user()->get_object()->get_username();
        $user_role = $c->user->get_object->get_user_type();
    }

    return ($user_id, $user_name, $user_role);
}

1;
