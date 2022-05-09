
package SGN::Controller::AJAX::Order;

use Moose;
use CXGN::Stock::Order;
use CXGN::Stock::OrderBatch;
use Data::Dumper;
use JSON;
use DateTime;
use CXGN::People::Person;
use CXGN::Contact;

use File::Basename qw | basename dirname|;
use File::Copy;
use File::Slurp;
use File::Spec::Functions;
use Digest::MD5;
use File::Path qw(make_path);
use File::Spec::Functions qw / catfile catdir/;

use LWP::UserAgent;
use LWP::Simple;
use HTML::Entities;
use URI::Encode qw(uri_encode uri_decode);
use Tie::UrlEncoder; our(%urlencode);


BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON' },
   );


sub submit_order : Path('/ajax/order/submit') : ActionClass('REST'){ }

sub submit_order_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $dbh = $c->dbc->dbh();
    my $list_id = $c->req->param('list_id');
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    my $request_date = $time->ymd();
#    print STDERR "LIST ID =".Dumper($list_id)."\n";

    if (!$c->user()) {
        print STDERR "User not logged in... not adding a catalog item.\n";
        $c->stash->{rest} = {error_string => "You must be logged in to add a catalog item." };
        return;
    }
    my $user_id = $c->user()->get_object()->get_sp_person_id();
    my $user_name = $c->user()->get_object()->get_username();
    my $user_role = $c->user->get_object->get_user_type();

    my $list = CXGN::List->new( { dbh=>$dbh, list_id=>$list_id });
    my $items = $list->elements();
