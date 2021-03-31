
package SGN::Controller::AJAX::Order;

use Moose;
use CXGN::Stock::Order;
use Data::Dumper;
use JSON;
use DateTime;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON' },
   );


sub order :Chained('/') PathPart('ajax/orders/') Args(1) {
    my $self = shift;
    my $c = shift;

    my $person_id = shift;

    my $orders = CXGN::Stock::StockOrder::get_orders_by_person_id( $c->dbic_schema(), $person_id);

    $c->stash->{order_from_person_id} = $person_id;
    $c->stash->{orders} = { data => $orders };
}

sub new_orders :Chained('order') PathPart('view') Args(0) {
    my $self = shift;
    my $c = shift;

    $c->stash->{rest} = { data => $c->stash->{orders} };
}


#sub new_order: Chained('order') PathPart('new') Args(0) {
#    my $self = shift;
#    my $c = shift;

#    my $order_from_person_id =  $c->stash->{order_from_person_id};
#    my $order_to_person_id = $c->req->param('order_to_person_id');
    #my $order_status = $c->req->param('order_status');
#    my $comment = $c->req->param('comments');

#    my $so = CXGN::Stock::StockOrder->new( { bcs_schema => $c->dbic_schema() });

    #$so->order_from_person_id($order_from_person_id);
#    $so->order_to_person_id($order_to_person_id);
#    $so->order_status("submitted");
#    $so->comment($comment);

#    $so->store();
#}

sub submit_order : Path('/ajax/order/submit') : ActionClass('REST'){ }

sub submit_order_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $people_schema = $c->dbic_schema('CXGN::People::Schema');
    my $dbh = $c->dbc->dbh();
    my $list_id = $c->req->param('list_id');
    my $time = DateTime->now();
    my $timestamp = $time->ymd();
#    print STDERR "LIST ID =".Dumper($list_id)."\n";
#    print STDERR "TIME =".Dumper($timestamp)."\n";

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
    my $contact_person_id;
    my %group_by_contact_id;
    my @all_items = @$items;
    foreach my $item_name (@all_items) {
        my $item_rs = $schema->resultset("Stock::Stock")->find( { uniquename => $item_name });
        my $item_id = $item_rs->stock_id();
#        print STDERR "ITEM ID =".Dumper($item_id)."\n";
        my $item_info_rs = $schema->resultset("Stock::Stockprop")->find({stock_id => $item_id, type_id => $catalog_cvterm_id});
        my $item_info_string = $item_info_rs->value();
        my $item_info_hash = decode_json $item_info_string;
        $contact_person_id = $item_info_hash->{'contact_person_id'};
        my $item_type = $item_info_hash->{'item_type'};
#        print STDERR "CONTACT PERSON ID =".Dumper($contact_person_id)."\n";
#        print STDERR "ITEM TYPE =".Dumper($item_type)."\n";
#        $group_by_contact_id{$contact_person_id}{$item_name} = $item_type;
        $group_by_contact_id{$contact_person_id}{$item_name}++;

        print STDERR "GROUP BY CONTACT ID =".Dumper(\%group_by_contact_id)."\n";
    }

    foreach my $contact_id (keys %group_by_contact_id) {
        my $item_ref = $group_by_contact_id{$contact_id};
        my %items = %{$item_ref};
        my @item_array = keys %items;
        print STDERR "ITEM ARRAY =".Dumper(\@item_array)."\n";
        my $new_order = CXGN::Stock::Order->new( { people_schema => $people_schema});
        $new_order->order_from_id($user_id);
        $new_order->order_to_id($contact_id);
        $new_order->order_status("submitted");
        $new_order->create_date($timestamp);
        my $order_id = $new_order->store();
        print STDERR "ORDER ID =".($order_id)."\n";

        my $order_prop = CXGN::Stock::OrderBatch->new({ people_schema => $people_schema });
        $order_prop->clone_list(\@item_array);
        $order_prop->parent_id($order_id);
    	my $order_prop_id = $order_prop->store();
        print STDERR "ORDER PROP ID =".($order_prop_id)."\n";
    }


}

1;
