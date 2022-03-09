
package SGN::Controller::DbStats;

use Moose;
use Data::Dumper;

BEGIN { extends 'Catalyst::Controller' };

sub dbstats :Path('/breeders/dbstats') Args(0) {
    my $self = shift;
    my $c = shift;

    if (!$c->user()) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        return;
    }
    my $sp_person_id = $c->user()->get_object()->get_sp_person_id();

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $projects = CXGN::BreedersToolbox::Projects->new( { schema=> $schema } );
    my $breeding_programs = $projects->get_breeding_programs($sp_person_id);
    #print STDERR Dumper $breeding_programs;

    $c->stash->{breeding_programs} = $breeding_programs;
    $c->stash->{template} = '/breeders_toolbox/db_stats.mas';
}

1;
