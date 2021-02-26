
package CXGN::Stock::Catalog;

use Moose;

extends 'CXGN::JSONProp';

# a general human readable description of the stock
#
has 'description' => ( isa => 'Str', is => 'rw' );

# a list of representative images, given as image_ids
#
has 'images' => ( isa => 'Maybe[ArrayRef]', is => 'rw' );

# availability status: in_stock, delayed, currently_unavailable ...
#
has 'availability' => ( isa => 'Str', is => 'rw' );

# list of hashrefs like { stock_center => { name => ..., count_available => ..., delivery_time => } } 
has 'order_source' => ( isa => 'ArrayRef', is => 'rw');

# the breeding program this clones originated from
#
has 'breeding_program' => ( isa => 'Str', is => 'rw');

# list of trait ids??? product profiles??? maybe free text better???
#
has 'categories' => ( isa => 'ArrayRef', is => 'rw' );

# list of comments as ArrayRef of [ 'comment', 'sp_person_id']
#
has 'comments' => ( isa => 'ArrayRef', is => 'rw') ;


sub BUILD {
    my $self = shift;
    my $args = shift;
    
    $self->prop_table('stockprop');
    $self->prop_namespace('Stock::Stockprop');
    $self->prop_primary_key('stockprop_id');
    $self->prop_type('stock_order_json');
    $self->cv_name('stock_property');
    $self->allowed_fields( [ qw | description images availability comments | ] );
    $self->parent_table('stock');
    $self->parent_primary_key('stock_id');
    
    $self->load();
}

1;
