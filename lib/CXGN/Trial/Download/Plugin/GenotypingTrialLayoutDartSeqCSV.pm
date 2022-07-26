
package CXGN::Trial::Download::Plugin::GenotypingTrialLayoutDartSeqCSV;

=head1 NAME

CXGN::Trial::Download::Plugin::GenotypingTrialLayoutDartSeqCSV

=head1 SYNOPSIS

This plugin module is loaded from CXGN::Trial::Download

------------------------------------------------------------------

For downloading a genotyping plate's layout (as used from CXGN::Trial::Download->trial_download):

my $plugin = "GenotypingTrialLayoutDartSeqCSV";

my $download = CXGN::Trial::Download->new({
    bcs_schema => $schema,
    trial_id => $c->stash->{trial_id},
    trial_list => \@trial_id_list,
    filename => $tempfile,
    format => $plugin,
});
my $error = $download->download();
my $file_name = $trial_id . "_" . "$what" . ".$format";
$c->res->content_type('Application/'.$format);
$c->res->header('Content-Disposition', qq[attachment; filename="$file_name"]);
my $output = read_file($tempfile);
$c->res->body($output);


=head1 AUTHORS

=cut

use Moose::Role;
use Data::Dumper;
use Spreadsheet::WriteExcel;
use CXGN::Trial;
use CXGN::Trial::TrialLayout;
use Text::CSV;

sub verify {
    return 1;
}

sub download {
    my $self = shift;

    print STDERR "DATALEVEL ".$self->data_level."\n";

    open(my $F, ">:encoding(utf8)", $self->filename()) || die "Can't open file ".$self->filename();

    my $csv = Text::CSV->new({eol => $/});

    my @header = ('PlateID', 'Row', 'Column', 'Organism', 'Species', 'Genotype', 'Tissue', 'Comments');
    $csv->print($F, \@header);

    my @trial_ids;
    if ($self->trial_id) {
        push @trial_ids, $self->trial_id;
    }
    if ($self->trial_list) {
        push @trial_ids, @{$self->trial_list};
    }

    foreach (@trial_ids) {
        my $trial = CXGN::Trial->new( { bcs_schema => $self->bcs_schema, trial_id => $_ });
        my $trial_name = $trial->get_name();
        my $trial_layout = CXGN::Trial::TrialLayout->new({schema => $self->bcs_schema, trial_id => $_, experiment_type => 'genotyping_layout'});
        my $design = $trial_layout->get_design();
        #print STDERR Dumper $design;

        my $q = "SELECT common_name FROM organism WHERE species = ?;";
        my $h = $self->bcs_schema->storage->dbh()->prepare($q);

        my @plot_design = values %$design;
        @plot_design = sort { $a->{col_number} <=> $b->{col_number} || $a->{row_number} cmp $b->{row_number} } @plot_design;

        foreach my $val (@plot_design){
            my $notes = $val->{notes} || 'NA';
            my $acquisition_date = $val->{acquisition_date} || 'NA';
            my $concentration = $val->{concentration} || 'NA';
            my $volume = $val->{volume} || 'NA';
            my $dna_person = $val->{dna_person} || 'NA';
            my $extraction = $val->{extraction} || 'NA';
            my $facility_identifier = $val->{facility_identifier} || 'NA';
            my $comments = 'Notes: '.$notes.' AcquisitionDate: '.$acquisition_date.' Concentration: '.$concentration.' Volume: '.$volume.' Person: '.$dna_person.' Extraction: '.$extraction.' Facility Identifier: '.$facility_identifier;
            my $sample_name = $val->{plot_name}."|||".$val->{accession_name};

            $h->execute($val->{species});
            my ($common_name) = $h->fetchrow_array();

            if (!$val->{is_blank}) {
                my $o = [
                    $trial_name,
                    $val->{row_number},
                    $val->{col_number},
                    $common_name,
                    $val->{species},
                    $sample_name,
                    $val->{tissue_type},
                    $comments
                ];
                $csv->print($F, $o);
            }
        }
        $h = undef;
    }
    close($F);
}

1;