#    print STDERR "ITEMS =".Dumper($items)."\n";
    my $catalog_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stock_catalog_json', 'stock_property')->cvterm_id();
    my %group_by_contact_id;
    my @all_new_rows;
    my @all_items = @$items;
    foreach my $ordered_item (@all_items) {
        my @ona_info = ();
        my @ordered_item_split = split /,/, $ordered_item;
        my $number_of_fields = @ordered_item_split;
        my $item_name = $ordered_item_split[0];
        my $item_rs = $schema->resultset("Stock::Stock")->find( { uniquename => $item_name });
        my $item_id = $item_rs->stock_id();
        my $item_info_rs = $schema->resultset("Stock::Stockprop")->find({stock_id => $item_id, type_id => $catalog_cvterm_id});
        my $item_info_string = $item_info_rs->value();
        my $item_info_hash = decode_json $item_info_string;
        my $contact_person_id = $item_info_hash->{'contact_person_id'};
        my $item_type = $item_info_hash->{'item_type'};
        my $item_source = $item_info_hash->{'material_source'};
        $group_by_contact_id{$contact_person_id}{'item_list'}{$item_name}{'item_type'} = $item_type;
        $group_by_contact_id{$contact_person_id}{'item_list'}{$item_name}{'material_source'} = $item_source;

        my $quantity_string = $ordered_item_split[1];
        my @quantity_info = split /:/, $quantity_string;
        my $quantity = $quantity_info[1];
        $quantity =~ s/^\s+|\s+$//g;
        $group_by_contact_id{$contact_person_id}{'item_list'}{$item_name}{'quantity'} = $quantity;

        @ona_info = ($item_source, $item_name, $quantity, $request_date);
        $group_by_contact_id{$contact_person_id}{'ona'}{$item_name} = \@ona_info;

        if ($number_of_fields == 3) {
            my $comments = $ordered_item_split[2];
            my @comment_info = split /:/, $comments;
            my $comment_detail = $comment_info[1];
            $comment_detail =~ s/^\s+|\s+$//g;
            $group_by_contact_id{$contact_person_id}{'item_list'}{$item_name}{'comments'} = $comment_detail;
        }
    }

    my $odk_crossing_data_service_name = $c->config->{odk_crossing_data_service_name};
    my $odk_crossing_data_service_url = $c->config->{odk_crossing_data_service_url};

    my @item_list;
    my @contact_email_list;
    foreach my $contact_id (keys %group_by_contact_id) {
        my @history = ();
        my $history_info = {};
        my $item_ref = $group_by_contact_id{$contact_id}{'item_list'};
        my %item_hashes = %{$item_ref};
        my @item_list = map { { $_ => $item_hashes{$_} } } keys %item_hashes;

        my $new_order = CXGN::Stock::Order->new( { people_schema => $people_schema, dbh => $dbh});
        $new_order->order_from_id($user_id);
        $new_order->order_to_id($contact_id);
        $new_order->order_status("submitted");
        $new_order->create_date($timestamp);
        my $order_id = $new_order->store();
#        print STDERR "ORDER ID =".($order_id)."\n";
        if (!$order_id){
            $c->stash->{rest} = {error_string => "Error saving your order",};
            return;
        }

        $history_info ->{'submitted'} = $timestamp;
        push @history, $history_info;

        my $order_prop = CXGN::Stock::OrderBatch->new({ bcs_schema => $schema, people_schema => $people_schema});
        $order_prop->clone_list(\@item_list);
        $order_prop->parent_id($order_id);
        $order_prop->history(\@history);
    	my $order_prop_id = $order_prop->store_sp_orderprop();
#        print STDERR "ORDER PROP ID =".($order_prop_id)."\n";

        if (!$order_prop_id){
            $c->stash->{rest} = {error_string => "Error saving your order",};
            return;
        }

        my $contact_person = CXGN::People::Person -> new($dbh, $contact_id);
        my $contact_email = $contact_person->get_contact_email();
        push @contact_email_list, $contact_email;

        if ($odk_crossing_data_service_name eq 'ONA') {
            my $each_contact_id_ona = $group_by_contact_id{$contact_id}{'ona'};
            my $order_location;
            foreach my $item (keys %{$each_contact_id_ona}) {
                my @new_order_row = ();
                my $ona_ref = $each_contact_id_ona->{$item};
                $order_location = $ona_ref->[0];
                @new_order_row = @$ona_ref;
                splice @new_order_row, 1, 0, $order_id;
                push @all_new_rows, [@new_order_row];
            }
            print STDERR "ORDER LOCATION =".Dumper($order_location)."\n";
            print STDERR "ALL NEW ROWS =".Dumper(\@all_new_rows)."\n";

            my $order_file_name = 'test_orders.csv';
            my $id_string;
            my $form_id;
            my $ua = LWP::UserAgent->new;
            $ua->credentials( 'api.ona.io:443', 'DJANGO', $c->config->{odk_crossing_data_service_username}, $c->config->{odk_crossing_data_service_password} );
            my $login_resp = $ua->get("https://api.ona.io/api/v1/user.json");
            my $server_endpoint_1 = "https://api.ona.io/api/v1/data";
            my $resp = $ua->get($server_endpoint_1);

            if ($resp->is_success) {
                my $message = $resp->decoded_content;
                my $all_info = decode_json $message;
                foreach my $info (@$all_info) {
                    my %info_hash = %{$info};
                    if ($info_hash{'id_string'} eq 'OrderingSystemTest') {
                        $form_id = $info_hash{'id'};
                    }
                }
            }
            print STDERR "FORM ID =".Dumper($form_id)."\n";
            my $order_ona_id;
            my $server_endpoint_2 = "https://api.ona.io/api/v1/metadata?xform=".$form_id;
            my $resp_d = $ua->get($server_endpoint_2);
            if ($resp_d->is_success) {
                my $message_d = $resp_d->decoded_content;
                my $message_hash_d = decode_json $message_d;
                foreach my $t (@$message_hash_d) {
                    if ($t->{'data_value'} eq $order_file_name) {
#                        print STDERR "DELETE INFO =".Dumper($t)."\n";
                        getstore($t->{media_url}, $order_file_name);
                        $order_ona_id = $t->{id};
                        print STDERR "ORDER ONA ID=".Dumper($order_ona_id);
                    }
                }
            }
            my @previous_order_rows;
            my @all_order_rows;
            if ($order_ona_id) {
                open(my $fh, '<', $order_file_name)
                or die "Could not open file!";
                my $old_header_row = <$fh>;
                while ( my $row = <$fh> ){
                    chomp $row;
                    push @previous_order_rows, [split ',', $row];
                }
                print STDERR "PREVIOUS ORDER INFO =".Dumper(\@previous_order_rows)."\n";
                push @all_order_rows, (@previous_order_rows);
            }

            push @all_order_rows, (@all_new_rows);
            print STDERR "ALL ORDER ROWS =".Dumper(\@all_order_rows)."\n";

            my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
#            my $ona_header = '"location","orderNo","accessionName","requestedNumberOfClones","requestDate","initiationDate","initiatedBy","subcultureDate","numberOfCopies","rootingDate","numberInRooting","weaning1Date","numberInWeaning1","weaning2Date","numberInWeaning2","screenhouseTransferDate","numberInScreenhouse","hardeningDate","numberInHardening","currentStatus","percentageComplete"';
            my $ona_header = '"location","orderNo","accessionName","requestedNumberOfClones","requestDate"';
#            my $template_file_name = 'ona_order_info';
            my $template_file_name = 'test_orders';
            my $user_id = $c->user()->get_object()->get_sp_person_id();
            my $user_name = $c->user()->get_object()->get_username();
            my $time = DateTime->now();
            my $timestamp = $time->ymd()."_".$time->hms();
            my $subdirectory_name = "ona_order_info";
#           my $archived_file_name = catfile($user_id, $subdirectory_name,$timestamp."_".$template_file_name.".csv");
            my $archived_file_name = catfile($user_id, $subdirectory_name,$template_file_name.".csv");
            my $archive_path = $c->config->{archive_path};
            my $file_destination =  catfile($archive_path, $archived_file_name);
            my $dir = $c->tempfiles_subdir('/download');
            my $rel_file = $c->tempfile( TEMPLATE => 'download/ona_order_infoXXXXX');
            my $tempfile = $c->config->{basepath}."/".$rel_file.".csv";
    #        print STDERR "TEMPFILE =".Dumper($tempfile)."\n";
            open(my $FILE, '> :encoding(UTF-8)', $tempfile) or die "Cannot open tempfile $tempfile: $!";

            print $FILE $ona_header."\n";
            my $order_row = 0;
            foreach my $row (@all_order_rows) {
                my @row_array = ();
                @row_array = @$row;
                my $csv_format = join(',',@row_array);
                print $FILE $csv_format."\n";
                $order_row++;
            }
            close $FILE;

            open(my $F, "<", $tempfile) || die "Can't open file ".$self->tempfile();
            binmode $F;
            my $md5 = Digest::MD5->new();
            $md5->addfile($F);
            close($F);

            if (!-d $archive_path) {
                mkdir $archive_path;
            }

            if (! -d catfile($archive_path, $user_id)) {
                mkdir (catfile($archive_path, $user_id));
            }

            if (! -d catfile($archive_path, $user_id,$subdirectory_name)) {
                mkdir (catfile($archive_path, $user_id, $subdirectory_name));
            }
            my $md_row = $metadata_schema->resultset("MdMetadata")->create({
                create_person_id => $user_id,
            });
            $md_row->insert();
            my $file_row = $metadata_schema->resultset("MdFiles")->create({
                basename => basename($file_destination),
                dirname => dirname($file_destination),
                filetype => 'orders',
                md5checksum => $md5->hexdigest(),
                metadata_id => $md_row->metadata_id(),
            });
            $file_row->insert();
            my $file_id = $file_row->file_id();

            move($tempfile,$file_destination);
            unlink $tempfile;
            print STDERR "FILE ID =".Dumper($file_id)."\n";
            print STDERR "FILE DESTINATION =".Dumper($file_destination)."\n";

            if ($order_ona_id) {
                my $server_endpoint_3 = "https://api.ona.io/api/v1/metadata";
                my $delete_resp = $ua->delete(
                    $server_endpoint_3."/$order_ona_id"
                );
                if ($delete_resp->is_success) {
                    print STDERR "Deleted order file on ONA $order_ona_id.\n";
                } else {
                    print STDERR "ERROR: Did not delete order file on ONA $order_ona_id.\n";
                    #print STDERR Dumper $delete_resp;
                }
            }

            my $server_endpoint_4 = "https://api.ona.io/api/v1/metadata";
            my $add_resp = $ua->post(
                $server_endpoint_4,
                Content_Type => 'form-data',
                Content => [
                    data_file => [ $file_destination, $file_destination, Content_Type => 'text/plain', ],
                    "xform"=>$form_id,
                    "data_type"=>"media",
                    "data_value"=>$file_destination
                ]
            );

            if ($add_resp->is_success) {
                my $message = $add_resp->decoded_content;
                my $message_hash = decode_json $message;
                print STDERR "ONA MESSAGE HASH =".Dumper($message_hash)."\n";
                print STDERR "ONA MESSAGE ID =".Dumper($message_hash->{id})."\n";

#                if ($message_hash->{id}){
#                    $c->stash->{rest}->{success} .= 'The order was sucessfully sent to the BANANA ORDERING SYSTEM. The progress of your order can be tracked on Musabase.';
#                } else {
#                        $c->stash->{rest}->{error} = 'Error sending your order to the BANANA ORDERING SYSTEM.';
#                    }
#                } else {
#                    print STDERR "ERROR RESPONSE =".Dumper($resp)."\n";
#                    $c->stash->{rest}->{error} = "There was an error submitting cross wishlist to ONA. Please try again.";
#                }
            }
        }
    }

    my $host = $c->config->{main_production_site_url};
    my $project_name = $c->config->{project_name};
    my $subject="Ordering Notification from $project_name";
    my $body=<<END_HEREDOC;

