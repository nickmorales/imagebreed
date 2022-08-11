package SGN::Controller::AJAX::GenotypingProject;

use Moose;
use JSON;
use Data::Dumper;
use CXGN::Login;
use List::MoreUtils qw /any /;

use CXGN::Genotype::StoreGenotypingProject;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);


sub add_genotyping_project : Path('/ajax/breeders/add_genotyping_project') : ActionClass('REST') {}

sub add_genotyping_project_POST :Args(0){
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $dbh = $c->dbc->dbh;
    my $project_name = $c->req->param('project_name');
    my $project_breeding_program = $c->req->param('project_breeding_program');
    my $project_facility = $c->req->param('project_facility');
    my $project_year = $c->req->param('project_year');
    my $project_description = $c->req->param('project_description');
    my $project_location = $c->req->param('project_location');
    my $data_type = $c->req->param('data_type');

    my ($user_id, $user_name, $user_role) = _check_user_login_genotyping_project($c, 'submitter', 0, 0);

    my $error;
    eval{
        my $add_genotyping_project = CXGN::Genotype::StoreGenotypingProject->new({
            chado_schema => $schema,
            dbh => $dbh,
            project_name => $project_name,
            breeding_program_id => $project_breeding_program,
            project_facility => $project_facility,
            data_type => $data_type,
            year => $project_year,
            project_description => $project_description,
            nd_geolocation_id => $project_location,
            owner_id => $user_id
        });
        my $store_return = $add_genotyping_project->store_genotyping_project();
        if ($store_return->{error}){
            $error = $store_return->{error};
        }
    };

    if ($@) {
        $c->stash->{rest} = {error => $@};
        return;
    };

    if ($error){
        $c->stash->{rest} = {error => $error};
    } else {
        $c->stash->{rest} = {success => 1};
    }

}

sub _check_user_login_genotyping_project {
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
