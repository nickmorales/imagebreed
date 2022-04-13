
package CXGN::List::Transform::Plugin::Companies2CompanyIds;

use Moose;
use Data::Dumper;

sub name {
    return "companies_2_companies_ids";
}

sub display_name {
    return "Company names to company IDs";
}

sub can_transform {
    my $self = shift;
    my $type1 = shift;
    my $type2= shift;

	return 1;
}

sub transform {
    my $self = shift;
    my $schema = shift;
    my $list = shift;

    my @transform = ();
    my @missing = ();

    my $q = "SELECT private_company_id FROM sgn_people.private_company WHERE name=?;";
    my $h = $schema->storage->dbh()->prepare($q);

    foreach my $term (@$list) {
        $h->execute($term);
        my ($private_company_id) = $h->fetchrow_array();
        if (!$private_company_id) {
            push @missing, $term;
        }
        else {
            push @transform, $private_company_id;
        }
    }
    $h = undef;

    # print STDERR " transform array = " . Dumper(@transform);
    # print STDERR " missing array = " . Dumper(@missing);
    return {
        transform => \@transform,
        missing   => \@missing,
    };
}

1;
