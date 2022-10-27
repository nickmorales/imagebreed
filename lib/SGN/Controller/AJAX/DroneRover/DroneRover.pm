
=head1 NAME

SGN::Controller::AJAX::DroneRover::DroneRover - a REST controller class to provide the
functions for uploading and analyzing drone rover point clouds

=head1 DESCRIPTION

=head1 AUTHOR

=cut

package SGN::Controller::AJAX::DroneRover::DroneRover;

use Moose;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use SGN::Model::Cvterm;
use DateTime;
use CXGN::UploadFile;
use SGN::Image;
use CXGN::DroneImagery::ImagesSearch;
use URI::Encode qw(uri_encode uri_decode);
use File::Basename qw | basename dirname|;
use File::Slurp qw(write_file);
use File::Temp 'tempfile';
use File::Spec::Functions;
use File::Copy;
use CXGN::Calendar;
use Image::Size;
use Text::CSV;
use CXGN::Phenotypes::StorePhenotypes;
use CXGN::Phenotypes::PhenotypeMatrix;
use CXGN::BrAPI::FileResponse;
use CXGN::Onto;
use CXGN::Tag;
use CXGN::DroneImagery::ImageTypes;
use Time::Piece;
use POSIX;
use Math::Round;
use Parallel::ForkManager;
use CXGN::NOAANCDC;
use CXGN::BreederSearch;
use CXGN::Phenotypes::SearchFactory;
use CXGN::BreedersToolbox::Accessions;
use CXGN::Genotype::GRM;
use CXGN::Pedigree::ARM;
use CXGN::AnalysisModel::SaveModel;
use CXGN::AnalysisModel::GetModel;
use Math::Polygon;
use Math::Trig;
use List::MoreUtils qw(first_index);
use List::Util qw(sum);
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Spreadsheet::WriteExcel;
use Spreadsheet::ParseExcel;
use CXGN::Location;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);

sub drone_rover_get_vehicles : Path('/api/drone_rover/rover_vehicles') : ActionClass('REST') { }
sub drone_rover_get_vehicles_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $private_company_id = $c->req->param('private_company_id');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover($c, 'user', $private_company_id, 'user_access');

    my $private_companies_sql = '';
    if ($private_company_id) {
        $private_companies_sql = $private_company_id;
    }
    else {
        my $private_companies = CXGN::PrivateCompany->new( { schema => $bcs_schema } );
        my ($private_companies_array, $private_companies_ids, $allowed_private_company_ids_hash, $allowed_private_company_access_hash, $private_company_access_is_private_hash) = $private_companies->get_users_private_companies($user_id, 0);
        $private_companies_sql = join ',', @$private_companies_ids;
    }

    my $imaging_vehicle_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'imaging_event_vehicle_rover', 'stock_type')->cvterm_id();
    my $imaging_vehicle_properties_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'imaging_event_vehicle_json', 'stock_property')->cvterm_id();

    my $q = "SELECT stock.stock_id, stock.uniquename, stock.description, stock.private_company_id, company.name, stockprop.value
        FROM stock
        JOIN sgn_people.private_company AS company ON(stock.private_company_id=company.private_company_id)
        JOIN stockprop ON(stock.stock_id=stockprop.stock_id AND stockprop.type_id=$imaging_vehicle_properties_cvterm_id)
        WHERE stock.type_id=$imaging_vehicle_cvterm_id AND stock.private_company_id IN($private_companies_sql);";
    my $h = $bcs_schema->storage->dbh()->prepare($q);
    $h->execute();
    my @vehicles;
    while (my ($stock_id, $name, $description, $private_company_id, $private_company_name, $prop) = $h->fetchrow_array()) {
        my $prop_hash = decode_json $prop;
        my @batt_info;
        foreach (sort keys %{$prop_hash->{batteries}}) {
            my $p = $prop_hash->{batteries}->{$_};
            push @batt_info, "$_: Usage = ".$p->{usage}." Obsolete = ".$p->{obsolete};
        }
        my $batt_info_string = join '<br/>', @batt_info;
        my $private_company = "<a href='/company/$private_company_id'>$private_company_name</a>";
        push @vehicles, [$name, $description, $private_company, $batt_info_string]
    }

    $c->stash->{rest} = { data => \@vehicles };
}

sub _check_user_login_drone_rover {
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
