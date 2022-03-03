=head1 NAME

CXGN::PrivateCompany -


=head1 DESCRIPTION


=head1 AUTHOR

=cut

package CXGN::PrivateCompany;

use Moose;

use Data::Dumper;
use Bio::Chado::Schema;
use SGN::Model::Cvterm;

has 'schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1
);

has 'private_company_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'private_company_name' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_description' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_contact_email' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_contact_person_first_name' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_contact_person_last_name' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_contact_person_phone' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_address_street' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_address_street_2' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_address_state' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_address_city' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_address_zipcode' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_address_country' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_create_date' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_type_cvterm_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'private_company_type_name' => (
    isa => 'Str',
    is => 'rw',
);


sub BUILD {
    my $self = shift;

    if ($self->private_company_id){
        my $q = "SELECT private_company.private_company_id, private_company.name, private_company.description, private_company.contact_email, private_company.contact_person_first_name, private_company.contact_person_last_name, private_company.contact_person_phone, private_company.address_street, private_company.address_street_2, private_company.address_state, private_company.city, private_company.address_zipcode, private_company.address_country, private_company.create_date, private_company_type.cvterm_id, private_company_type.name
            FROM sgn_people.private_company AS private_company
            JOIN cvterm AS private_company_type ON(private_company.type_id=private_company_type.cvterm_id)
            WHERE private_company_id=?;";
        my $h = $self->schema->storage->dbh()->prepare($q);
        $h->execute($self->private_company_id);
        my ($private_company_id, $name, $description, $email, $first_name, $last_name, $phone, $address, $address2, $state, $city, $zipcode, $country, $create_date, $company_type_id, $company_type_name) = $h->fetchrow_array();

        $self->private_company_name($name);
        $self->private_company_description($description);
        $self->private_company_contact_email($email);
        $self->private_company_contact_person_first_name($first_name);
        $self->private_company_contact_person_last_name($last_name);
        $self->private_company_contact_person_phone($phone);
        $self->private_company_address_street($address);
        $self->private_company_address_street_2($address2);
        $self->private_company_address_state($state);
        $self->private_company_address_city($city);
        $self->private_company_address_zipcode($zipcode);
        $self->private_company_address_country($country);
        $self->private_company_create_date($create_date);
        $self->private_company_type_cvterm_id($company_type_id);
        $self->private_company_type_name($company_type_name);
    }
    return $self;
}

sub get_private_companies {
    my $self = shift;
    my $sp_person_id = shift;

    my $default_company_type_id = SGN::Model::Cvterm->get_cvterm_row($self->schema, 'default_access', 'company_type')->cvterm_id();

    my $q = "SELECT private_company.private_company_id, private_company.name, private_company.description, private_company.contact_email, private_company.contact_person_first_name, private_company.contact_person_last_name, private_company.contact_person_phone, private_company.address_street, private_company.address_street_2, private_company.address_state, private_company.city, private_company.address_zipcode, private_company.address_country, private_company.create_date, private_company_type.cvterm_id, private_company_type.name, user_type.cvterm_id, user_type.name
        FROM sgn_people.private_company AS private_company
        JOIN sgn_people.private_company_sp_person AS p ON(private_company.private_company_id=p.private_company_id)
        JOIN cvterm AS private_company_type ON(private_company.type_id=private_company_type.cvterm_id)
        JOIN cvterm AS user_type ON(p.type_id=user_type.cvterm_id)
        WHERE p.sp_person_id=? AND p.is_private='f' AND private_company_type.cvterm_id=?;";
    my $h = $self->schema->storage->dbh()->prepare($q);

    my $q2 = "SELECT p.sp_person_id, p.username, p.first_name, p.last_name, p.last_access_time, user_type.cvterm_id, user_type.name
        FROM sgn_people.private_company AS private_company
        JOIN sgn_people.private_company_sp_person AS sp ON(private_company.private_company_id=sp.private_company_id)
        JOIN cvterm AS private_company_type ON(private_company.type_id=private_company_type.cvterm_id)
        JOIN cvterm AS user_type ON(sp.type_id=user_type.cvterm_id)
        JOIN sgn_people.sp_person AS p ON(p.sp_person_id=sp.sp_person_id)
        WHERE private_company.private_company_id=? AND sp.is_private='f';";
    my $h2 = $self->schema->storage->dbh()->prepare($q2);
    $h->execute($sp_person_id,$default_company_type_id);

    my @private_companies;
    while (my ($private_company_id, $name, $description, $email, $first_name, $last_name, $phone, $address, $address2, $state, $city, $zipcode, $country, $create_date, $company_type_id, $company_type_name, $user_type_id, $user_type_name) = $h->fetchrow_array()){

        my @members;
        $h2->execute($private_company_id);
        while (my ($sp_person_id, $sp_username, $sp_first_name, $sp_last_name, $sp_last_access, $sp_user_type_id, $sp_user_type_name) = $h2->fetchrow_array()){
            push @members, [$sp_person_id, $sp_username, $sp_first_name, $sp_last_name, $sp_last_access, $sp_user_type_id, $sp_user_type_name];
        }

        push @private_companies, [$private_company_id, $name, $description, $email, $first_name, $last_name, $phone, $address, $address2, $state, $city, $zipcode, $country, $create_date, $company_type_id, $company_type_name, $user_type_id, $user_type_name, \@members];
    }
    # print STDERR Dumper \@private_companies;
    return \@private_companies;
}

1;
