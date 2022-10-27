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

    var manage_drone_imagery_standard_process_drone_run_project_ids_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_field_trial_ids_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_field_trial_names_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_phenotype_time = '';
    var manage_drone_rover_plot_polygon_process_click_type = '';

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

        showPlotPolygonStartRoverSVG(manage_drone_rover_plot_polygons_filtered_image_id, manage_drone_rover_plot_polygons_drone_run_project_id, 'drone_rover_plot_polygons_process_image_div_svg', 'drone_rover_plot_polygons_process_top_section', 'drone_rover_plot_polygons_process_load_div', );
    });

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
