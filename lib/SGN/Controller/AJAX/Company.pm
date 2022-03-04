
=head1 NAME

SGN::Controller::AJAX::Company - a REST controller class to provide the
backend for managing company

=head1 DESCRIPTION


=cut

package SGN::Controller::AJAX::Company;

use Moose;
use Data::Dumper;
use Try::Tiny;
use JSON;
use SGN::Model::Cvterm;
use CXGN::PrivateCompany;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);

sub add_company : Path('/ajax/private_company/create_company') : ActionClass('REST') { }
sub add_company_POST : Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    if (!$c->user()) {
        $c->stash->{rest} = {error => 'Please login to add a new company!' };
        return;
    }
    my $sp_person_id = $c->user()->get_object()->get_sp_person_id();

    my $private_company = CXGN::PrivateCompany->new({
        schema=> $schema,
        sp_person_id => $sp_person_id,
        private_company_name => $c->req->param('name'),
        private_company_description => $c->req->param('description'),
        private_company_contact_email => $c->req->param('contact_email'),
        private_company_contact_person_first_name => $c->req->param('contact_first_name'),
        private_company_contact_person_last_name => $c->req->param('contact_last_name'),
        private_company_contact_person_phone => $c->req->param('contact_phone'),
        private_company_address_street => $c->req->param('address_street'),
        private_company_address_street_2 => $c->req->param('address_street_2'),
        private_company_address_state => $c->req->param('address_state'),
        private_company_address_city => $c->req->param('address_city'),
        private_company_address_zipcode => $c->req->param('address_zipcode'),
        private_company_address_country => $c->req->param('address_country'),
        private_company_create_date => $c->req->param('contact_email'),
        private_company_type_cvterm_id => SGN::Model::Cvterm->get_cvterm_row($schema, $c->req->param('company_access_type'), 'company_type')->cvterm_id()
    });
    my $return = $private_company->store_private_company();

    $c->stash->{rest} = $return;
}

sub edit_company : Path('/ajax/private_company/edit_company') : ActionClass('REST') { }
sub edit_company_POST : Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    if (!$c->user()) {
        $c->stash->{rest} = {error => 'Please login to edit a company!' };
        return;
    }
    my $sp_person_id = $c->user()->get_object()->get_sp_person_id();

    my $private_company = CXGN::PrivateCompany->new({
        schema=> $schema,
        sp_person_id => $sp_person_id,
        is_storing_or_editing => 1,
        private_company_id => $c->req->param('private_company_id'),
        private_company_name => $c->req->param('name'),
        private_company_description => $c->req->param('description'),
        private_company_contact_email => $c->req->param('contact_email'),
        private_company_contact_person_first_name => $c->req->param('contact_first_name'),
        private_company_contact_person_last_name => $c->req->param('contact_last_name'),
        private_company_contact_person_phone => $c->req->param('contact_phone'),
        private_company_address_street => $c->req->param('address_street'),
        private_company_address_street_2 => $c->req->param('address_street_2'),
        private_company_address_state => $c->req->param('address_state'),
        private_company_address_city => $c->req->param('address_city'),
        private_company_address_zipcode => $c->req->param('address_zipcode'),
        private_company_address_country => $c->req->param('address_country'),
        private_company_create_date => $c->req->param('contact_email'),
        private_company_type_cvterm_id => SGN::Model::Cvterm->get_cvterm_row($schema, $c->req->param('company_access_type'), 'company_type')->cvterm_id()
    });
    my $return = $private_company->edit_private_company();

    $c->stash->{rest} = $return;
}

sub add_company_member : Path('/ajax/private_company/add_company_member') : ActionClass('REST') { }
sub add_company_member_POST : Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    if (!$c->user()) {
        $c->stash->{rest} = {error => 'Please login to add a company member!' };
        return;
    }
    my $sp_person_id = $c->user()->get_object()->get_sp_person_id();

    my $private_company = CXGN::PrivateCompany->new({
        schema=> $schema,
        sp_person_id => $sp_person_id,
        is_storing_or_editing => 1,
        private_company_id => $c->req->param('private_company_id'),
    });
    my $return = $private_company->add_private_company_member([$c->req->param('add_sp_person_id'), $c->req->param('company_person_access_type')]);

    $c->stash->{rest} = $return;
}

sub remove_company_member : Path('/ajax/private_company/remove_company_member') : ActionClass('REST') { }
sub remove_company_member_POST : Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    if (!$c->user()) {
        $c->stash->{rest} = {error => 'Please login to remove a company member!' };
        return;
    }
    my $sp_person_id = $c->user()->get_object()->get_sp_person_id();

    my $private_company = CXGN::PrivateCompany->new({
        schema=> $schema,
        sp_person_id => $sp_person_id,
        is_storing_or_editing => 1,
        private_company_id => $c->req->param('private_company_id'),
    });
    my $return = $private_company->remove_private_company_member($c->req->param('remove_sp_person_id'));

    $c->stash->{rest} = $return;
}

sub edit_company_member : Path('/ajax/private_company/edit_company_member') : ActionClass('REST') { }
sub edit_company_member_POST : Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    # print STDERR Dumper $c->req->params();

    if (!$c->user()) {
        $c->stash->{rest} = {error => 'Please login to edit a company member!' };
        return;
    }
    my $sp_person_id = $c->user()->get_object()->get_sp_person_id();

    my $private_company = CXGN::PrivateCompany->new({
        schema=> $schema,
        sp_person_id => $sp_person_id,
        is_storing_or_editing => 1,
        private_company_id => $c->req->param('private_company_id'),
    });
    my $return = $private_company->edit_private_company_member([$c->req->param('edit_sp_person_id'), $c->req->param('access_type')]);

    $c->stash->{rest} = $return;
}

1;
