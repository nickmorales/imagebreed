package CXGN::Trial::ParseUpload::Plugin::TrialSubplotsWithNumberOfSubplotsXLS;

use Moose::Role;
use Spreadsheet::ParseExcel;
use CXGN::Stock::StockLookup;
use SGN::Model::Cvterm;
use Data::Dumper;
use CXGN::List::Validate;

sub _validate_with_plugin {
    my $self = shift;

    my $filename = $self->get_filename();
    my $schema = $self->get_chado_schema();
    my $parser = Spreadsheet::ParseExcel->new();
    my @error_messages;
    my %errors;
    my %missing_accessions;

    #try to open the excel file and report any errors
    my $excel_obj = $parser->parse($filename);
    if (!$excel_obj) {
        push @error_messages, $parser->error();
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }

    my $worksheet = ( $excel_obj->worksheets() )[0]; #support only one worksheet
    if (!$worksheet) {
        push @error_messages, "Spreadsheet must be on 1st tab in Excel (.xls) file";
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }
    my ( $row_min, $row_max ) = $worksheet->row_range();
    my ( $col_min, $col_max ) = $worksheet->col_range();
    if (($col_max - $col_min)  < 1 || ($row_max - $row_min) < 1 ) { #must have header and at least one row of plot data
        push @error_messages, "Spreadsheet is missing header or contains no rows";
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }

    #get column headers
    my $plot_name_head;
    my $num_subplots_per_plot_head;

    if ($worksheet->get_cell(0,0)) {
        $plot_name_head  = $worksheet->get_cell(0,0)->value();
    }
    if ($worksheet->get_cell(0,1)) {
        $num_subplots_per_plot_head  = $worksheet->get_cell(0,1)->value();
    }
    if (!$plot_name_head || $plot_name_head ne 'plot_name' ) {
        push @error_messages, "Cell A1: plot_name is missing from the header";
    }
    if (!$num_subplots_per_plot_head || $num_subplots_per_plot_head ne 'num_subplots_per_plot') {
        push @error_messages, "Cell B1: num_subplots_per_plot is missing from the header";
    }

    my %seen_plot_names;
    my %seen_subplot_names;
    for my $row ( 1 .. $row_max ) {
        my $row_name = $row+1;
        my $plot_name;
        my $num_subplots_per_plot;

        if ($worksheet->get_cell($row,0)) {
            $plot_name = $worksheet->get_cell($row,0)->value();
        }
        if ($worksheet->get_cell($row,1)) {
            $num_subplots_per_plot = $worksheet->get_cell($row,1)->value();
        }

        if (!$plot_name || $plot_name eq '' ) {
            push @error_messages, "Cell A$row_name: plot_name missing.";
        }
        elsif ($plot_name =~ /\s/ || $plot_name =~ /\// || $plot_name =~ /\\/ ) {
            push @error_messages, "Cell A$row_name: plot_name must not contain spaces or slashes.";
        }
        else {
            $seen_plot_names{$plot_name}=$row_name;
        }

        if (!$num_subplots_per_plot || $num_subplots_per_plot eq '') {
            push @error_messages, "Cell B$row_name: num_subplots_per_plot missing";
        } if (!($num_subplots_per_plot =~ /^\d+?$/)) {
            push @error_messages, "Cell B$row_name: num_subplots_per_plot must be a number";
        } else {
            #file must not contain duplicate subplot names
            for my $i (1 .. $num_subplots_per_plot) {
                my $subplot_name = $plot_name."_subplot".$i;
                if ($seen_subplot_names{$subplot_name}) {
                    push @error_messages, "Cell B$row_name: duplicate subplot_name at cell A".$seen_subplot_names{$subplot_name}.": $subplot_name";
                }
                if (!$subplot_name){
                    push @error_messages, "CellB$row_name: No subplot name could be made!";
                }
                $seen_subplot_names{$subplot_name}++;
            }
        }

    }

    my @plots = keys %seen_plot_names;
    my $plots_validator = CXGN::List::Validate->new();
    my @plots_missing = @{$plots_validator->validate($schema,'plots',\@plots)->{'missing'}};

    if (scalar(@plots_missing) > 0) {
        push @error_messages, "The following plot_name are not in the database: ".join(',',@plots_missing);
        $errors{'missing_plots'} = \@plots_missing;
    }

    my @subplots = keys %seen_subplot_names;
    my $subplot_rs = $schema->resultset('Stock::Stock')->search({ 'uniquename' => {-in => \@subplots} });
    while (my $r = $subplot_rs->next){
        push @error_messages, "The following subplot_name is already in the database and is not unique ".$r->uniquename;
    }

    #store any errors found in the parsed file to parse_errors accessor
    if (scalar(@error_messages) >= 1) {
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }

    return 1; #returns true if validation is passed
}


sub _parse_with_plugin {
    my $self = shift;
    my $filename = $self->get_filename();
    my $schema = $self->get_chado_schema();
    my $parser   = Spreadsheet::ParseExcel->new();
    my $excel_obj;
    my $worksheet;
    my %parsed_entries;

    $excel_obj = $parser->parse($filename);
    if ( !$excel_obj ) {
        return;
    }

    $worksheet = ( $excel_obj->worksheets() )[0];
    my ( $row_min, $row_max ) = $worksheet->row_range();
    my ( $col_min, $col_max ) = $worksheet->col_range();

    my %seen_plot_names;
    for my $row ( 1 .. $row_max ) {
        my $plot_name;
        if ($worksheet->get_cell($row,0)) {
            $plot_name = $worksheet->get_cell($row,0)->value();
            $seen_plot_names{$plot_name}++;
        }
    }
    my @plots = keys %seen_plot_names;
    my $plot_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id;
    my $rs = $schema->resultset("Stock::Stock")->search({
        'is_obsolete' => { '!=' => 't' },
        'uniquename' => { -in => \@plots },
        'type_id' => $plot_cvterm_id
    });
    my %plot_lookup;
    while (my $r=$rs->next){
        $plot_lookup{$r->uniquename} = $r->stock_id;
    }

    for my $row ( 1 .. $row_max ) {
        my $plot_name;
        my $num_subplots_per_plot;

        if ($worksheet->get_cell($row,0)) {
            $plot_name = $worksheet->get_cell($row,0)->value();
        }
        if ($worksheet->get_cell($row,1)) {
            $num_subplots_per_plot = $worksheet->get_cell($row,1)->value();
        }

        for my $i (1 .. $num_subplots_per_plot) {
            my $subplot_name = $plot_name."_subplot".$i;

            #skip blank lines
            if (!$plot_name && !$subplot_name) {
                next;
            }

            push @{$parsed_entries{'data'}}, {
                plot_name => $plot_name,
                plot_stock_id => $plot_lookup{$plot_name},
                subplot_name => $subplot_name,
                subplot_index_number => $i
            };
        }
    }

    $self->_set_parsed_data(\%parsed_entries);
    return 1;
}


1;
