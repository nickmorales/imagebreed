
function get_select_box(type, div_id, options) {

    // var previous_html = jQuery('#'+div_id).html();

    //alert(JSON.stringify(options));
    jQuery.ajax({
        url: '/ajax/html/select/'+type,
        data: options ,
        beforeSend: function(){
            var html = '<div class="well well-sm"><center><img src="/img/wheel.gif" /></center></div>';
            jQuery('#'+div_id).html(html);
        },
        success: function(response) {
            if (response.error) {
                alert(response.error);
                // jQuery('#'+div_id).html(previous_html);
            }
            else {
                jQuery('#'+div_id).empty();
                jQuery('#'+div_id).html(response.select);
                if (options.live_search) {
                    var select = jQuery("#"+options.id);
                    select.selectpicker('render');
                    select.data('selectpicker').$button.focus();
                    select.data('selectpicker').$button.attr("style","background-color:#fff");
                }
                if (options.multiple) {
                    var select = jQuery("#"+options.id).prop('multiple', 'multiple');
                }
                if (options.workflow_trigger) {
                    // console.log("this is a workflow trigger. Response.select is: \n");
                    // console.log(JSON.stringify(response.select));
                    var select = jQuery("#"+options.id).attr('onChange', 'Workflow.complete(this);');
                }
            }
        },
        error: function(response) {
            alert("An error occurred");
        }
    });
}

function filter_options(filter, filterType, targetSelect) {

    if (filter) { // If filter is defined, then show only options that are associated with it's value
        jQuery('#'+targetSelect+' option').each(function(){
            if(this.getAttribute('data-'+filterType) == filter) {
                jQuery(this).show();
            }
            else {
                jQuery(this).hide();
            }
        });
    }
    else { // Otherwise display all options
        jQuery('#'+targetSelect+' option').each(function(){
            jQuery(this).show();
        });
    }

}
