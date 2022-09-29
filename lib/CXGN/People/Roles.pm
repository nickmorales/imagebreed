
=head1 NAME

CXGN::People::Roles - helper class for people's roles

=head1 SYNOPSYS

 my $person_roles = CXGN::Person::Roles->new( { bcs_schema => $schema } );

 etc.

=head1 AUTHOR

Nicolas Morales <nm529@cornell.edu>

=head1 METHODS

=cut

package CXGN::People::Roles;

use Moose;
use Try::Tiny;
use SGN::Model::Cvterm;
use Data::Dumper;
use Text::Unidecode;

has 'bcs_schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
);

sub add_sp_role {
    my $self = shift;
    my $name = shift;
    my $dbh = $self->bcs_schema->storage->dbh;

    my $q = "SELECT sp_role_id FROM sgn_people.sp_roles where name=?;";
    my $sth = $dbh->prepare($q);
    $sth->execute($name);
    my $count = $sth->rows;
    $sth = undef;

    if ($count > 0){
        print STDERR "A role with that name already exists.\n";
        return;
    }
    eval {
        my $q = "INSERT INTO sgn_people.sp_roles (name) VALUES (?);";
        my $sth = $dbh->prepare($q);
        $sth->execute($name);
        $sth = undef;
    };
    if ($@) {
        return "An error occurred while storing a new role. ($@)";
    }
}

sub update_sp_role {
    my $self = shift;
    my $new_name = shift;
    my $old_name = shift;
    my $dbh = $self->bcs_schema->storage->dbh;

    my $q_select = "SELECT sp_role_id FROM sgn_people.sp_roles where name=?;";
    my $sth_select = $dbh->prepare($q_select);
    $sth_select->execute($old_name);
    my $count = $sth_select->rows;
    $sth_select = undef;

    if ($count < 1){
        print STDERR "No role with that name exists.\n";
        return;
    }

    my $q_update = "UPDATE sgn_people.sp_roles SET name = ? WHERE name = ?;";
    my $sth_update = $dbh->prepare($q_update);
    $sth_update->execute($new_name, $old_name);
    $sth_update = undef;
    return;
}

sub get_breeding_program_roles {
    my $self = shift;
    my $ascii_chars = shift;
    my $dbh = $self->bcs_schema->storage->dbh;
    my @breeding_program_roles;

    my $q = "SELECT username, sp_person_id, name FROM sgn_people.sp_person_roles JOIN sgn_people.sp_person using(sp_person_id) JOIN sgn_people.sp_roles using(sp_role_id)";
    my $sth = $dbh->prepare($q);
    $sth->execute();
    while (my ($username, $sp_person_id, $sp_role) = $sth->fetchrow_array ) {
        if ($ascii_chars) {
            $username = unidecode($username);
        }
        push(@breeding_program_roles, [$username, $sp_person_id, $sp_role] );
    }
    $sth = undef;

    #print STDERR Dumper \@breeding_program_roles;
    return \@breeding_program_roles;
}

sub add_sp_person_role {
    my $self = shift;
    my $sp_person_id = shift;
    my $sp_role_id = shift;
    my $dbh = $self->bcs_schema->storage->dbh;
    my $q = "INSERT INTO sgn_people.sp_person_roles (sp_person_id, sp_role_id) VALUES (?,?);";
    my $sth = $dbh->prepare($q);
    $sth->execute($sp_person_id, $sp_role_id);
    $sth = undef;
    return;
}

sub remove_sp_person_role {
    my $self = shift;
    my $sp_person_id = shift;
    my $sp_role_name = shift;

    my $q = "SELECT sp_role_id FROM sgn_people.sp_roles where name=?;";
    my $sth = $self->bcs_schema->storage->dbh->prepare($q);
    $sth->execute($sp_role_name);
    my ($sp_role_id) = $sth->fetchrow_array();
    $sth = undef;

    my $q1 = "DELETE FROM sgn_people.sp_person_roles WHERE sp_person_id=? AND sp_role_id=?;";
    my $sth1 = $self->bcs_schema->storage->dbh->prepare($q1);
    $sth1->execute($sp_person_id, $sp_role_id);
    $sth1 = undef;
    return;
}

sub get_sp_persons {
    my $self = shift;
    my $dbh = $self->bcs_schema->storage->dbh;
    my @sp_persons;
    my $q = "SELECT username, sp_person_id FROM sgn_people.sp_person ORDER BY username ASC;";
    my $sth = $dbh->prepare($q);
    $sth->execute();
    while (my ($username, $sp_person_id) = $sth->fetchrow_array ) {
        push(@sp_persons, [$username, $sp_person_id] );
    }
    $sth = undef;
    return \@sp_persons;
}

sub get_sp_roles {
    my $self = shift;
    my $dbh = $self->bcs_schema->storage->dbh;
    my @sp_roles;
    my $q = "SELECT name, sp_role_id FROM sgn_people.sp_roles;";
    my $sth = $dbh->prepare($q);
    $sth->execute();
    while (my ($name, $sp_role_id) = $sth->fetchrow_array ) {
        push(@sp_roles, [$name, $sp_role_id] );
    }
    $sth = undef;
    return \@sp_roles;
}

1;
