jQuery(document).ready(function() {

    //
    // Imaging vehicles
    //

    jQuery('#drone_rover_view_rover_vehicles_link').click(function(){
        jQuery('#drone_rover_view_rover_vehicles_table').DataTable({
            destroy : true,
            paging : true,
            ajax : '/api/drone_rover/rover_vehicles'
        });

        jQuery('#drone_rover_view_rover_vehicles_modal').modal('show');
    })

    //
    // Standard Process for EarthSense Rover Events
    //

    var manage_drone_rover_plot_polygons_private_company_id;
    var manage_drone_rover_plot_polygons_private_company_is_private;
    var manage_drone_rover_plot_polygons_field_trial_id;
    var manage_drone_rover_plot_polygons_field_trial_name;
    var manage_drone_rover_plot_polygons_drone_run_project_id;
    var manage_drone_rover_plot_polygons_drone_run_project_name;
    var manage_drone_rover_plot_polygons_original_image_id;
    var manage_drone_rover_plot_polygons_filtered_image_id;
    var manage_drone_rover_plot_polygons_background_image_url;
    var manage_drone_rover_plot_polygons_background_image_width;
    var manage_drone_rover_plot_polygons_background_image_height;
    var manage_drone_rover_plot_polygons_drone_run_project_ids_in_same_orthophoto = [];
    var manage_drone_rover_plot_polygons_drone_run_project_names_in_same_orthophoto = [];
    var manage_drone_rover_plot_polygons_field_trial_ids_in_same_orthophoto = [];
    var manage_drone_rover_plot_polygons_field_trial_names_in_same_orthophoto = [];
    var manage_drone_rover_plot_polygons_phenotype_time = '';
    var manage_drone_rover_plot_polygon_process_click_type = '';
    var manage_drone_rover_plot_polygons_field_trial_layout_responses = {};
    var manage_drone_rover_plot_polygons_field_trial_layout_response = {};
    var manage_drone_rover_plot_polygons_field_trial_layout_response_names = [];
    var manage_drone_rover_plot_polygons_available_stock_names = [];
    var manage_drone_rover_plot_polygons_plot_names_colors = {};
    var manage_drone_rover_plot_polygons_plot_names_plot_numbers = {};

    jQuery(document).on('click', 'button[name="project_drone_rover_plot_polygons"]', function(){
        showManageDroneRoverSection('manage_drone_rover_plot_polygon_process_div');

        manage_drone_rover_plot_polygons_private_company_id = jQuery(this).data('private_company_id');
        manage_drone_rover_plot_polygons_private_company_is_private = jQuery(this).data('private_company_is_private');
        manage_drone_rover_plot_polygons_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_rover_plot_polygons_field_trial_name = jQuery(this).data('field_trial_name');
        manage_drone_rover_plot_polygons_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        manage_drone_rover_plot_polygons_drone_run_project_name = jQuery(this).data('drone_run_project_name');
        manage_drone_rover_plot_polygons_original_image_id = jQuery(this).data('original_image_id');
        manage_drone_rover_plot_polygons_filtered_image_id = jQuery(this).data('filtered_image_id');

        manage_drone_rover_plot_polygons_drone_run_project_ids_in_same_orthophoto = [];
        manage_drone_rover_plot_polygons_drone_run_project_names_in_same_orthophoto = [];
        manage_drone_rover_plot_polygons_field_trial_ids_in_same_orthophoto = [];
        manage_drone_rover_plot_polygons_field_trial_names_in_same_orthophoto = [];
        manage_drone_rover_plot_polygons_phenotype_time = '';
        manage_drone_rover_plot_polygon_process_click_type = '';
        manage_drone_rover_plot_polygons_field_trial_layout_responses = {};
        manage_drone_rover_plot_polygons_field_trial_layout_response = {};
        manage_drone_rover_plot_polygons_field_trial_layout_response_names = [];
        manage_drone_rover_plot_polygons_available_stock_names = [];
        manage_drone_rover_plot_polygons_plot_names_colors = {};
        manage_drone_rover_plot_polygons_plot_names_plot_numbers = {};

        jQuery.ajax({
            url : '/api/drone_imagery/get_field_trial_drone_run_projects_in_same_orthophoto?drone_run_project_id='+manage_drone_rover_plot_polygons_drone_run_project_id+'&field_trial_project_id='+manage_drone_rover_plot_polygons_field_trial_id,
            success: function(response){
                console.log(response);
                manage_drone_rover_plot_polygons_drone_run_project_ids_in_same_orthophoto = response.drone_run_project_ids;
                manage_drone_rover_plot_polygons_drone_run_project_names_in_same_orthophoto = response.drone_run_project_names;
                manage_drone_rover_plot_polygons_field_trial_ids_in_same_orthophoto = response.drone_run_field_trial_ids;
                manage_drone_rover_plot_polygons_field_trial_names_in_same_orthophoto = response.drone_run_field_trial_names;

                manage_drone_rover_plot_polygons_field_trial_layout_responses = response.drone_run_all_field_trial_layouts;
                manage_drone_rover_plot_polygons_field_trial_layout_response = manage_drone_rover_plot_polygons_field_trial_layout_responses[0];
                manage_drone_rover_plot_polygons_field_trial_layout_response_names = response.drone_run_all_field_trial_names;

                var field_trial_layout_counter = 0;
                for (var key in manage_drone_rover_plot_polygons_field_trial_layout_responses) {
                    if (manage_drone_rover_plot_polygons_field_trial_layout_responses.hasOwnProperty(key)) {
                        var response = manage_drone_rover_plot_polygons_field_trial_layout_responses[key];
                        var layout = response.output;

                        for (var i=1; i<layout.length; i++) {
                            manage_drone_rover_plot_polygons_available_stock_names.push(layout[i][0]);
                        }
                        droneRoverDrawLayoutTable(response, {}, 'drone_rover_plot_polygons_process_trial_layout_div_'+field_trial_layout_counter, 'drone_rover_plot_polygons_process_layout_table_'+field_trial_layout_counter);

                        field_trial_layout_counter = field_trial_layout_counter + 1;
                    }
                }

                var plot_polygons_field_trial_names_order = manage_drone_rover_plot_polygons_field_trial_layout_response_names;

                for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
                    var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
                    var field_trial_layout_response_current = manage_drone_rover_plot_polygons_field_trial_layout_responses[plot_polygons_field_trial_names_order_current];

                    var randomColor = '#'+Math.floor(Math.random()*16777215).toString(16);

                    var plot_polygons_layout = field_trial_layout_response_current.output;
                    for (var i=1; i<plot_polygons_layout.length; i++) {
                        var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
                        var plot_polygons_plot_name = plot_polygons_layout[i][0];

                        manage_drone_rover_plot_polygons_plot_names_colors[plot_polygons_plot_name] = randomColor;
                        manage_drone_rover_plot_polygons_plot_names_plot_numbers[plot_polygons_plot_name] = plot_polygons_plot_number;
                    }
                }

            },
            error: function(response){
                alert('Error getting other field trial rover events in the same rover event!');
            }
        });

        showPlotPolygonStartRoverSVG(manage_drone_rover_plot_polygons_filtered_image_id, manage_drone_rover_plot_polygons_drone_run_project_id, 'drone_rover_plot_polygons_process_image_div_svg', 'drone_rover_plot_polygons_process_top_section', 'drone_rover_plot_polygons_process_load_div', );
    });

    function droneRoverDrawLayoutTable(response, plot_polygons, layout_div_id, layout_table_div_id) {
        var output = response.output;
        var header = output[0];
        var html = '<p>Field Trial: <b>'+response.trial_name+'</b></p><table class="table table-borders table-hover" id="'+layout_table_div_id+'"><thead><tr>';
        for (var i=0; i<header.length; i++){
            html = html + '<td>'+header[i]+'</td>';
        }
        html = html + '<td>Polygon Assigned</td>';
        html = html + '</tr></thead><tbody>';
        for (var i=1; i<output.length; i++){
            html = html + '<tr>';
            for (var j=0; j<output[i].length; j++){
                html = html + '<td>'+output[i][j]+'</td>';
            }
            if (output[i][0] in plot_polygons && plot_polygons[output[i][0]] != undefined){
                html = html + '<td>Yes</td>';
            } else {
                html = html + '<td></td>';
            }
            html = html + '</tr>';
        }
        html = html + '</tbody></table><hr>';
        jQuery('#'+layout_div_id).html(html);
        jQuery('#'+layout_table_div_id).DataTable();
    }

    function showPlotPolygonStartRoverSVG(image_id, drone_run_project_id, svg_div_id, info_div_id, load_div_id){
        jQuery.ajax({
            url : '/api/drone_imagery/get_image?image_id='+image_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                manage_drone_rover_plot_polygons_background_image_url = response.image_url;

                manage_drone_rover_plot_polygons_background_image_width = response.image_width;
                manage_drone_rover_plot_polygons_background_image_height = response.image_height;

                var top_section_html = '<p>Total Image Width: '+manage_drone_rover_plot_polygons_background_image_width+'px. Total Image Height: '+manage_drone_rover_plot_polygons_background_image_height+'px.</p>';

                jQuery('#'+info_div_id).html(top_section_html);

                d3.select('#'+svg_div_id).selectAll("*").remove();
                var svgElement = d3.select('#'+svg_div_id).append("svg")
                    .attr("width", manage_drone_rover_plot_polygons_background_image_width)
                    .attr("height", manage_drone_rover_plot_polygons_background_image_height)
                    .attr("id", svg_div_id+'_area')
                    .attr("x_pos", 0)
                    .attr("y_pos", 0)
                    .attr("x", 0)
                    .attr("y", 0)
                    .on("click", function(){
                        var coords = d3.mouse(this);
                        var PosX = Math.round(coords[0]);
                        var PosY = Math.round(coords[1]);

                        if (manage_drone_rover_plot_polygon_process_click_type == '') {
                            alert('X Coordinate: '+PosX+'. Y Coordinate: '+PosY+'.');
                        }
                        else if (manage_drone_rover_plot_polygon_process_click_type == 'plot_polygon_template_paste') {
                            manage_drone_rover_plot_polygon_process_click_type = '';

                            plotPolygonsTemplatePasteSVG(PosX, PosY, parseInt(drone_imagery_current_plot_polygon_index_options_id), 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
                            plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
                        }
                        else if (manage_drone_rover_plot_polygon_process_click_type == 'bottom_left') {
                            manage_drone_rover_plot_polygon_process_click_type = '';
                            jQuery('#drone_imagery_standard_process_plot_polygons_bottom_row_left_offset').val(PosX);
                            jQuery('#drone_imagery_standard_process_plot_polygons_left_column_bottom_offset').val(background_image_height-PosY);


                            plot_polygons_display_points = [];
                            plot_polygons_ind_points = [];
                            plot_polygons_ind_4_points = [];

                            var num_rows_val = jQuery('#drone_imagery_standard_process_plot_polygons_num_rows').val();
                            var num_cols_val = jQuery('#drone_imagery_standard_process_plot_polygons_num_cols').val();
                            var section_top_row_left_offset_val = jQuery('#drone_imagery_standard_process_plot_polygons_top_row_left_offset').val();
                            var section_top_row_right_offset_val = jQuery('#drone_imagery_standard_process_plot_polygons_top_row_right_offset').val();
                            var section_bottom_row_left_offset_val = jQuery('#drone_imagery_standard_process_plot_polygons_bottom_row_left_offset').val();
                            var section_left_column_top_offset_val = jQuery('#drone_imagery_standard_process_plot_polygons_left_column_top_offset').val();
                            var section_left_column_bottom_offset_val = jQuery('#drone_imagery_standard_process_plot_polygons_left_column_bottom_offset').val();
                            var section_right_column_bottom_offset_val = jQuery('#drone_imagery_standard_process_plot_polygons_right_col_bottom_offset').val();
                            var polygon_margin_top_bottom_val = jQuery('#drone_imagery_standard_process_plot_polygons_margin_top_bottom').val();
                            var polygon_margin_left_right_val = jQuery('#drone_imagery_standard_process_plot_polygons_margin_left_right').val();

                            plotPolygonsRectanglesApplySVG(num_rows_val, num_cols_val, section_top_row_left_offset_val, section_bottom_row_left_offset_val, section_left_column_top_offset_val, section_left_column_bottom_offset_val, section_top_row_right_offset_val, section_right_column_bottom_offset_val, polygon_margin_top_bottom_val, polygon_margin_left_right_val, 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom', 'drone_imagery_standard_process_plot_polygons_active_templates');

                            plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
                        }
                    });

                var imageGroup = svgElement.append("g")
                    .attr("x_pos", 0)
                    .attr("y_pos", 0)
                    .attr("x", 0)
                    .attr("y", 0);

                var imageElem = imageGroup.append("image")
                    .attr("x_pos", 0)
                    .attr("y_pos", 0)
                    .attr("x", 0)
                    .attr("y", 0)
                    .attr("xlink:href", manage_drone_rover_plot_polygons_background_image_url)
                    .attr("height", manage_drone_rover_plot_polygons_background_image_height)
                    .attr("width", manage_drone_rover_plot_polygons_background_image_width);


                svgElement.append('rect')
                    .attr('class', 'zoom')
                    .attr('cursor', 'move')
                    .attr('fill', 'none')
                    .attr('pointer-events', 'all')
                    .attr('width', manage_drone_rover_plot_polygons_background_image_width)
                    .attr('height', manage_drone_rover_plot_polygons_background_image_height);

                jQuery('#'+load_div_id).hide();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving rover point cloud plot polygon image SVG!')
            }
        });
    }

    function showManageDroneRoverSection(section_div_id) {
        console.log(section_div_id);
        if (section_div_id == 'manage_drone_rover_plot_polygon_process_div'){
            jQuery('#manage_drone_rover_top_div').hide();
            jQuery('#manage_drone_rover_plot_polygon_process_div').show();
        }
        window.scrollTo(0,0);
    }

});
