package SGN::Controller::Company;

use Moose;
use Data::Dumper;
use Try::Tiny;
use SGN::Model::Cvterm;
use Data::Dumper;
use URI::FromHash 'uri';

BEGIN { extends 'Catalyst::Controller'; }

sub company_page :Path("/company") Args(1) {
    my $self = shift;
    my $c = shift;
    my $company_id = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');

    if (!$c->user()) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        return;
    }
    my $sp_person_id = $c->user()->get_object()->get_sp_person_id();

    my $private_company = CXGN::PrivateCompany->new({
        schema=> $schema,
        private_company_id => $company_id,
        sp_person_id => $sp_person_id
    });
    my $name = $private_company->private_company_name();

    if (!$name) {
        $c->stash->{message} = "The requested company does not exist or has been deleted.";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $q = "SELECT s.administrator FROM sgn_people.sp_person AS s WHERE s.sp_person_id=?;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($sp_person_id);
    my ($person_administrator) = $h->fetchrow_array();

    my $description = $private_company->private_company_description();
    my $contact_email = $private_company->private_company_contact_email();
    my $contact_first_name = $private_company->private_company_contact_person_first_name();
    my $contact_last_name = $private_company->private_company_contact_person_last_name();
    my $contact_phone = $private_company->private_company_contact_person_phone();
    my $address_street = $private_company->private_company_address_street();
    my $address_street_2 = $private_company->private_company_address_street_2();
    my $state = $private_company->private_company_address_state();
    my $city = $private_company->private_company_address_city();
    my $zipcode = $private_company->private_company_address_zipcode();
    my $country = $private_company->private_company_address_country();
    my $create_date = $private_company->private_company_create_date();
    my $company_type_cvterm_id = $private_company->private_company_type_cvterm_id();
    my $company_type_cvterm_name = $private_company->private_company_type_name();
    my $sp_person_access_cvterm_id = $private_company->sp_person_access_cvterm_id();
    my $sp_person_access_cvterm_name = $private_company->sp_person_access_cvterm_name();
    my $company_members = $private_company->private_company_members();

    $c->stash->{administrator} = $person_administrator;
    $c->stash->{private_company_id} = $company_id;
    $c->stash->{name} = $name;
    $c->stash->{description} = $description;
    $c->stash->{contact_email} = $contact_email;
    $c->stash->{contact_first_name} = $contact_first_name;
    $c->stash->{contact_last_name} = $contact_last_name;
    $c->stash->{contact_phone} = $contact_phone;
    $c->stash->{address_street} = $address_street;
    $c->stash->{address_street_2} = $address_street_2;
    $c->stash->{state} = $state;
    $c->stash->{city} = $city;
    $c->stash->{zipcode} = $zipcode;
    $c->stash->{country} = $country;
    $c->stash->{create_date} = $create_date;
    $c->stash->{company_type_cvterm_id} = $company_type_cvterm_id;
    $c->stash->{company_type_cvterm_name} = $company_type_cvterm_name;
    $c->stash->{company_sp_person_access_cvterm_id} = $sp_person_access_cvterm_id;
    $c->stash->{company_sp_person_access_cvterm_name} = $sp_person_access_cvterm_name;
    $c->stash->{company_members} = $company_members;

    $c->stash->{template} = '/breeders_toolbox/private_companies/private_company.mas';
}

1;