You have an order submitted to $project_name ($host/order/stocks/view).
Please do *NOT* reply to this message.

Thank you,
$project_name Team

END_HEREDOC

    foreach my $each_email (@contact_email_list) {
        CXGN::Contact::send_email($subject,$body,$each_email);
    }

    $c->stash->{rest} = {success => "1",};

}


sub get_user_current_orders :Path('/ajax/order/current') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $dbh = $c->dbc->dbh;
    my $user_id;

    if (!$c->user){
        $c->stash->{rest} = {error=>'You must be logged in to view your current orders!'};
        $c->detach();
    }

    if ($c->user){
        $user_id = $c->user()->get_object()->get_sp_person_id();
    }

    my $orders = CXGN::Stock::Order->new({ dbh => $dbh, people_schema => $people_schema, order_from_id => $user_id});
    my $all_orders_ref = $orders->get_orders_from_person_id();
    my @current_orders;
    my @all_orders = @$all_orders_ref;
    foreach my $order (@all_orders) {
        if (($order->[3]) ne 'completed') {
            push @current_orders, [qq{<a href="/order/details/view/$order->[0]">$order->[0]</a>}, $order->[1], $order->[2], $order->[3], $order->[5], $order->[6]]
        }
    }
    $c->stash->{rest} = {data => \@current_orders};
}

