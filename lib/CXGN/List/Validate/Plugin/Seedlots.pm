
package CXGN::List::Validate::Plugin::Seedlots;

use Moose;

use Data::Dumper;
use SGN::Model::Cvterm;

sub name {
    return "seedlots";
}

sub validate {
    my $self = shift;
    my $schema = shift;
    my $list = shift;

    my %all_names;
    my $synonym_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stock_synonym', 'stock_property')->cvterm_id();
    my $type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'seedlot', 'stock_type')->cvterm_id();
    my $q = "SELECT stock.uniquename, stockprop.value, stockprop.type_id FROM stock LEFT JOIN stockprop USING(stock_id) WHERE stock.type_id=$type_id AND stock.is_obsolete = 'F';";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute();
    my %result;
    while (my ($uniquename, $synonym, $type_id) = $h->fetchrow_array()) {
        $all_names{$uniquename}++;
        if ($type_id) {
            if ($type_id == $synonym_type_id) {
                $all_names{$synonym}++;
            }
        }
    }
    $h = undef;

    #print STDERR Dumper \%all_names;
    my @missing;
    foreach my $item (@$list) {
        if (!exists($all_names{$item})) {
            push @missing, $item;
        }
    }

    return { missing => \@missing };
}

1;
