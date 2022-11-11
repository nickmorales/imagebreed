
package CXGN::Trial::Download::Plugin::TrialLayoutExcel;

=head1 NAME

CXGN::Trial::Download::Plugin::TrialLayoutCSV

=head1 SYNOPSIS

This plugin module is loaded from CXGN::Trial::Download

------------------------------------------------------------------

For downloading a trial's layout (as used from CXGN::Trial::Download->trial_download):

A trial's layout can optionally include treatment and phenotype summary
information, mapping to treatment_project_ids and trait_list.
These keys can be ignored if you don't need them in the layout.

As a XLS:
my $plugin = "TrialLayoutExcel";

As a CSV:
my $plugin = "TrialLayoutCSV";

my $download = CXGN::Trial::Download->new({
    bcs_schema => $schema,
    trial_id => $c->stash->{trial_id},
    trait_list => \@trait_list,
    filename => $tempfile,
    format => $plugin,
    data_level => $data_level,
    treatment_project_ids => \@treatment_project_ids,
    selected_columns => $selected_cols,
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
use Excel::Writer::XLSX;
use CXGN::Trial;
use CXGN::Trial::TrialLayoutDownload;
use CXGN::Trial::TrialLayout;
use List::MoreUtils ':all';

sub verify {
    return 1;
}

sub download {
    my $self = shift;

    print STDERR "DATALEVEL ".$self->data_level."\n";

    # Match a dot, extension .xls / .xlsx
    my ($extension) = $self->filename() =~ /(\.[^.]+)$/;
    my $ss;

    if ($extension eq '.xlsx') {
        $ss = Excel::Writer::XLSX->new($self->filename());
    }
    else {
        $ss = Spreadsheet::WriteExcel->new($self->filename());
    }

    my $ws = $ss->add_worksheet();

    my $trial_layout_download = CXGN::Trial::TrialLayoutDownload->new({
        schema => $self->bcs_schema,
        trial_id => $self->trial_id,
        data_level => $self->data_level,
        treatment_project_ids => $self->treatment_project_ids,
        selected_columns => $self->selected_columns,
        selected_trait_ids => $self->trait_list,
        include_measured => $self->include_measured
    });
    my $output = $trial_layout_download->get_layout_output();
    if ($output->{error_messages}){
        return $output;
    }

    if ($self->data_level eq 'plot_fieldMap'){
        my (@unique_col,@unique_row);
        my %hash = %{$output->{output}};
        my @all_col = @{$output->{cols}};
        my @all_rows = @{$output->{rows}};
        my ($min_col, $max_col) = minmax @all_col;
    	my ($min_row, $max_row) = minmax @all_rows;
    	for my $x (1..$max_col){
    		push @unique_col, $x;
    	}
    	for my $y (1..$max_row){
    		push @unique_row, $y;
    	}
        my $trial_layout = CXGN::Trial::TrialLayout->new({schema => $self->bcs_schema, trial_id => $self->trial_id, experiment_type => 'field_layout'});
        my $trial_name =  $trial_layout->get_trial_name();
        my $info = $trial_name."\nColumns\nRows";
        $ws->write( "A1", $info );
        my $row_num_label = 1;
        foreach my $l (@unique_row){
            my $col_num_label = 0;
            $ws->write( $row_num_label, $col_num_label, $l);
            $col_num_label++;
            $row_num_label++;
        }
        my $row_num_label_col = 1;
        foreach my $l (@unique_col){
            my $col_num_label_col = 0;
            $ws->write($col_num_label_col, $row_num_label_col, $l);
            $col_num_label_col++;
            $row_num_label_col++;
        }
        foreach my $row (keys %hash){
            my $cols = $hash{$row};
            foreach my $col (keys %$cols){
                my $accession = $hash{$row}->{$col};
                $ws->write($row, $col, $accession);
            }
        }
    } else {
        my @output_array = @{$output->{output}};
        my $row_num = 0;
        foreach my $l (@output_array){
            my $col_num = 0;
            foreach my $c (@$l){
                $ws->write($row_num, $col_num, $c);
                $col_num++;
            }
            $row_num++;
        }
    }

    $ss ->close();

}

1;
