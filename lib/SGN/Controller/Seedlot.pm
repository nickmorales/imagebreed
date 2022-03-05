
package SGN::Controller::Seedlot;

use Moose;

BEGIN { extends 'Catalyst::Controller'; }

use CXGN::Stock::Seedlot;
use Data::Dumper;
use JSON::XS;
use URI::FromHash 'uri';

sub seedlots :Path('/breeders/seedlots') :Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    if (!$c->user()) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        return;
    }

    $c->stash->{preferred_species} = $c->config->{preferred_species};
    $c->stash->{timestamp} = localtime;

    my $user_role;
    if ($c->user() && $c->user()->check_roles("curator")) {
        $user_role = "curator";
    }

    my @editable_stock_props = split ',', $c->config->{editable_stock_props};
    my %editable_stock_props = map { $_=>1 } @editable_stock_props;

    my @editable_stock_props_definitions = split ',', $c->config->{editable_stock_props_definitions};
    my %def_hash;
    foreach (@editable_stock_props_definitions) {
        my @term_def = split ':', $_;
        $def_hash{$term_def[0]} = $term_def[1];
    }

    my $projects = CXGN::BreedersToolbox::Projects->new( { schema=> $schema } );
    my $breeding_programs = $projects->get_breeding_programs();

    $c->stash->{editable_stock_props} = \%editable_stock_props;
    $c->stash->{editable_stock_props_definitions} = \%def_hash;
    $c->stash->{crossing_trials} = $projects->get_crossing_trials();
    $c->stash->{locations} = JSON::XS->new->decode($projects->get_location_geojson());
    $c->stash->{programs} = $breeding_programs;
    $c->stash->{user_role} = $user_role;
    $c->stash->{template} = '/breeders_toolbox/seedlots.mas';
}

sub seedlot_detail :Path('/breeders/seedlot') Args(1) {
    my $self = shift;
    my $c = shift;
    my $seedlot_id = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");

    my $sl = CXGN::Stock::Seedlot->new(
        schema => $schema,
        phenome_schema => $phenome_schema,
        seedlot_id => $seedlot_id
    );
    my @content_accession_names;
    my @content_cross_names;
    my $accessions = $sl->accession();
    my $accessions_html = '';
    if ($accessions){
        $accessions_html .= '<a href="/stock/'.$accessions->[0].'/view">'.$accessions->[1].'</a> (accession)';
        push @content_accession_names, $accessions->[1];
    }
    my $crosses = $sl->cross();
    my $crosses_html = '';
    if ($crosses){
        $crosses_html .= '<a href="/cross/'.$crosses->[0].'">'.$crosses->[1].'</a> (cross)';
        push @content_cross_names, $crosses->[1];
    }
    my $populations = $sl->populations();
    my $populations_html = '';
    foreach (@$populations){
        $populations_html .= '<a href="/stock/'.$_->[0].'/view">'.$_->[1].'</a> ';
    }
    my $owners = $sl->owners;
    my $owners_string = '';
    foreach (@$owners){
        my $p = $people_schema->resultset("SpPerson")->find({sp_person_id=>$_});
        $owners_string .= ' <a href="/solpeople/personal-info.pl?sp_person_id='.$p->sp_person_id.'">'.$p->username.'</a>';
    }
    $c->stash->{seedlot_id} = $seedlot_id;
    $c->stash->{uniquename} = $sl->uniquename();
    $c->stash->{organization_name} = $sl->organization_name();
    $c->stash->{box_name} = $sl->box_name();
    $c->stash->{population_name} = $populations_html;
    $c->stash->{content_html} = $accessions_html ? $accessions_html : $crosses_html;
    $c->stash->{content_accession_name} = $content_accession_names[0];
    $c->stash->{content_cross_name} = $content_cross_names[0];
    $c->stash->{current_count} = $sl->get_current_count_property();
    $c->stash->{current_weight} = $sl->get_current_weight_property();
    $c->stash->{quality} = $sl->quality();
    $c->stash->{owners_string} = $owners_string;
    $c->stash->{timestamp} = localtime();
    $c->stash->{template} = '/breeders_toolbox/seedlot_details.mas';
}

1;