sub get_user_completed_orders :Path('/ajax/order/completed') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $dbh = $c->dbc->dbh;
    my $user_id;

    if (!$c->user){
        $c->stash->{rest} = {error=>'You must be logged in to view your completed orders!'};
        $c->detach();
    }

    if ($c->user){
        $user_id = $c->user()->get_object()->get_sp_person_id();
    }

    my $orders = CXGN::Stock::Order->new({ dbh => $dbh, people_schema => $people_schema, order_from_id => $user_id});
    my $all_orders_ref = $orders->get_orders_from_person_id();
    my @completed_orders;
    my @all_orders = @$all_orders_ref;
    foreach my $order (@all_orders) {
        if (($order->[3]) eq 'completed') {
            push @completed_orders, [qq{<a href="/order/details/view/$order->[0]">$order->[0]</a>}, $order->[1], $order->[2], $order->[3], $order->[4], $order->[5], $order->[6]]
        }
    }

    $c->stash->{rest} = {data => \@completed_orders};

}


sub get_vendor_current_orders :Path('/ajax/order/vendor_current_orders') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $dbh = $c->dbc->dbh;
    my $user_id;

    if (!$c->user){
        $c->stash->{rest} = {error=>'You must be logged in to view your orders!'};
        $c->detach();
    }

    if ($c->user){
        $user_id = $c->user()->get_object()->get_sp_person_id();
    }

    my $orders = CXGN::Stock::Order->new({ dbh => $dbh, people_schema => $people_schema, order_to_id => $user_id});
    my $vendor_orders_ref = $orders->get_orders_to_person_id();

    my @vendor_current_orders;
    my @all_vendor_orders = @$vendor_orders_ref;
        foreach my $vendor_order (@all_vendor_orders) {
            if (($vendor_order->{'order_status'}) ne 'completed') {
                push @vendor_current_orders, $vendor_order
            }
        }

    $c->stash->{rest} = {data => \@vendor_current_orders};

}


