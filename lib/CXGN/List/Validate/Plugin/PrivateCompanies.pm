
package CXGN::List::Validate::Plugin::PrivateCompanies;

use Moose;
use Data::Dumper;

sub name {
    return "private_companies";
}

sub validate {
    my $self = shift;
    my $schema = shift;
    my $list = shift;
    my @missing = ();

    my $q = "SELECT private_company_id FROM sgn_people.private_company WHERE name=?;";
    my $h = $schema->storage->dbh()->prepare($q);

    foreach my $term (@$list) {
        $h->execute($term);
        my ($private_company_id) = $h->fetchrow_array();
        if (!$private_company_id) {
            push @missing, $term;
        }
    }

    return { missing => \@missing };
}

1;