sub get_vendor_completed_orders :Path('/ajax/order/vendor_completed_orders') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $dbh = $c->dbc->dbh;
    my $user_id;

    if (!$c->user){
        $c->stash->{rest} = {error=>'You must be logged in to view your orders!'};
        $c->detach();
    }

    if ($c->user) {
        $user_id = $c->user()->get_object()->get_sp_person_id();
    }

    my $orders = CXGN::Stock::Order->new({ dbh => $dbh, people_schema => $people_schema, order_to_id => $user_id});
    my $vendor_orders_ref = $orders->get_orders_to_person_id();

    my @vendor_completed_orders;
    my @all_vendor_orders = @$vendor_orders_ref;
    foreach my $vendor_order (@all_vendor_orders) {
        if (($vendor_order->{'order_status'}) eq 'completed') {
            push @vendor_completed_orders, $vendor_order
        }
    }

    $c->stash->{rest} = {data => \@vendor_completed_orders};

}


sub update_order :Path('/ajax/order/update') :Args(0) {
    my $self = shift;
    my $c = shift;
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $dbh = $c->dbc->dbh;
    my $order_id = $c->req->param('order_id');
    my $new_status = $c->req->param('new_status');
    my $contact_person_comments = $c->req->param('contact_person_comments');
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    my $user_id;

    if (!$c->user){
        $c->stash->{rest} = {error=>'You must be logged in to update the orders!'};
        $c->detach();
    }

    if ($c->user) {
        $user_id = $c->user()->get_object()->get_sp_person_id();
    }

    my $order_obj;
    if ($new_status eq 'completed') {
        $order_obj = CXGN::Stock::Order->new({ dbh => $dbh, people_schema => $people_schema, sp_order_id => $order_id, order_to_id => $user_id, order_status => $new_status, completion_date => $timestamp, comments => $contact_person_comments});
    } else {
        $order_obj = CXGN::Stock::Order->new({ dbh => $dbh, people_schema => $people_schema, sp_order_id => $order_id, order_to_id => $user_id, order_status => $new_status, comments => $contact_person_comments});
    }

    my $updated_order = $order_obj->store();
#    print STDERR "UPDATED ORDER ID =".Dumper($updated_order)."\n";
    if (!$updated_order){
        $c->stash->{rest} = {error_string => "Error updating the order",};
        return;
    }

    my $orderprop_rs = $people_schema->resultset('SpOrderprop')->find( { sp_order_id => $order_id } );
    my $orderprop_id = $orderprop_rs->sp_orderprop_id();
    my $details_json = $orderprop_rs->value();
    print STDERR "ORDER PROP ID =".Dumper($orderprop_id)."\n";
    my $detail_hash = JSON::Any->jsonToObj($details_json);

    my $order_history_ref = $detail_hash->{'history'};
    my @order_history = @$order_history_ref;
    my $new_status_record = {};
    $new_status_record->{$new_status} = $timestamp;
    push @order_history, $new_status_record;
    $detail_hash->{'history'} = \@order_history;

    my $order_prop = CXGN::Stock::OrderBatch->new({ bcs_schema => $schema, people_schema => $people_schema, sp_order_id => $order_id, prop_id => $orderprop_id});
    $order_prop->history(\@order_history);
    my $updated_orderprop = $order_prop->store_sp_orderprop();

    if (!$updated_orderprop){
        $c->stash->{rest} = {error_string => "Error updating the order",};
        return;
    }

    $c->stash->{rest} = {success => "1",};


}


1;
