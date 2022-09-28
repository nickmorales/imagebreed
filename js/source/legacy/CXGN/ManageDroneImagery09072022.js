jQuery(document).ready(function() {

    //
    // Imaging vehicles
    //

    jQuery('#drone_imagery_view_imaging_vehicles_link').click(function(){
        jQuery('#drone_imagery_view_imaging_vehicles_table').DataTable({
            destroy : true,
            paging : true,
            ajax : '/api/drone_imagery/imaging_vehicles'
        });

        jQuery('#drone_imagery_view_imaging_vehicles_modal').modal('show');
    })

    //
    // Standard Process for Imaging Events
    //

    var manage_drone_imagery_standard_process_private_company_id;
    var manage_drone_imagery_standard_process_private_company_is_private;
    var manage_drone_imagery_standard_process_field_trial_id;
    var manage_drone_imagery_standard_process_field_trial_name;
    var manage_drone_imagery_standard_process_drone_run_project_id;
    var manage_drone_imagery_standard_process_drone_run_project_ids_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_field_trial_ids_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_field_trial_names_in_same_orthophoto = [];
    var manage_drone_imagery_standard_process_drone_run_band_project_id;
    var manage_drone_imagery_standard_process_gcp_drone_run_band_project_id;
    var manage_drone_imagery_standard_process_rotate_stitched_image_id;
    var manage_drone_imagery_standard_process_rotate_drone_run_band_project_id;
    var manage_drone_imagery_standard_process_rotate_stitched_image_degrees;
    var manage_drone_imagery_standard_process_rotated_stitched_image_id;
    var manage_drone_imagery_standard_process_cropped_image_id;
    var manage_drone_imagery_standard_process_denoised_image_id;
    var manage_drone_imagery_standard_process_removed_background_image_id;
    var manage_drone_imagery_standard_process_current_threshold_background_removed_type;
    var manage_drone_imagery_standard_process_apply_drone_run_band_project_ids = [];
    var manage_drone_imagery_standard_process_apply_drone_run_band_vegetative_indices = [];
    var manage_drone_imagery_standard_process_phenotype_time = '';
    var manage_drone_imagery_standard_process_image_width;
    var manage_drone_imagery_standard_process_image_height;
    var manage_drone_imagery_standard_process_gcp_test_run = 'Yes';
    var manage_drone_imagery_standard_process_preview_image_urls = [];
    var manage_drone_imagery_standard_process_preview_image_sizes = [];
    var drone_imagery_standard_process_ground_control_points_original_x = 0;
    var drone_imagery_standard_process_ground_control_points_original_y = 0;
    var drone_imagery_standard_process_ground_control_points_original_resize_x = 0;
    var drone_imagery_standard_process_ground_control_points_original_resize_y = 0;
    var drone_imagery_standard_process_ground_control_points_x_diff = 0;
    var drone_imagery_standard_process_ground_control_points_y_diff = 0;
    var drone_imagery_standard_process_ground_control_points_resize_x_diff = 0;
    var drone_imagery_standard_process_ground_control_points_resize_y_diff = 0;
    var drone_imagery_standard_process_brighten_image = 0;
    var manage_drone_imagery_standard_process_cropped_stitched_brightened_image_id;

    jQuery(document).on('click', 'button[name="project_drone_imagery_standard_process"]', function(){
        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');

        manage_drone_imagery_standard_process_private_company_id = jQuery(this).data('private_company_id');
        manage_drone_imagery_standard_process_private_company_is_private = jQuery(this).data('private_company_is_private');
        manage_drone_imagery_standard_process_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        manage_drone_imagery_standard_process_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_standard_process_field_trial_name = jQuery(this).data('field_trial_name');
        project_drone_imagery_ground_control_points_drone_run_project_id = manage_drone_imagery_standard_process_drone_run_project_id;
        project_drone_imagery_ground_control_points_drone_run_project_name = jQuery(this).data('drone_run_project_name');

        project_drone_imagery_ground_control_points_saved_div_table = 'project_drone_imagery_standard_process_ground_control_points_saved_div';
        project_drone_imagery_ground_control_points_svg_div = 'project_drone_imagery_standard_process_ground_control_points_svg_div';

        jQuery('#manage_drone_imagery_standard_process_drone_run_bands_table').DataTable({
            destroy : true,
            ajax : '/api/drone_imagery/drone_run_bands?select_checkbox_name=drone_run_standard_process_band_select&drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id
        });

        jQuery.ajax({
            url : '/api/drone_imagery/get_field_trial_drone_run_projects_in_same_orthophoto?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id+'&field_trial_project_id='+manage_drone_imagery_standard_process_field_trial_id,
            beforeSend: function(){
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                manage_drone_imagery_standard_process_drone_run_project_ids_in_same_orthophoto = response.drone_run_project_ids;
                manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto = response.drone_run_project_names;
                manage_drone_imagery_standard_process_field_trial_ids_in_same_orthophoto = response.drone_run_field_trial_ids;
                manage_drone_imagery_standard_process_field_trial_names_in_same_orthophoto = response.drone_run_field_trial_names;

                field_trial_layout_responses = response.drone_run_all_field_trial_layouts;
                field_trial_layout_response = field_trial_layout_responses[0];
                field_trial_layout_response_names = response.drone_run_all_field_trial_names;

                var field_trial_layout_counter = 0;
                for (var key in field_trial_layout_responses) {
                    if (field_trial_layout_responses.hasOwnProperty(key)) {
                        var response = field_trial_layout_responses[key];
                        var layout = response.output;

                        for (var i=1; i<layout.length; i++) {
                            drone_imagery_plot_polygons_available_stock_names.push(layout[i][0]);
                        }
                        droneImageryDrawLayoutTable(response, {}, 'drone_imagery_standard_process_trial_layout_div_'+field_trial_layout_counter, 'drone_imagery_standard_process_layout_table_'+field_trial_layout_counter);

                        field_trial_layout_counter = field_trial_layout_counter + 1;
                    }
                }

                plot_polygons_plot_names_colors = {};
                plot_polygons_plot_names_plot_numbers = {};
                var plot_polygons_field_trial_names_order = field_trial_layout_response_names;

                for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
                    var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
                    var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];

                    var randomColor = '#'+Math.floor(Math.random()*16777215).toString(16);

                    var plot_polygons_layout = field_trial_layout_response_current.output;
                    for (var i=1; i<plot_polygons_layout.length; i++) {
                        var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
                        var plot_polygons_plot_name = plot_polygons_layout[i][0];

                        plot_polygons_plot_names_colors[plot_polygons_plot_name] = randomColor;
                        plot_polygons_plot_names_plot_numbers[plot_polygons_plot_name] = plot_polygons_plot_number;
                    }
                }

                var html = '<div class="panel panel-default"><div class="panel-body"><p>The image contains the '+project_drone_imagery_ground_control_points_drone_run_project_name+' imaging event';

                if (manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto.length > 0) {
                    html = html + ' as well as the following imaging events: '+manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto.join();
                }

                html = html + '.</p><p><b>Use one of the following three options to assign the generated polygons to the field experiment(s) of these imaging event(s).</b></p></div></div>';

                jQuery('#drone_imagery_standard_process_generated_polygons_table_header_div').html(html);
                jQuery("#working_modal").modal("hide");
            },
            error: function(response){
                alert('Error getting other field trial imaging events in the same orthophoto!');
                jQuery("#working_modal").modal("hide");
            }
        });
    });

    jQuery('#manage_drone_imagery_standard_process_drone_run_band_step').click(function(){
        var selected = [];
        jQuery('input[name="drone_run_standard_process_band_select"]:checked').each(function() {
            selected.push([jQuery(this).val(), jQuery(this).data('background_removed_threshold_type')]);
        });
        if (selected.length < 1){
            alert('Please select at least one imaging event band! Preferably one with high contrast such as NIR.');
            return false;
        } else if (selected.length > 1){
            alert('Please select only one imaging event band! Preferably one with high contrast such as NIR.');
            return false;
        } else {
            manage_drone_imagery_standard_process_drone_run_band_project_id = selected[0][0];
            manage_drone_imagery_standard_process_current_threshold_background_removed_type = selected[0][1];

            drone_imagery_standard_process_brighten_image = jQuery('#manage_drone_imagery_standard_process_brighten_image_option').val();

            jQuery.ajax({
                url : '/api/drone_imagery/get_image_for_saving_gcp?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id,
                beforeSend: function(){
                    showManageDroneImagerySection('manage_drone_imagery_loading_div');
                },
                success: function(response){
                    console.log(response);

                    project_drone_imagery_ground_control_points_saved = response.saved_gcps_full;
                    project_drone_imagery_ground_control_points_saved_array = response.gcps_array;
                    _redraw_ground_control_points_table(project_drone_imagery_ground_control_points_saved_div_table, 'project_drone_imagery_ground_control_points_draw_points', 'project_drone_imagery_ground_control_points_delete_one');

                    jQuery.ajax({
                        url : '/api/drone_imagery/get_project_md_image?drone_run_band_project_id='+manage_drone_imagery_standard_process_drone_run_band_project_id+'&project_image_type_name=stitched_drone_imagery',
                        success: function(response){
                            console.log(response);

                            manage_drone_imagery_standard_process_rotate_stitched_image_id = response.data[0]['image_id'];

                            jQuery.ajax({
                                url : '/api/drone_imagery/brighten_image?image_id='+manage_drone_imagery_standard_process_rotate_stitched_image_id+'&brighten_image='+drone_imagery_standard_process_brighten_image,
                                success: function(response){
                                    console.log(response);
                                    var manage_drone_imagery_standard_process_rotate_stitched_brightened_image_id = response.brightened_image_id;

                                    showPlotPolygonStartSVG(manage_drone_imagery_standard_process_rotate_stitched_brightened_image_id, manage_drone_imagery_standard_process_drone_run_project_id, 'project_drone_imagery_standard_process_ground_control_points_svg_div', 'project_drone_imagery_standard_process_ground_control_points_info_div', 'project_drone_imagery_standard_process_ground_control_points_loading_div', 0, 0, undefined, undefined, 0, 1, project_drone_imagery_ground_control_points_saved_array, 1);

                                    drone_imagery_plot_polygon_click_type = 'save_ground_control_point';

                                    showManageDroneImagerySection('manage_drone_imagery_standard_process_div');

                                    Workflow.complete("#manage_drone_imagery_standard_process_drone_run_band_step");
                                    Workflow.focus('#manage_drone_imagery_standard_process_workflow', 2);
                                },
                                error: function(response){
                                    alert('Error getting standard process image brightened gcp step!');
                                    showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                                }
                            });

                        },
                        error: function(response){
                            alert('Error getting standard process image gcp step!');
                            showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                        }
                    });

                },
                error: function(response){
                    alert('Error getting standard process gcps!');
                }
            });

            jQuery('#manage_drone_imagery_standard_process_ground_control_points_skip_div').show();

            get_select_box('drone_runs_with_gcps', 'manage_drone_imagery_standard_process_ground_control_points_select', {'id':'manage_drone_imagery_standard_process_ground_control_points_select_id', 'name':'manage_drone_imagery_standard_process_ground_control_points_select_id', 'field_trial_id':manage_drone_imagery_standard_process_field_trial_id, 'empty':1});

            get_select_box('drone_runs', 'manage_drone_imagery_standard_process_previous_camera_rig_select', {'id':'manage_drone_imagery_standard_process_previous_camera_rig_select_id', 'name':'manage_drone_imagery_standard_process_previous_camera_rig_select_id', 'field_trial_id':manage_drone_imagery_standard_process_field_trial_id, 'empty':1});

            get_select_box('drone_runs', 'manage_drone_imagery_standard_process_geotiff_params_select', {'id':'manage_drone_imagery_standard_process_previous_geotiff_params_select_id', 'name':'manage_drone_imagery_standard_process_previous_geotiff_params_select_id', 'field_trial_id':manage_drone_imagery_standard_process_field_trial_id});
        }
    });

    jQuery('#manage_drone_imagery_standard_process_ground_control_points_option').change(function(){
        if (jQuery(this).val() == 'Yes') {
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_skip_div').hide();
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_select_div').show();
            jQuery('#manage_drone_imagery_standard_process_previous_camera_rig_select_div').hide();
            jQuery('#manage_drone_imagery_standard_process_previous_geotiff_params_div').hide();
        }
        else if (jQuery(this).val() == 'Yes_camera_rig') {
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_skip_div').hide();
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_select_div').hide();
            jQuery('#manage_drone_imagery_standard_process_previous_camera_rig_select_div').show();
            jQuery('#manage_drone_imagery_standard_process_previous_geotiff_params_div').hide();
        }
        else if (jQuery(this).val() == 'Yes_GeoTIFF_params') {
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_skip_div').hide();
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_select_div').hide();
            jQuery('#manage_drone_imagery_standard_process_previous_camera_rig_select_div').hide();
            jQuery('#manage_drone_imagery_standard_process_previous_geotiff_params_div').show();
        }
        else {
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_skip_div').show();
            jQuery('#manage_drone_imagery_standard_process_ground_control_points_select_div').hide();
            jQuery('#manage_drone_imagery_standard_process_previous_camera_rig_select_div').hide();
            jQuery('#manage_drone_imagery_standard_process_previous_geotiff_params_div').hide();
        }
    });

    var checkonce = 1;
    jQuery('#manage_drone_imagery_standard_process_ground_control_points_step').click(function(){
        manage_drone_imagery_standard_process_gcp_drone_run_band_project_id = jQuery('#manage_drone_imagery_standard_process_ground_control_points_select_id').val();
        if (manage_drone_imagery_standard_process_gcp_drone_run_band_project_id == '') {
            alert('Please select an imaging event as a template to base GCPs on!');
            return false;
        }
        else {
            drone_imagery_standard_process_ground_control_points_original_x = 0;
            drone_imagery_standard_process_ground_control_points_original_y = 0;
            drone_imagery_standard_process_ground_control_points_original_resize_x = 0;
            drone_imagery_standard_process_ground_control_points_original_resize_y = 0;
            drone_imagery_standard_process_ground_control_points_x_diff = 0;
            drone_imagery_standard_process_ground_control_points_y_diff = 0;
            drone_imagery_standard_process_ground_control_points_resize_x_diff = 0;
            drone_imagery_standard_process_ground_control_points_resize_y_diff = 0;

            jQuery.ajax({
                type: 'GET',
                url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id,
                dataType: "json",
                beforeSend: function (){
                    showManageDroneImagerySection('manage_drone_imagery_loading_div');
                },
                success: function(response){
                    console.log(response);
                    if (response.error) {
                        alert(response.error);
                    }

                    manage_drone_imagery_standard_process_phenotype_time = response.time_ontology_day_cvterm_id;

                    jQuery.ajax({
                        type : 'POST',
                        url : '/api/drone_imagery/standard_process_apply_ground_control_points',
                        data : {
                            'gcp_drone_run_project_id':manage_drone_imagery_standard_process_gcp_drone_run_band_project_id,
                            'field_trial_id':manage_drone_imagery_standard_process_field_trial_id,
                            'drone_run_project_id':manage_drone_imagery_standard_process_drone_run_project_id,
                            'drone_run_band_project_id':manage_drone_imagery_standard_process_drone_run_band_project_id,
                            'time_cvterm_id':manage_drone_imagery_standard_process_phenotype_time,
                            'test_run':'Yes',
                            'company_id': manage_drone_imagery_standard_process_private_company_id,
                            'is_private': manage_drone_imagery_standard_process_private_company_is_private
                        },
                        success: function(response){
                            console.log(response);
                            showManageDroneImagerySection('manage_drone_imagery_standard_process_div');

                            if (response.error) {
                                alert(response.error);
                            }
                            if (response.plot_polygons) {
                                drone_imagery_plot_polygons_display = response.plot_polygons;
                                manage_drone_imagery_standard_process_gcp_test_run = 'No';
                            }
                            if (response.rotated_image_id && checkonce == 1) {
                                if (response.rotated_cropped_points) {
                                    var project_drone_imagery_ground_control_points_rotated_cropped_points = [];
                                    for (var i=0; i<response.rotated_cropped_points.length; i++) {
                                        project_drone_imagery_ground_control_points_rotated_cropped_points.push({'x_pos':response.rotated_cropped_points[i][0], 'y_pos':response.rotated_cropped_points[i][1], 'name':''});
                                    }
                                }

                                jQuery.ajax({
                                    url : '/api/drone_imagery/brighten_image?image_id='+response.rotated_image_id+'&brighten_image='+drone_imagery_standard_process_brighten_image,
                                    success: function(response){
                                        console.log(response);
                                        var manage_drone_imagery_standard_process_gcp_brightened_image_id = response.brightened_image_id;

                                        showPlotPolygonStartSVG(manage_drone_imagery_standard_process_gcp_brightened_image_id, manage_drone_imagery_standard_process_drone_run_project_id, 'project_drone_imagery_standard_process_ground_control_points_svg_div', 'project_drone_imagery_standard_process_ground_control_points_info_div', 'project_drone_imagery_standard_process_ground_control_points_loading_div', 0, 1, 1, 1, 1, 1, project_drone_imagery_ground_control_points_rotated_cropped_points, undefined);

                                        checkonce = 0;
                                    },
                                    error: function(response){
                                        alert('Error getting standard process image brightened gcp confirm step!');
                                    }
                                });

                            }
                            if (response.rotated_points) {
                                var project_drone_imagery_ground_control_points_rotated_points = [];
                                for (var i=0; i<response.rotated_points.length; i++) {
                                    project_drone_imagery_ground_control_points_rotated_points.push({'x_pos':response.rotated_points[i][0], 'y_pos':response.rotated_points[i][1], 'name':'r'+i});
                                }
                                drawWaypointsSVG('project_drone_imagery_standard_process_ground_control_points_svg_div', project_drone_imagery_ground_control_points_rotated_points, undefined);
                            }
                            if (response.cropped_points) {
                                var project_drone_imagery_ground_control_points_cropped_points = [];
                                for (var i=0; i<response.cropped_points[0].length; i++) {
                                    project_drone_imagery_ground_control_points_cropped_points.push({'x_pos':response.cropped_points[0][i]['x'], 'y_pos':response.cropped_points[0][i]['y'], 'name':'c'+i});
                                }
                                drawWaypointsSVG('project_drone_imagery_standard_process_ground_control_points_svg_div', project_drone_imagery_ground_control_points_cropped_points, undefined);
                            }
                            if (response.old_cropped_points) {
                                var project_drone_imagery_ground_control_points_old_cropped_points = [];
                                for (var i=0; i<response.old_cropped_points[0].length; i++) {
                                    project_drone_imagery_ground_control_points_old_cropped_points.push({'x_pos':response.old_cropped_points[0][i]['x'], 'y_pos':response.old_cropped_points[0][i]['y'], 'name':'old'+i});
                                }
                                drawWaypointsSVG('project_drone_imagery_standard_process_ground_control_points_svg_div', project_drone_imagery_ground_control_points_old_cropped_points, undefined);
                            }
                        },
                        error: function(response){
                            alert('Error doing standard process with ground control points!');
                        }
                    });
                },
                error: function(response){
                    alert('Error getting time terms for standard process with gcp!');
                }
            });
        }
    });

    jQuery('#manage_drone_imagery_standard_process_ground_control_points_step_confirm').click(function(){
        if (manage_drone_imagery_standard_process_gcp_test_run == 'Yes') {
            alert('Please calculate the plot polygons and confirm they look good first!');
            return false;
        } else {
            jQuery.ajax({
                type : 'POST',
                url : '/api/drone_imagery/standard_process_apply_ground_control_points',
                data : {
                    'gcp_drone_run_project_id':manage_drone_imagery_standard_process_gcp_drone_run_band_project_id,
                    'field_trial_id':manage_drone_imagery_standard_process_field_trial_id,
                    'drone_run_project_id':manage_drone_imagery_standard_process_drone_run_project_id,
                    'drone_run_band_project_id':manage_drone_imagery_standard_process_drone_run_band_project_id,
                    'time_cvterm_id':manage_drone_imagery_standard_process_phenotype_time,
                    'test_run':manage_drone_imagery_standard_process_gcp_test_run,
                    'gcp_drag_x_diff':drone_imagery_standard_process_ground_control_points_x_diff,
                    'gcp_drag_y_diff':drone_imagery_standard_process_ground_control_points_y_diff,
                    'company_id': manage_drone_imagery_standard_process_private_company_id,
                    'is_private': manage_drone_imagery_standard_process_private_company_is_private
                },
                success: function(response){
                    console.log(response);
                    if (response.error) {
                        alert(response.error);
                    }
                },
                error: function(response){
                    alert('Error doing standard process with ground control points confirmation!');
                }
            });
            alert('The standard process will continue in the background and may take some time. You can check the indicator on the manage aerial imagery page to see when it is complete.');
            location.reload();
        }
    });

    jQuery('#manage_drone_imagery_standard_process_previous_camera_rig_step_confirm').click(function(){
        var manage_drone_imagery_standard_process_previous_camera_rig_step_drone_run_project_id = jQuery('#manage_drone_imagery_standard_process_previous_camera_rig_select_id').val();
        if (manage_drone_imagery_standard_process_previous_camera_rig_step_drone_run_project_id == '') {
            alert('Please select a previous imaging event to use as the template!');
            return false;
        } else {
            jQuery.ajax({
                type: 'GET',
                url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id,
                dataType: "json",
                beforeSend: function (){
                    jQuery('#working_modal').modal('show');
                },
                success: function(response){
                    jQuery('#working_modal').modal('hide');
                    console.log(response);
                    if (response.error) {
                        alert(response.error);
                    }

                    manage_drone_imagery_standard_process_phenotype_time = response.time_ontology_day_cvterm_id;

                    jQuery.ajax({
                        type : 'POST',
                        url : '/api/drone_imagery/standard_process_apply_previous_imaging_event',
                        data : {
                            'previous_drone_run_project_id':manage_drone_imagery_standard_process_previous_camera_rig_step_drone_run_project_id,
                            'field_trial_id':manage_drone_imagery_standard_process_field_trial_id,
                            'drone_run_project_id':manage_drone_imagery_standard_process_drone_run_project_id,
                            'drone_run_band_project_id':manage_drone_imagery_standard_process_drone_run_band_project_id,
                            'time_cvterm_id':manage_drone_imagery_standard_process_phenotype_time
                        },
                        success: function(response){
                            console.log(response);
                            if (response.error) {
                                alert(response.error);
                            }
                        },
                        error: function(response){
                            alert('Error doing standard process with previous imaging event!');
                        }
                    });

                    alert('The standard process will continue in the background and may take some time. You can check the indicator on the manage aerial imagery page to see when it is complete.');
                    location.reload();
                },
                error: function(response){
                    alert('Error getting time terms for standard process with previous imaging event!');
                    jQuery('#working_modal').modal('hide');
                }
            });

        }
    });

    jQuery('#manage_drone_imagery_standard_process_geotiff_params_confirm').click(function() {
        jQuery.ajax({
            url : '/api/drone_imagery/get_project_md_image?drone_run_band_project_id='+manage_drone_imagery_standard_process_drone_run_band_project_id+'&project_image_type_name=stitched_drone_imagery',
            beforeSend: function(){
                showManageDroneImagerySection('manage_drone_imagery_loading_div');
            },
            success: function(response){
                console.log(response);
                manage_drone_imagery_standard_process_rotate_stitched_image_id = response.data[0]['image_id'];
                manage_drone_imagery_standard_process_rotate_stitched_image_degrees = 0.00;

                drone_imagery_plot_polygon_click_type = '';

                showRotateImageD3(manage_drone_imagery_standard_process_rotate_stitched_image_id, '#drone_imagery_standard_process_rotate_original_stitched_div', 'manage_drone_imagery_standard_process_rotate_load_div');

                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');

                jQuery('#manage_drone_imagery_standard_process_rotate_step_confirm_div').hide();
                jQuery('#manage_drone_imagery_standard_process_rotate_step_finish_div').show();

                Workflow.complete("#manage_drone_imagery_standard_process_geotiff_params_confirm");
                Workflow.focus('#manage_drone_imagery_standard_process_workflow', 3);
            },
            error: function(response){
                alert('Error getting standard process image rotation step after GeoTIFF previous select!');
                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
            }
        });
    });

    jQuery('#manage_drone_imagery_standard_process_ground_control_points_skip_step').click(function(){
        jQuery.ajax({
            url : '/api/drone_imagery/get_project_md_image?drone_run_band_project_id='+manage_drone_imagery_standard_process_drone_run_band_project_id+'&project_image_type_name=stitched_drone_imagery',
            beforeSend: function(){
                showManageDroneImagerySection('manage_drone_imagery_loading_div');
            },
            success: function(response){
                console.log(response);
                manage_drone_imagery_standard_process_rotate_stitched_image_id = response.data[0]['image_id'];
                manage_drone_imagery_standard_process_rotate_stitched_image_degrees = 0.00;

                jQuery.ajax({
                    url : '/api/drone_imagery/brighten_image?image_id='+manage_drone_imagery_standard_process_rotate_stitched_image_id+'&brighten_image='+drone_imagery_standard_process_brighten_image,
                    success: function(response){
                        console.log(response);
                        var manage_drone_imagery_standard_process_rotate_stitched_brightened_image_id = response.brightened_image_id;

                        showRotateImageD3(manage_drone_imagery_standard_process_rotate_stitched_brightened_image_id, '#drone_imagery_standard_process_rotate_original_stitched_div', 'manage_drone_imagery_standard_process_rotate_load_div');

                        drone_imagery_plot_polygon_click_type = '';

                        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');

                        jQuery('#manage_drone_imagery_standard_process_rotate_step_confirm_div').show();
                        jQuery('#manage_drone_imagery_standard_process_rotate_step_finish_div').hide();

                        Workflow.complete("#manage_drone_imagery_standard_process_ground_control_points_skip_step");
                        Workflow.focus('#manage_drone_imagery_standard_process_workflow', 3);
                    },
                    error: function(response){
                        alert('Error getting standard process image rotate brighten step!');
                        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                    }
                });

            },
            error: function(response){
                alert('Error getting standard process image rotation step!');
                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
            }
        });
    });

    d3.select("#drone_imagery_standard_process_rotate_degrees_input").on("input", function() {
        manage_drone_imagery_standard_process_rotate_stitched_image_degrees = this.value;
        droneImageryStandardProcessRotateImages(manage_drone_imagery_standard_process_rotate_stitched_image_degrees, 1, 'drone_imagery_standard_process_rotate_original_stitched_div');
        jQuery('#drone_imagery_standard_process_rotate_degrees_input_text').html(manage_drone_imagery_standard_process_rotate_stitched_image_degrees);
    });

    function droneImageryStandardProcessRotateImages(angle, centered, svg_div_id){
        var svgElement = d3.select('#'+svg_div_id).selectAll('g');

        svgElement.each(function(d) {
            var x_pos = d3.select(this).attr('x_pos');
            var y_pos = d3.select(this).attr('y_pos');
            if (centered == 1) {
                var rotate_x_pos = manage_drone_imagery_standard_process_image_width/2;
                var rotate_y_pos = manage_drone_imagery_standard_process_image_height/2;
                d3.select(this).attr("transform", "translate("+x_pos+","+y_pos+") rotate("+angle+","+rotate_x_pos+","+rotate_y_pos+")");
            }
            else {
                d3.select(this).attr("transform", "translate("+x_pos+","+y_pos+") rotate("+angle+")");
            }
        });
    }

    jQuery('#drone_imagery_standard_process_rotate_stitched_crosshairs').click(function(){
        drawRotateCrosshairsD3(getRandomColor());
    });

    jQuery('#drone_imagery_standard_process_rotate_stitched_restart').click(function(){
        showRotateImageD3(manage_drone_imagery_standard_process_rotate_stitched_image_id, '#drone_imagery_standard_process_rotate_original_stitched_div', 'manage_drone_imagery_standard_process_rotate_load_div');
        manage_drone_imagery_standard_process_rotate_stitched_image_degrees = 0.00;
    });

    jQuery('#manage_drone_imagery_standard_process_rotate_step').click(function() {
        var rotate_stitched_image_degrees_text = jQuery('#drone_imagery_standard_process_rotate_degrees_input').val();
        if (rotate_stitched_image_degrees_text == '') {
            alert('Please give a number of degrees first! Can be a decimal amount.');
            return;
        }
        if (isNaN(rotate_stitched_image_degrees_text)) {
            alert('Please give a number of degrees first! Can be a decimal amount.');
            return;
        }
        manage_drone_imagery_standard_process_rotate_stitched_image_degrees = parseFloat(rotate_stitched_image_degrees_text);
        jQuery.ajax({
            type: 'POST',
            url : '/api/drone_imagery/rotate_image',
            data : {
                'image_id': manage_drone_imagery_standard_process_rotate_stitched_image_id,
                'drone_run_band_project_id': manage_drone_imagery_standard_process_drone_run_band_project_id,
                'angle': manage_drone_imagery_standard_process_rotate_stitched_image_degrees*-1,
                'company_id': manage_drone_imagery_standard_process_private_company_id,
                'is_private': manage_drone_imagery_standard_process_private_company_is_private
            },
            beforeSend: function() {
                showManageDroneImagerySection('manage_drone_imagery_loading_div');
            },
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                    return false;
                }

                manage_drone_imagery_standard_process_rotated_stitched_image_id = response.rotated_image_id;

                get_select_box('drone_imagery_parameter_select','plot_polygons_standard_process_previously_saved_image_cropping_templates', {'name':'drone_imagery_standard_process_previously_saved_image_cropping_select', 'id':'drone_imagery_standard_process_previously_saved_image_cropping_select', 'empty':1, 'field_trial_id':manage_drone_imagery_standard_process_field_trial_id, 'parameter':'image_cropping' });

                jQuery.ajax({
                    url : '/api/drone_imagery/brighten_image?image_id='+manage_drone_imagery_standard_process_rotated_stitched_image_id+'&brighten_image='+drone_imagery_standard_process_brighten_image,
                    success: function(response){
                        console.log(response);
                        var manage_drone_imagery_standard_process_rotate_stitched_brightened_image_id = response.brightened_image_id;

                        showCropImageStart(manage_drone_imagery_standard_process_rotate_stitched_brightened_image_id, 'drone_imagery_standard_process_crop_original_stitched_div', 'manage_drone_imagery_standard_process_crop_load_div');

                        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');

                        Workflow.complete("#manage_drone_imagery_standard_process_rotate_step");
                        Workflow.focus('#manage_drone_imagery_standard_process_workflow', 4);
                    },
                    error: function(response){
                        alert('Error getting standard process brightened image cropping step!');
                        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                    }
                });

            },
            error: function(response){
                //alert('Error saving standard process rotated image image!');
                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
            }
        });
    });

    jQuery('#manage_drone_imagery_standard_process_rotate_step_finish').click(function(){
        var rotate_stitched_image_degrees_text = jQuery('#drone_imagery_standard_process_rotate_degrees_input').val();
        if (rotate_stitched_image_degrees_text == '') {
            alert('Please give a number of degrees first! Can be a decimal amount.');
            return false;
        }
        if (isNaN(rotate_stitched_image_degrees_text)) {
            alert('Please give a number of degrees first! Can be a decimal amount.');
            return false;
        }
        manage_drone_imagery_standard_process_rotate_stitched_image_degrees = parseFloat(rotate_stitched_image_degrees_text);

        var manage_drone_imagery_standard_process_previous_geotiff_params_step_drone_run_project_id = jQuery('#manage_drone_imagery_standard_process_previous_geotiff_params_select_id').val();
        if (manage_drone_imagery_standard_process_previous_geotiff_params_step_drone_run_project_id == '') {
            alert('Please select a previous imaging event to use as the template!');
            return false;
        }

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id,
            dataType: "json",
            beforeSend: function (){
                showManageDroneImagerySection('manage_drone_imagery_loading_div');
            },
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }

                manage_drone_imagery_standard_process_phenotype_time = response.time_ontology_day_cvterm_id;

                jQuery('#manage_drone_imagery_standard_process_geotiff_params_drone_run_project_id').val(manage_drone_imagery_standard_process_drone_run_project_id);
                jQuery('#manage_drone_imagery_standard_process_geotiff_params_previous_drone_run_project_id').val(manage_drone_imagery_standard_process_previous_geotiff_params_step_drone_run_project_id);
                jQuery('#manage_drone_imagery_standard_process_geotiff_params_time_cvterm_id').val(manage_drone_imagery_standard_process_phenotype_time);
                jQuery('#manage_drone_imagery_standard_process_geotiff_params_angle').val(manage_drone_imagery_standard_process_rotate_stitched_image_degrees);


                Workflow.complete("#manage_drone_imagery_standard_process_rotate_step_finish");

                jQuery('#manage_drone_imagery_standard_process_previous_geotiff_params_form').submit();
            },
            error: function(response){
                alert('Error getting time terms for standard process with previous imaging event!');
                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
            }
        });

    });

    jQuery('#manage_drone_imagery_standard_process_previous_geotiff_params_form').submit(function() {
        jQuery('#working_msg').html('This can potentially take time to complete. Ensure the file(s) have completely transferred to the server before closing this tab. You can check when the process is done by looking at the indicator on the manage drone imagery page.');
        jQuery('#working_modal').modal('show');
        return true;
    });

    jQuery(document).on('click', '#manage_drone_imagery_standard_process_cropping_step', function(){
        console.log(crop_points);
        if (crop_points.length != 4) {
            alert('Please click 4 points on the image to draw a rectangle first!');
            return false;
        }
        jQuery.ajax({
            type: 'POST',
            url : '/api/drone_imagery/crop_image',
            data: {
                'image_id' :manage_drone_imagery_standard_process_rotated_stitched_image_id,
                'polygon': JSON.stringify(crop_points),
                'drone_run_band_project_id': manage_drone_imagery_standard_process_drone_run_band_project_id,
                'company_id': manage_drone_imagery_standard_process_private_company_id,
                'is_private': manage_drone_imagery_standard_process_private_company_is_private
            },
            beforeSend: function() {
                showManageDroneImagerySection('manage_drone_imagery_loading_div');
            },
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                    return false;
                }

                manage_drone_imagery_standard_process_cropped_image_id = response.cropped_image_id;
                if (response.error) {
                    alert(response.error);
                    return false;
                } else {
                    jQuery.ajax({
                        type: 'POST',
                        url : '/api/drone_imagery/denoise',
                        data : {
                            'image_id': manage_drone_imagery_standard_process_cropped_image_id,
                            'drone_run_band_project_id': manage_drone_imagery_standard_process_drone_run_band_project_id,
                            'company_id': manage_drone_imagery_standard_process_private_company_id,
                            'is_private': manage_drone_imagery_standard_process_private_company_is_private
                        },
                        success: function(response){
                            console.log(response);
                            if (response.error) {
                                alert(response.error);
                                return false;
                            }

                            manage_drone_imagery_standard_process_denoised_image_id = response.denoised_image_id;
                            remove_background_current_image_id = manage_drone_imagery_standard_process_denoised_image_id;
                            remove_background_drone_run_band_project_id = manage_drone_imagery_standard_process_drone_run_band_project_id;

                            showRemoveBackgroundHistogramStart(manage_drone_imagery_standard_process_denoised_image_id, 'drone_imagery_standard_process_remove_background_original', 'drone_imagery_standard_process_remove_background_histogram_div', 'manage_drone_imagery_standard_process_remove_background_load_div');

                            Workflow.complete("#manage_drone_imagery_standard_process_cropping_step");
                            Workflow.focus('#manage_drone_imagery_standard_process_workflow', 5);

                            showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                        },
                        error: function(response){
                            alert('Error standard process denoising image!');
                            showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                        }
                    });
                }
            },
            error: function(response){
                alert('Error standard process cropping image!');
                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
            }
        });
    });

    jQuery(document).on('click', '#drone_imagery_standard_process_cropping_use_previous_cropping', function() {
        var plot_polygons_use_previously_saved_cropping = jQuery('#drone_imagery_standard_process_previously_saved_image_cropping_select').val();
        jQuery.ajax({
            url : '/api/drone_imagery/retrieve_parameter_template?plot_polygons_template_projectprop_id='+plot_polygons_use_previously_saved_cropping,
            success: function(response){
                console.log(response);
                jQuery.ajax({
                    type: 'POST',
                    url : '/api/drone_imagery/crop_image',
                    data: {
                        'image_id' :manage_drone_imagery_standard_process_rotated_stitched_image_id,
                        'polygon': JSON.stringify(response.parameter[0]),
                        'drone_run_band_project_id': manage_drone_imagery_standard_process_drone_run_band_project_id,
                        'company_id': manage_drone_imagery_standard_process_private_company_id,
                        'is_private': manage_drone_imagery_standard_process_private_company_is_private
                    },
                    beforeSend: function() {
                        showManageDroneImagerySection('manage_drone_imagery_loading_div');
                    },
                    success: function(response){
                        console.log(response);
                        if (response.error) {
                            alert(response.error);
                            return false;
                        }

                        manage_drone_imagery_standard_process_cropped_image_id = response.cropped_image_id;
                        if (response.error) {
                            alert(response.error);
                            return false;
                        } else {
                            jQuery.ajax({
                                type: 'POST',
                                url : '/api/drone_imagery/denoise',
                                data : {
                                    'image_id': manage_drone_imagery_standard_process_cropped_image_id,
                                    'drone_run_band_project_id': manage_drone_imagery_standard_process_drone_run_band_project_id,
                                    'company_id': manage_drone_imagery_standard_process_private_company_id,
                                    'is_private': manage_drone_imagery_standard_process_private_company_is_private
                                },
                                success: function(response){
                                    console.log(response);
                                    if (response.error) {
                                        alert(response.error);
                                        return false;
                                    }

                                    manage_drone_imagery_standard_process_denoised_image_id = response.denoised_image_id;
                                    remove_background_current_image_id = manage_drone_imagery_standard_process_denoised_image_id;
                                    remove_background_drone_run_band_project_id = manage_drone_imagery_standard_process_drone_run_band_project_id;

                                    showRemoveBackgroundHistogramStart(manage_drone_imagery_standard_process_denoised_image_id, 'drone_imagery_standard_process_remove_background_original', 'drone_imagery_standard_process_remove_background_histogram_div', 'manage_drone_imagery_standard_process_remove_background_load_div');

                                    Workflow.complete("#manage_drone_imagery_standard_process_cropping_step");
                                    Workflow.focus('#manage_drone_imagery_standard_process_workflow', 5);

                                    showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                                },
                                error: function(response){
                                    alert('Error standard process denoising image!');
                                    showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                                }
                            });
                        }
                    },
                    error: function(response){
                        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                        alert('Error cropping image!');
                    }
                });
            },
            error: function(response){
                alert('Error retrieving saved cropping template in standard process!');
                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
            }
        });
        return;
    });

    jQuery('#drone_imagery_standard_process_remove_background_defined_percentage_submit').click(function(){
        drone_imagery_remove_background_lower_percentage = Number(jQuery('#drone_imagery_standard_process_remove_background_lower_threshold_percentage').val());
        drone_imagery_remove_background_upper_percentage = Number(jQuery('#drone_imagery_standard_process_remove_background_upper_threshold_percentage').val());

        //var threshold_value_return = calculateThresholdPercentageValues('drone_imagery_remove_background_original', drone_imagery_remove_background_lower_percentage, drone_imagery_remove_background_upper_percentage);

        manage_drone_imagery_standard_process_remove_background_threshold_percentage_save(manage_drone_imagery_standard_process_denoised_image_id, manage_drone_imagery_standard_process_current_threshold_background_removed_type, manage_drone_imagery_standard_process_drone_run_band_project_id, drone_imagery_remove_background_lower_percentage, drone_imagery_remove_background_upper_percentage);
    });

    jQuery('#drone_imagery_standard_process_remove_background_upper_threshold_percentage_change_button').change(function() {
        if (this.checked) {
            if (confirm("When viewing phenotypes derived from this thresholded image, you will need to remember or look up the thresholding you used. You can look up the threshold you used on the Manage Aerial Imagery page.")) {
                jQuery("#drone_imagery_standard_process_remove_background_lower_threshold_percentage").prop('disabled', false);
                jQuery("#drone_imagery_standard_process_remove_background_upper_threshold_percentage").prop('disabled', false);
            }
            else {
                jQuery("#drone_imagery_standard_process_remove_background_lower_threshold_percentage").prop('disabled', true);
                jQuery("#drone_imagery_standard_process_remove_background_upper_threshold_percentage").prop('disabled', true);
            }
        }
        else {
            jQuery("#drone_imagery_standard_process_remove_background_lower_threshold_percentage").prop('disabled', true);
            jQuery("#drone_imagery_standard_process_remove_background_upper_threshold_percentage").prop('disabled', true);
        }
    });

    jQuery('#drone_imagery_standard_process_phenotypes_margin_button').change(function() {
        if (this.checked) {
            if (confirm("When viewing phenotypes derived from these images, you will need to remember or look up the margins you used. You can look up the margins you used on the Manage Aerial Imagery page.")) {
                jQuery("#drone_imagery_standard_process_phenotypes_margin_top_bottom").prop('disabled', false);
                jQuery("#drone_imagery_standard_process_phenotypes_margin_left_right").prop('disabled', false);
            }
            else {
                jQuery("#drone_imagery_standard_process_phenotypes_margin_top_bottom").prop('disabled', true);
                jQuery("#drone_imagery_standard_process_phenotypes_margin_left_right").prop('disabled', true);
            }
        }
        else {
            jQuery("#drone_imagery_standard_process_phenotypes_margin_top_bottom").prop('disabled', true);
            jQuery("#drone_imagery_standard_process_phenotypes_margin_left_right").prop('disabled', true);
        }
    });

    function manage_drone_imagery_standard_process_remove_background_threshold_percentage_save(image_id, image_type, drone_run_band_project_id, lower_threshold_percentage, upper_threshold_percentage){
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/remove_background_percentage_save',
            dataType: "json",
            beforeSend: function() {
                showManageDroneImagerySection('manage_drone_imagery_loading_div');
            },
            data: {
                'image_id': image_id,
                'image_type_list': image_type,
                'drone_run_band_project_id': drone_run_band_project_id,
                'lower_threshold_percentage': lower_threshold_percentage,
                'upper_threshold_percentage': upper_threshold_percentage,
                'company_id': manage_drone_imagery_standard_process_private_company_id,
                'is_private': manage_drone_imagery_standard_process_private_company_is_private
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                }

                manage_drone_imagery_standard_process_removed_background_image_id = response[0]['removed_background_image_id'];

                get_select_box('drone_imagery_parameter_select','plot_polygons_standard_process_previously_saved_plot_polygon_templates', {'name': 'plot_polygons_standard_process_template_select', 'id': 'plot_polygons_standard_process_template_select', 'empty':1, 'field_trial_id':manage_drone_imagery_standard_process_field_trial_id, 'parameter':'plot_polygons' });

                jQuery.ajax({
                    url : '/api/drone_imagery/brighten_image?image_id='+image_id+'&brighten_image='+drone_imagery_standard_process_brighten_image,
                    success: function(response){
                        console.log(response);
                        manage_drone_imagery_standard_process_cropped_stitched_brightened_image_id = response.brightened_image_id;

                        //showPlotPolygonStart(manage_drone_imagery_standard_process_cropped_stitched_brightened_image_id, drone_run_band_project_id, 'drone_imagery_standard_process_plot_polygons_original_stitched_div', 'drone_imagery_standard_process_plot_polygons_top_section', 'manage_drone_imagery_standard_process_plot_polygons_load_div', 0);

                        showPlotPolygonStartSVG(manage_drone_imagery_standard_process_cropped_stitched_brightened_image_id, drone_run_band_project_id, 'drone_imagery_standard_process_plot_polygons_original_stitched_div_svg', 'drone_imagery_standard_process_plot_polygons_top_section', 'manage_drone_imagery_standard_process_plot_polygons_load_div', 0, 0, undefined, undefined, 1, undefined, undefined, undefined);

                        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');

                        Workflow.complete("#drone_imagery_standard_process_remove_background_defined_percentage_submit");
                        Workflow.focus('#manage_drone_imagery_standard_process_workflow', 6);
                    },
                    error: function(response){
                        alert('Error getting standard process brightened image threshold step!');
                        showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
                    }
                });

            },
            error: function(response){
                //alert('Error saving standard process removed background image!');
                showManageDroneImagerySection('manage_drone_imagery_standard_process_div');
            }
        });
    }

    var plot_polygons_standard_process_default_image_type_is_background_removed = 1;
    jQuery('#drone_imagery_standard_process_plot_polygons_switch_image_url').click(function() {
        if (plot_polygons_standard_process_default_image_type_is_background_removed == 1) {
            showPlotPolygonStartSVG(manage_drone_imagery_standard_process_removed_background_image_id, drone_run_band_project_id, 'drone_imagery_standard_process_plot_polygons_original_stitched_div_svg', 'drone_imagery_standard_process_plot_polygons_top_section', 'manage_drone_imagery_standard_process_plot_polygons_load_div', 0, 0, undefined, undefined, 1, undefined, undefined, undefined);
            plot_polygons_standard_process_default_image_type_is_background_removed = 0;
        }
        else {
            showPlotPolygonStartSVG(manage_drone_imagery_standard_process_cropped_stitched_brightened_image_id, drone_run_band_project_id, 'drone_imagery_standard_process_plot_polygons_original_stitched_div_svg', 'drone_imagery_standard_process_plot_polygons_top_section', 'manage_drone_imagery_standard_process_plot_polygons_load_div', 0, 0, undefined, undefined, 1, undefined, undefined, undefined);
            plot_polygons_standard_process_default_image_type_is_background_removed = 1;
        }
    });

    jQuery('#plot_polygons_standard_process_use_previously_saved_template').click(function() {
        var plot_polygons_use_previously_saved_template = jQuery('#plot_polygons_standard_process_template_select').val();
        if (plot_polygons_use_previously_saved_template == '') {
            alert('Please select a previously saved template before trying to apply it. If there is not a template listed, then you can create one using the templating tool above.');
            return;
        }

        jQuery.ajax({
            url : '/api/drone_imagery/retrieve_parameter_template?plot_polygons_template_projectprop_id='+plot_polygons_use_previously_saved_template,
            success: function(response){
                console.log(response);

                drone_imagery_plot_polygons_display = response.parameter;
                drone_imagery_plot_polygons = response.parameter;

                draw_canvas_image(background_image_url, 0);
                droneImageryDrawLayoutTable(field_trial_layout_response, drone_imagery_plot_polygons, 'drone_imagery_standard_process_trial_layout_div_0', 'drone_imagery_standard_process_layout_table_0');
                droneImageryRectangleLayoutTable(drone_imagery_plot_polygons, 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
            },
            error: function(response){
                alert('Error retrieving plot polygons template in standard process!');
            }
        });
        return;
    });

    jQuery('#drone_imagery_standard_process_plot_polygons_rectangles_apply').click(function() {
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

        plotPolygonsRectanglesApply(num_rows_val, num_cols_val, section_top_row_left_offset_val, section_bottom_row_left_offset_val, section_left_column_top_offset_val, section_left_column_bottom_offset_val, section_top_row_right_offset_val, section_right_column_bottom_offset_val, 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom', 'drone_imagery_standard_process_plot_polygons_active_templates');

        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
    });

    var drone_imagery_standard_process_plot_polygon_click_type = '';
    jQuery('#drone_imagery_standard_process_plot_polygons_top_left_click').click(function(){
        alert('Now click the top left corner of your field on the image below.');
        drone_imagery_standard_process_plot_polygon_click_type = 'top_left';
    });
    jQuery('#drone_imagery_standard_process_plot_polygons_top_right_click').click(function(){
        alert('Now click the top right corner of your field on the image below.');
        drone_imagery_standard_process_plot_polygon_click_type = 'top_right';
    });
    jQuery('#drone_imagery_standard_process_plot_polygons_bottom_left_click').click(function(){
        alert('Now click the bottom left corner of your field on the image below.');
        drone_imagery_standard_process_plot_polygon_click_type = 'bottom_left';
    });
    jQuery('#drone_imagery_standard_process_plot_polygons_bottom_right_click').click(function(){
        alert('Now click the bottom right corner of your field on the image below.');
        drone_imagery_standard_process_plot_polygon_click_type = 'bottom_right';
    });
    jQuery(document).on('click', '#drone_imagery_standard_process_plot_polygons_get_distance', function(){
        alert('Click on two points in image. The distance will be returned.');
        drone_imagery_standard_process_plot_polygon_click_type = 'get_distance';
        return false;
    });

    jQuery('#drone_imagery_standard_process_plot_polygons_rectangles_start').click(function(){
        if (jQuery('#drone_imagery_standard_process_plot_polygons_num_rows').val() == '') {
            alert('Please type the number of rows to draw in the template first!');
            return false;
        }
        if (jQuery('#drone_imagery_standard_process_plot_polygons_num_cols').val() == '') {
            alert('Please type the number of columns to draw in the template first!');
            return false;
        }

        alert('Now click the top left corner of the area to create a template for on the image below.');
        drone_imagery_standard_process_plot_polygon_click_type = 'top_left';
    });

    jQuery(document).on('click', '#drone_imagery_standard_process_plot_polygons_clear', function(){
        plot_polygons_display_points = [];
        plot_polygons_ind_points = [];
        plot_polygons_ind_4_points = [];
        drone_imagery_plot_polygons = {};
        drone_imagery_plot_polygons_plot_names = {};
        drone_imagery_plot_generated_polygons = {};
        drone_imagery_plot_polygons_display = {};
        plot_polygons_plot_names_colors = {};
        plot_polygons_plot_names_plot_numbers = {};
        plot_polygons_generated_polygons = [];
        drone_imagery_plot_polygons_removed_numbers = [];
        plot_polygons_template_dimensions = [];
        plot_polygons_template_dimensions_svg = [];
        plot_polygons_template_dimensions_template_number_svg = 0;
        plot_polygons_template_dimensions_deleted_templates_svg = [];

        d3.selectAll("path").remove();
        d3.selectAll("text").remove();
        d3.selectAll("circle").remove();
        d3.selectAll("rect").remove();

        jQuery('#drone_imagery_standard_process_generated_polygons_div').html('');

        plot_polygons_field_trial_names_order = field_trial_layout_response_names;

        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
            var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];
            droneImageryDrawLayoutTable(field_trial_layout_response_current, drone_imagery_plot_polygons, 'drone_imagery_standard_process_trial_layout_div_'+plot_polygons_field_trial_name_iterator, 'drone_imagery_standard_process_layout_table_'+plot_polygons_field_trial_name_iterator);
        }

        droneImageryDrawPlotPolygonActiveTemplatesTable("drone_imagery_standard_process_plot_polygons_active_templates", plot_polygons_template_dimensions);
        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
    });

    jQuery('#drone_imagery_plot_polygons_spreadsheet_upload_button').click(function(){
        var uploadFile = jQuery("#drone_imagery_plot_polygons_spreadsheet_upload").val();
        jQuery('#drone_imagery_plot_polygons_spreadsheet_upload_form').attr("action", "/api/drone_imagery/plot_polygon_spreadsheet_parse");
        if (uploadFile === '') {
            alert("Please select a file");
            return;
        }
        jQuery('#drone_imagery_plot_polygons_spreadsheet_upload_stock_polygons').val(JSON.stringify(drone_imagery_plot_polygons_display));
        jQuery("#drone_imagery_plot_polygons_spreadsheet_upload_form").submit();
    });

    jQuery('#drone_imagery_plot_polygons_spreadsheet_upload_form').iframePostForm({
        json: true,
        post: function () {
            jQuery('#working_modal').modal("show");
        },
        complete: function (response) {
            console.log(response);
            jQuery('#working_modal').modal("hide");

            if (response.error) {
                alert(response.error);
                return;
            }
            else {
                var html = '<div class="well well-sm">';
                if (response.error_messages) {
                    for (var i=0; i<response.error_messages.length; i++) {
                        html = html + '<p class="text-danger">' + response.error_messages[i] + '</p>';
                    }
                }
                else {
                    html = html + '<p class="text-success">Successfully assigned plot numbers to polygon numbers! View the assignments in the image above before proceeding.</p>';

                    plot_polygon_new_display = response.assigned_polygons;
                    drone_imagery_plot_polygons = response.assigned_polygons;
                    plot_polygons_field_trial_names_order = response.trial_names;
                    drone_imagery_plot_polygons_display = plot_polygon_new_display;
                    drone_imagery_plot_polygons_plot_names = response.polygon_to_plot_name;


                    for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
                        var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
                        var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];
                        droneImageryDrawLayoutTable(field_trial_layout_response_current, drone_imagery_plot_polygons, 'drone_imagery_standard_process_trial_layout_div_'+plot_polygons_field_trial_name_iterator, 'drone_imagery_standard_process_layout_table_'+plot_polygons_field_trial_name_iterator);
                    }

                    plot_polygons_plot_names_colors = {};
                    plot_polygons_plot_names_plot_numbers = {};

                    for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
                        var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
                        var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];

                        var randomColor = '#'+Math.floor(Math.random()*16777215).toString(16);

                        var plot_polygons_layout = field_trial_layout_response_current.output;
                        for (var i=1; i<plot_polygons_layout.length; i++) {
                            var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
                            var plot_polygons_plot_name = plot_polygons_layout[i][0];

                            plot_polygons_plot_names_colors[plot_polygons_plot_name] = randomColor;
                            plot_polygons_plot_names_plot_numbers[plot_polygons_plot_name] = plot_polygons_plot_number;
                        }
                    }

                    draw_polygons_svg_plots_labeled('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg', undefined, undefined, 1);
                }
                html = html + '</div>';
                jQuery('#drone_imagery_plot_polygons_spreadsheet_upload_form_response_div').html(html);
            }
        }
    });

    jQuery(document).on('click', '#drone_imagery_standard_process_plot_polygons_clear_one', function(){
        jQuery('#drone_imagery_plot_polygon_remove_polygon').modal('show');
        return false;
    });

    jQuery(document).on('click', '#drone_imagery_standard_process_plot_polygons_generated_assign', function() {
        generatePlotPolygonAssignments('drone_imagery_standard_process_trial_layout_div', 'drone_imagery_standard_process_layout_table');

        jQuery('input[name="drone_imagery_plot_polygons_autocomplete"]').each(function() {
            var stock_name = this.value;
            if (stock_name != '') {
                var polygon = drone_imagery_plot_generated_polygons[jQuery(this).data('generated_polygon_key')];
                drone_imagery_plot_polygons[stock_name] = polygon;
            }
        });
    });

    jQuery(document).on('click', 'button[name=drone_imagery_standard_process_plot_polygons_submit_bottom]', function(){
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/save_plot_polygons_template',
            dataType: "json",
            data: {
                'drone_run_band_project_id': manage_drone_imagery_standard_process_drone_run_band_project_id,
                'stock_polygons': JSON.stringify(drone_imagery_plot_polygons)
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                } else {
                    Workflow.complete("#drone_imagery_standard_process_generated_polygons_div");
                    Workflow.focus('#manage_drone_imagery_standard_process_workflow', 7);
                }
            },
            error: function(response){
                //alert('Error saving standard process assigned plot polygons!')
            }
        });

        jQuery('#manage_drone_imagery_standard_process_drone_run_bands_apply_table').DataTable({
            destroy : true,
            ajax : '/api/drone_imagery/drone_run_bands?select_checkbox_name=drone_run_standard_process_band_apply_select&drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id+'&select_all=1&disable=1'
        });
    });

    jQuery('#manage_drone_imagery_standard_process_drone_run_band_apply_step').click(function(){
        manage_drone_imagery_standard_process_apply_drone_run_band_project_ids = [];
        jQuery('input[name="drone_run_standard_process_band_apply_select"]:checked').each(function() {
            manage_drone_imagery_standard_process_apply_drone_run_band_project_ids.push(jQuery(this).val());
        });
        if (manage_drone_imagery_standard_process_apply_drone_run_band_project_ids.length < 1){
            alert('Please select at least one other imaging event band!');
            return false;
        } else {
            drone_imagery_standard_process_preview_plot_polygons(manage_drone_imagery_standard_process_drone_run_band_project_id, manage_drone_imagery_standard_process_denoised_image_id, drone_imagery_plot_polygons, jQuery('#drone_imagery_standard_process_phenotypes_margin_left_right').val(), jQuery('#drone_imagery_standard_process_phenotypes_margin_top_bottom').val());

            Workflow.complete("#manage_drone_imagery_standard_process_drone_run_band_apply_step");
            Workflow.focus('#manage_drone_imagery_standard_process_workflow', 8);
        }
    });

    function drone_imagery_standard_process_preview_plot_polygons(drone_run_band_project_id, image_id, drone_imagery_plot_polygons, plot_margin_left_right, plot_margin_top_bottom) {
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/preview_plot_polygons',
            dataType: "json",
            data: {
                'drone_run_band_project_id': drone_run_band_project_id,
                'stock_polygons': JSON.stringify(drone_imagery_plot_polygons),
                'image_id': image_id
            },
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                } else {
                    manage_drone_imagery_standard_process_preview_image_urls = response.plot_polygon_preview_urls;
                    manage_drone_imagery_standard_process_preview_image_sizes = response.plot_polygon_preview_image_sizes;

                    drone_imagery_standard_process_preview_plot_polygons_draw('drone_imagery_standard_process_phenotypes_margin_visual_div_svg', plot_margin_left_right, plot_margin_top_bottom);
                }
            },
            error: function(response){
                alert('Error previewing plot polygons for margin visualization!');
                return false;
            }
        });
    }

    jQuery(document).on("change", "#drone_imagery_standard_process_phenotypes_margin_left_right", function() {
        var plot_margin_left_right = jQuery('#drone_imagery_standard_process_phenotypes_margin_left_right').val();
        var plot_margin_top_bottom = jQuery('#drone_imagery_standard_process_phenotypes_margin_top_bottom').val();
        if (plot_margin_left_right != '' && plot_margin_top_bottom != '') {
            if (plot_margin_left_right >= 50 || plot_margin_top_bottom >= 50) {
                alert('Margins cannot be greater or equal to 50%! That would exclude the entire photo!');
                return false
            }
            drone_imagery_standard_process_preview_plot_polygons_draw('drone_imagery_standard_process_phenotypes_margin_visual_div_svg', plot_margin_left_right, plot_margin_top_bottom);
        }
        else {
            alert('Please give margin values!');
            return false;
        }
    });

    jQuery(document).on("change", "#drone_imagery_standard_process_phenotypes_margin_top_bottom", function() {
        var plot_margin_left_right = jQuery('#drone_imagery_standard_process_phenotypes_margin_left_right').val();
        var plot_margin_top_bottom = jQuery('#drone_imagery_standard_process_phenotypes_margin_top_bottom').val();
        if (plot_margin_left_right != '' && plot_margin_top_bottom != '') {
            if (plot_margin_left_right >= 50 || plot_margin_top_bottom >= 50) {
                alert('Margins cannot be greater or equal to 50%! That would exclude the entire photo!');
                return false
            }
            drone_imagery_standard_process_preview_plot_polygons_draw('drone_imagery_standard_process_phenotypes_margin_visual_div_svg', plot_margin_left_right, plot_margin_top_bottom);
        }
        else {
            alert('Please give margin values!');
            return false;
        }
    });

    function drone_imagery_standard_process_preview_plot_polygons_draw(svg_div_id, plot_margin_left_right, plot_margin_top_bottom) {
        var x_pos = 0;
        var y_pos = 0;
        var image_x_space = 10;
        var total_width = 0;
        var total_height = 0;

        for (var i=0; i<manage_drone_imagery_standard_process_preview_image_urls.length; i++) {
            var image_url = manage_drone_imagery_standard_process_preview_image_urls[i];
            var image_width = manage_drone_imagery_standard_process_preview_image_sizes[i][0];
            var image_height = manage_drone_imagery_standard_process_preview_image_sizes[i][1];

            total_width = total_width + image_width + image_x_space;
            if (image_height > total_height) {
                total_height = image_height;
            }
        }

        d3.select('#'+svg_div_id).selectAll("*").remove();
        var svgElement = d3.select('#'+svg_div_id).append("svg")
            .attr("width", total_width)
            .attr("height", total_height)
            .attr("id", svg_div_id+'_area')
            .attr("x_pos", 0)
            .attr("y_pos", 0)
            .attr("x", 0)
            .attr("y", 0);

        for (var i=0; i<manage_drone_imagery_standard_process_preview_image_urls.length; i++) {
            var image_url = manage_drone_imagery_standard_process_preview_image_urls[i];
            var image_width = manage_drone_imagery_standard_process_preview_image_sizes[i][0];
            var image_height = manage_drone_imagery_standard_process_preview_image_sizes[i][1];

            var margin_left_right = image_width*plot_margin_left_right/100;
            var margin_top_bottom = image_height*plot_margin_top_bottom/100;
            console.log([margin_left_right, margin_top_bottom]);

            var imageGroup = svgElement.append("g")
                .attr("x_pos", x_pos)
                .attr("y_pos", y_pos)
                .attr("x", x_pos)
                .attr("y", y_pos);

            var imageElem = imageGroup.append("image")
                .attr("x_pos", x_pos)
                .attr("y_pos", y_pos)
                .attr("x", x_pos)
                .attr("y", y_pos)
                .attr("xlink:href", image_url)
                .attr("height", image_height)
                .attr("width", image_width);

            var poly = [
                [x_pos+margin_left_right, y_pos+margin_top_bottom],
                [x_pos+image_width-margin_left_right, y_pos+margin_top_bottom],
                [x_pos+image_width-margin_left_right, y_pos+image_height-margin_top_bottom],
                [x_pos+margin_left_right, y_pos+image_height-margin_top_bottom],
                [x_pos+margin_left_right, y_pos+margin_top_bottom],
            ];
            //console.log(poly);
            imageGroup.append("path")
                .datum(poly)
                .attr("fill", "none")
                .attr("stroke", "steelblue")
                .attr("stroke-linejoin", "round")
                .attr("stroke-linecap", "round")
                .attr("stroke-width", 2.5)
                .attr("d", line);

            x_pos = x_pos + image_width + image_x_space;
        }
    }

    jQuery('#manage_drone_imagery_standard_process_indices_step').click(function(){
        manage_drone_imagery_standard_process_apply_drone_run_band_vegetative_indices = [];
        jQuery('input[name="drone_imagery_standard_process_apply_indices_select"]:checked').each(function() {
            manage_drone_imagery_standard_process_apply_drone_run_band_vegetative_indices.push(jQuery(this).val());
        });
        if (manage_drone_imagery_standard_process_apply_drone_run_band_vegetative_indices.length < 1){
            alert('Please select at least one vegetative index!');
            return false;
        } else {
            jQuery.ajax({
                type: 'GET',
                url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id,
                dataType: "json",
                beforeSend: function (){
                    jQuery('#working_modal').modal('show');
                },
                success: function(response){
                    jQuery('#working_modal').modal('hide');
                    console.log(response);
                    if (response.error) {
                        alert(response.error);
                    }

                    var html = "<div class='well well-sm'><table class='table table-bordered table-hover'><thead><tr><th>Field Trial</th><th>Planting Date</th><th>Imaging Event Date</th><th>Number of Weeks</th><th>Number of Days</th></tr></thead><tbody>";
                    html = html + "<tr><td>"+response.trial_name+"</td><td>"+response.planting_date+"</td><td>"+response.drone_run_date+"</td><td>"+response.time_ontology_week_term+"</td><td>"+response.time_ontology_day_term+"</td></tr>";

                    jQuery.ajax({
                        type: 'GET',
                        url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_ids='+JSON.stringify(manage_drone_imagery_standard_process_drone_run_project_ids_in_same_orthophoto),
                        dataType: "json",
                        success: function(response){
                            console.log(response);
                            if (response.error) {
                                alert(response.error);
                            }

                            for (var i=0; i<response.length; i++) {
                                html = html + "<tr><td>"+response[i].trial_name+"</td><td>"+response[i].planting_date+"</td><td>"+response[i].drone_run_date+"</td><td>"+response[i].time_ontology_week_term+"</td><td>"+response[i].time_ontology_day_term+"</td></tr>";
                            }

                            html = html + '</tbody></table></div>';
                            jQuery('#drone_imagery_standard_process_week_term_div').html(html);

                            manage_drone_imagery_standard_process_phenotype_time = response.time_ontology_day_cvterm_id;
                        },
                        error: function(response){
                            alert('Error getting time terms!');
                        }
                    });

                    manage_drone_imagery_standard_process_phenotype_time = response.time_ontology_day_cvterm_id;
                },
                error: function(response){
                    alert('Error getting time terms!');
                    jQuery('#working_modal').modal('hide');
                }
            });

            Workflow.complete("#manage_drone_imagery_standard_process_indices_step");
            Workflow.focus('#manage_drone_imagery_standard_process_workflow', 9);
        }
    });

    jQuery('#manage_drone_imagery_standard_process_phenotypes_step').click(function(){
        var selected = [];

        if (manage_drone_imagery_standard_process_phenotype_time == '') {
            alert('Time of phenotype not set! This should not happen! Please contact us.');
            return false;
        }

        var plot_margin_left_right = jQuery('#drone_imagery_standard_process_phenotypes_margin_left_right').val();
        var plot_margin_top_bottom = jQuery('#drone_imagery_standard_process_phenotypes_margin_top_bottom').val();

        if (plot_margin_top_bottom == '') {
            alert('Please give a plot polygon margin on top and bottom for phenotypes!');
            return false;
        }
        if (plot_margin_left_right == '') {
            alert('Please give a plot polygon margin on left and right for phenotypes!');
            return false;
        }
        if (plot_margin_left_right >= 50 || plot_margin_top_bottom >= 50) {
            alert('Margins cannot be greater or equal to 50%! That would exclude the entire photo!');
            return false
        }

        jQuery('input[name="drone_imagery_standard_process_phenotypes_select"]:checked').each(function() {
            selected.push(jQuery(this).val());
        });
        if (selected.length < 1){
            alert('Please select at least one phenotype!');
            return false;
        } else {
            jQuery.ajax({
                type: 'POST',
                url: '/api/drone_imagery/check_maximum_standard_processes',
                dataType: "json",
                success: function(response){
                    if (response.error) {
                        alert(response.error);
                        return false;
                    }
                    else if (response.success) {
                        jQuery.ajax({
                            type: 'POST',
                            url: '/api/drone_imagery/standard_process_apply',
                            dataType: "json",
                            data: {
                                'drone_run_project_id': manage_drone_imagery_standard_process_drone_run_project_id,
                                'drone_run_band_project_id': manage_drone_imagery_standard_process_drone_run_band_project_id,
                                'apply_drone_run_band_project_ids': JSON.stringify(manage_drone_imagery_standard_process_apply_drone_run_band_project_ids),
                                'vegetative_indices': JSON.stringify(manage_drone_imagery_standard_process_apply_drone_run_band_vegetative_indices),
                                'phenotype_types': JSON.stringify(selected),
                                'time_cvterm_id': manage_drone_imagery_standard_process_phenotype_time,
                                'standard_process_type': 'minimal',
                                'field_trial_id':manage_drone_imagery_standard_process_field_trial_id,
                                'apply_to_all_drone_runs_from_same_camera_rig':jQuery('#drone_imagery_standard_process_camera_rig_apply_select').val(),
                                'phenotypes_plot_margin_top_bottom':plot_margin_top_bottom,
                                'phenotypes_plot_margin_right_left':plot_margin_left_right,
                                'drone_imagery_remove_background_lower_percentage':drone_imagery_remove_background_lower_percentage,
                                'drone_imagery_remove_background_upper_percentage':drone_imagery_remove_background_upper_percentage,
                                'polygon_template_metadata':JSON.stringify(plot_polygons_template_dimensions_svg),
                                'polygon_templates_deleted':JSON.stringify(plot_polygons_template_dimensions_deleted_templates_svg),
                                'polygon_removed_numbers':JSON.stringify(drone_imagery_plot_polygons_removed_numbers),
                                'polygons_to_plot_names':JSON.stringify(drone_imagery_plot_polygons_plot_names),
                                'company_id': manage_drone_imagery_standard_process_private_company_id,
                                'is_private': manage_drone_imagery_standard_process_private_company_is_private
                            },
                            success: function(response){
                                console.log(response);
                                if (response.error) {
                                    alert(response.error);
                                }
                            },
                            error: function(response){
                                alert('Error saving standard process assigned plot polygons!')
                            }
                        });

                        Workflow.complete("#manage_drone_imagery_standard_process_phenotypes_step");
                        jQuery('#drone_imagery_standard_process_complete_dialog').modal('show');
                    }
                },
                error: function(response){
                    alert('Error checking maximum number of standard processes!')
                }
            });
        }
    });

    jQuery('#drone_imagery_standard_process_complete_dialog').on('hidden.bs.modal', function () {
        location.reload();
    });

    //
    // TimeSeries for field trial
    //

    var manage_drone_imagery_field_trial_time_series_field_trial_id;
    var manage_drone_imagery_field_trial_time_series_field_trial_name;
    var manage_drone_imagery_field_trial_time_series_image_id_hash;
    var manage_drone_imagery_field_trial_time_series_image_id;
    var manage_drone_imagery_field_trial_time_series_drone_run_project_id;
    var manage_drone_imagery_field_trial_time_series_sorted_times;
    var manage_drone_imagery_field_trial_time_series_sorted_dates;
    var manage_drone_imagery_field_trial_time_series_date;
    var manage_drone_imagery_field_trial_time_series_time;
    var manage_drone_imagery_field_trial_time_series_sorted_image_types;
    var manage_drone_imagery_field_trial_time_series_image_type;
    var manage_drone_imagery_field_trial_time_series_image_type_counter = 0;
    var manage_drone_imagery_field_trial_time_series_time_counter = 0;
    var drone_imagery_plot_polygons_display_plot_field_layout;

    function _drone_imagery_time_series_image_show() {
        manage_drone_imagery_field_trial_time_series_time = manage_drone_imagery_field_trial_time_series_sorted_times[manage_drone_imagery_field_trial_time_series_time_counter];
        manage_drone_imagery_field_trial_time_series_date = manage_drone_imagery_field_trial_time_series_sorted_dates[manage_drone_imagery_field_trial_time_series_time_counter];

        manage_drone_imagery_field_trial_time_series_image_id = 0;
        while (manage_drone_imagery_field_trial_time_series_image_id == 0) {
            manage_drone_imagery_field_trial_time_series_image_type = manage_drone_imagery_field_trial_time_series_sorted_image_types[manage_drone_imagery_field_trial_time_series_image_type_counter];
            if (manage_drone_imagery_field_trial_time_series_image_id_hash[manage_drone_imagery_field_trial_time_series_time][manage_drone_imagery_field_trial_time_series_image_type]) {
                manage_drone_imagery_field_trial_time_series_image_id = manage_drone_imagery_field_trial_time_series_image_id_hash[manage_drone_imagery_field_trial_time_series_time][manage_drone_imagery_field_trial_time_series_image_type]['image_id'];
            }
            else {
                if (manage_drone_imagery_field_trial_time_series_image_type_counter > manage_drone_imagery_field_trial_time_series_sorted_image_types.length) {
                    manage_drone_imagery_field_trial_time_series_image_type_counter = 0;
                }
                else {
                    manage_drone_imagery_field_trial_time_series_image_type_counter = manage_drone_imagery_field_trial_time_series_image_type_counter + 1;
                }
            }
        }

        manage_drone_imagery_field_trial_time_series_drone_run_project_id = manage_drone_imagery_field_trial_time_series_image_id_hash[manage_drone_imagery_field_trial_time_series_time][manage_drone_imagery_field_trial_time_series_image_type]['drone_run_project_id'];

        drone_imagery_plot_polygons_display = JSON.parse(manage_drone_imagery_field_trial_time_series_image_id_hash[manage_drone_imagery_field_trial_time_series_time][manage_drone_imagery_field_trial_time_series_image_type]['plot_polygons']);

        showPlotPolygonStart(manage_drone_imagery_field_trial_time_series_image_id, manage_drone_imagery_field_trial_time_series_drone_run_project_id, 'manage_drone_imagery_field_trial_time_series_canvas_div', 'manage_drone_imagery_field_trial_time_series_info_div', 'manage_drone_imagery_field_trial_time_series_loading_div', 1);

        var image_type_html = "<table class='table table-bordered table-hover'><thead><tr><th>Image Types (Select an image type)</th></tr></thead><tbody><tr><td>";
        for (var i=0; i<manage_drone_imagery_field_trial_time_series_sorted_image_types.length; i++) {
            if (manage_drone_imagery_field_trial_time_series_sorted_image_types[i] == manage_drone_imagery_field_trial_time_series_image_type) {
                image_type_html = image_type_html + "<button class='btn btn-sm btn-info' style='margin:3px'>"+manage_drone_imagery_field_trial_time_series_sorted_image_types[i]+"</button>";
            }
            else {
                image_type_html = image_type_html + "<button class='btn btn-sm btn-default' style='margin:3px' name='drone_runs_trial_view_timeseries_image_type_select' data-index="+i+" >"+manage_drone_imagery_field_trial_time_series_sorted_image_types[i]+"</button>";
            }
        }
        image_type_html = image_type_html + "</td></tr></tbody></table>";

        var time_html = "<table class='table table-bordered table-hover'><thead><tr><th>Time Points (Select a time point)</th></tr></thead><tbody><tr><td>";
        for (var i=0; i<manage_drone_imagery_field_trial_time_series_sorted_dates.length; i++) {
            if (manage_drone_imagery_field_trial_time_series_sorted_dates[i] == manage_drone_imagery_field_trial_time_series_date) {
                time_html = time_html + "<button class='btn btn-sm btn-info' style='margin:3px' >"+manage_drone_imagery_field_trial_time_series_sorted_dates[i]+"</button>";
            }
            else {
                time_html = time_html + "<button class='btn btn-sm btn-default' style='margin:3px' name='drone_runs_trial_view_timeseries_date_select' data-index="+i+" >"+manage_drone_imagery_field_trial_time_series_sorted_dates[i]+"</button>";
            }
        }
        time_html = time_html + "</td></tr></tbody></table>";

        jQuery('#manage_drone_imagery_field_trial_time_series_image_type_div').html(image_type_html);
        jQuery('#manage_drone_imagery_field_trial_time_series_times_div').html(time_html);
    }

    jQuery(document).on('click', 'button[name="drone_runs_trial_view_timeseries_image_type_select"]', function(){
        manage_drone_imagery_field_trial_time_series_image_type_counter = jQuery(this).data('index');
        _drone_imagery_time_series_image_show();
    });

    jQuery(document).on('click', 'button[name="drone_runs_trial_view_timeseries_date_select"]', function(){
        manage_drone_imagery_field_trial_time_series_time_counter = jQuery(this).data('index');
        _drone_imagery_time_series_image_show();
    });

    jQuery(document).on('click', 'button[name="drone_runs_trial_view_timeseries"]', function(){
        manage_drone_imagery_field_trial_time_series_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_field_trial_time_series_field_trial_name = jQuery(this).data('field_trial_name');

        jQuery('#manage_drone_imagery_field_trial_time_series_div_title').html("<center><h3>"+manage_drone_imagery_field_trial_time_series_field_trial_name+"</h3></center>");

        jQuery.ajax({
            url: '/api/drone_imagery/get_image_for_time_series?field_trial_id='+manage_drone_imagery_field_trial_time_series_field_trial_id,
            beforeSend: function() {
                showManageDroneImagerySection('manage_drone_imagery_loading_div');
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                }
                showManageDroneImagerySection('manage_drone_imagery_field_trial_time_series_div');

                manage_drone_imagery_field_trial_time_series_image_id_hash = response.image_ids_hash;
                manage_drone_imagery_field_trial_time_series_sorted_times = response.sorted_times;
                manage_drone_imagery_field_trial_time_series_sorted_dates = response.sorted_dates;
                manage_drone_imagery_field_trial_time_series_sorted_image_types = response.sorted_image_types;
                manage_drone_imagery_field_trial_time_series_time_counter = 0;
                manage_drone_imagery_field_trial_time_series_image_type_counter = 0

                drone_imagery_plot_polygons_display_plot_field_layout = response.field_layout;

                _drone_imagery_time_series_image_show();
            },
            error: function(response){
                showManageDroneImagerySection('manage_drone_imagery_field_trial_time_series_div');
                alert('Error getting image for time series!')
            }
        });
    });

    //
    // Save ground control points
    //

    var project_drone_imagery_ground_control_points_drone_run_project_id;
    var project_drone_imagery_ground_control_points_drone_run_project_name;
    var project_drone_imagery_ground_control_points_image_ids;
    var project_drone_imagery_ground_control_points_image_types;
    var project_drone_imagery_ground_control_points_image_id;
    var project_drone_imagery_ground_control_points_image_type;
    var project_drone_imagery_ground_control_points_image_id_counter = 0;
    var project_drone_imagery_ground_control_points_saved;
    var project_drone_imagery_ground_control_points_saved_array;

    var project_drone_imagery_ground_control_points_saved_div_table;
    var project_drone_imagery_ground_control_points_svg_div;

    jQuery(document).on('click', 'button[name="project_drone_imagery_ground_control_points"]', function(){
        project_drone_imagery_ground_control_points_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        project_drone_imagery_ground_control_points_drone_run_project_name = jQuery(this).data('drone_run_project_name');

        project_drone_imagery_ground_control_points_saved_div_table = 'project_drone_imagery_ground_control_points_saved_div';
        project_drone_imagery_ground_control_points_svg_div = 'project_drone_imagery_ground_control_points_svg_div';

        jQuery('#project_drone_imagery_ground_control_points_title_div').html('<center><h3>'+project_drone_imagery_ground_control_points_drone_run_project_name+'</h3></center>');

        showManageDroneImagerySection('project_drone_imagery_ground_control_points_div');

        jQuery.ajax({
            url: '/api/drone_imagery/get_image_for_saving_gcp?drone_run_project_id='+project_drone_imagery_ground_control_points_drone_run_project_id,
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                }

                project_drone_imagery_ground_control_points_image_ids = response.image_ids;
                project_drone_imagery_ground_control_points_image_types = response.image_types;
                project_drone_imagery_ground_control_points_saved = response.saved_gcps_full;
                project_drone_imagery_ground_control_points_saved_array = response.gcps_array;

                project_drone_imagery_ground_control_points_image_id = project_drone_imagery_ground_control_points_image_ids[0];
                project_drone_imagery_ground_control_points_image_type = project_drone_imagery_ground_control_points_image_types[0];

                showPlotPolygonStartSVG(project_drone_imagery_ground_control_points_image_id, project_drone_imagery_ground_control_points_drone_run_project_id, 'project_drone_imagery_ground_control_points_svg_div', 'project_drone_imagery_ground_control_points_info_div', 'project_drone_imagery_ground_control_points_loading_div', 0, 0, undefined, undefined, 1, 1, project_drone_imagery_ground_control_points_saved_array, 1);

                jQuery('#project_drone_imagery_ground_control_points_image_type_div').html('<h4>'+project_drone_imagery_ground_control_points_image_type+'</h4>');
                jQuery('#project_drone_imagery_ground_control_points_next_buttons').show();

                drone_imagery_plot_polygon_click_type = 'save_ground_control_point';

                _redraw_ground_control_points_table(project_drone_imagery_ground_control_points_saved_div_table, 'project_drone_imagery_ground_control_points_draw_points', 'project_drone_imagery_ground_control_points_delete_one');
            },
            error: function(response){
                alert('Error getting image for GCP saving!')
            }
        });

    });

    jQuery('#project_drone_imagery_ground_control_points_previous_image').click(function(){
        if (project_drone_imagery_ground_control_points_image_id_counter > 0) {
            project_drone_imagery_ground_control_points_image_id_counter = project_drone_imagery_ground_control_points_image_id_counter - 1;
            project_drone_imagery_ground_control_points_image_id = project_drone_imagery_ground_control_points_image_ids[project_drone_imagery_ground_control_points_image_id_counter];
            project_drone_imagery_ground_control_points_image_type = project_drone_imagery_ground_control_points_image_types[project_drone_imagery_ground_control_points_image_id_counter];

            showPlotPolygonStartSVG(project_drone_imagery_ground_control_points_image_id, project_drone_imagery_ground_control_points_drone_run_project_id, 'project_drone_imagery_ground_control_points_svg_div', 'project_drone_imagery_ground_control_points_info_div', 'project_drone_imagery_ground_control_points_loading_div', 0, 0, undefined, undefined, 1, 1, project_drone_imagery_ground_control_points_saved_array, 1);

            jQuery('#project_drone_imagery_ground_control_points_image_type_div').html('<h4>'+project_drone_imagery_ground_control_points_image_type+'</h4>');
        }
        else {
            alert('No previous image! Go to next image first!');
            return false;
        }
    });

    jQuery('#project_drone_imagery_ground_control_points_next_image').click(function(){
        if (project_drone_imagery_ground_control_points_image_id_counter < project_drone_imagery_ground_control_points_image_ids.length-1) {
            project_drone_imagery_ground_control_points_image_id_counter = project_drone_imagery_ground_control_points_image_id_counter + 1;
            project_drone_imagery_ground_control_points_image_id = project_drone_imagery_ground_control_points_image_ids[project_drone_imagery_ground_control_points_image_id_counter];
            project_drone_imagery_ground_control_points_image_type = project_drone_imagery_ground_control_points_image_types[project_drone_imagery_ground_control_points_image_id_counter];

            showPlotPolygonStartSVG(project_drone_imagery_ground_control_points_image_id, project_drone_imagery_ground_control_points_drone_run_project_id, 'project_drone_imagery_ground_control_points_svg_div', 'project_drone_imagery_ground_control_points_info_div', 'project_drone_imagery_ground_control_points_loading_div', 0, 0, undefined, undefined, 1, 1, project_drone_imagery_ground_control_points_saved_array, 1);

            jQuery('#project_drone_imagery_ground_control_points_image_type_div').html('<h4>'+project_drone_imagery_ground_control_points_image_type+'</h4>');
        }
        else {
            alert('No next image! Go to previous image first!');
            return false;
        }
    });

    function _redraw_ground_control_points_table(table_div, button_name, delete_button_name) {
        var html = "<table class='table table-bordered table-hover'><thead><tr><th>Saved GCP Name</th><th>X Pos</th><th>Y Pos</th><th>Latitude</th><th>Longitude</th><th>Remove</th></thead><tbody>";
        for (var i=0; i<project_drone_imagery_ground_control_points_saved_array.length; i++) {
            html = html + "<tr><td>"+project_drone_imagery_ground_control_points_saved_array[i]['name']+"</td><td>"+project_drone_imagery_ground_control_points_saved_array[i]['x_pos']+"</td><td>"+project_drone_imagery_ground_control_points_saved_array[i]['y_pos']+"</td><td>"+project_drone_imagery_ground_control_points_saved_array[i]['latitude']+"</td><td>"+project_drone_imagery_ground_control_points_saved_array[i]['longitude']+"</td><td><p style='color:red' name='"+delete_button_name+"' data-name='"+project_drone_imagery_ground_control_points_saved_array[i]['name']+"' data-drone_run_project_id="+project_drone_imagery_ground_control_points_drone_run_project_id+" >X</p></td></tr>";
        }
        html = html + "</tbody></table>";
        //html = html + "<button class='btn btn-default' name='"+button_name+"'>Draw Saved GCPs</button>";
        jQuery('#'+table_div).html(html);
    }

    jQuery(document).on('click', 'p[name="project_drone_imagery_ground_control_points_delete_one"]', function(){
        var drone_run_project_id = jQuery(this).data('drone_run_project_id');
        var name = jQuery(this).data('name');

        if (confirm("Remove this GCP?")) {
            jQuery.ajax({
                type: 'POST',
                url: '/api/drone_imagery/remove_one_gcp',
                data: {
                    'drone_run_project_id' : drone_run_project_id,
                    'name' : name,
                },
                success: function(response){
                    console.log(response);
                    if (response.error) {
                        alert(response.error);
                    }
                    project_drone_imagery_ground_control_points_saved = response.saved_gcps_full;
                    project_drone_imagery_ground_control_points_saved_array = response.gcps_array;
                    _redraw_ground_control_points_table(project_drone_imagery_ground_control_points_saved_div_table, 'project_drone_imagery_ground_control_points_draw_points', 'project_drone_imagery_ground_control_points_delete_one');

                    drawWaypointsSVG(project_drone_imagery_ground_control_points_svg_div, project_drone_imagery_ground_control_points_saved_array, 1);
                },
                error: function(response){
                    alert('Error deleting GCP name!');
                }
            });
        }
    });

    jQuery('#project_drone_imagery_ground_control_points_form_save').click(function(){
        var name = jQuery('#project_drone_imagery_ground_control_points_form_input_name').val();
        var longitude = jQuery('#project_drone_imagery_ground_control_points_form_input_longitude').val();
        var latitude = jQuery('#project_drone_imagery_ground_control_points_form_input_latitude').val();
        var x_pos = jQuery('#project_drone_imagery_ground_control_points_form_input_x_pos').val();
        var y_pos = jQuery('#project_drone_imagery_ground_control_points_form_input_y_pos').val();

        if (name == '') {
            alert('Please give a name to the GCP!');
            return false;
        }
        if (x_pos == '' || y_pos == '') {
            alert('Please give an x and y position to the GCP!');
            return false;
        }

        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/saving_gcp',
            data: {
                'drone_run_project_id' : project_drone_imagery_ground_control_points_drone_run_project_id,
                'name' : name,
                'x_pos' : x_pos,
                'y_pos' : y_pos,
                'latitude' : latitude,
                'longitude' : longitude
            },
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }
                project_drone_imagery_ground_control_points_saved = response.saved_gcps_full;
                project_drone_imagery_ground_control_points_saved_array = response.gcps_array;

                _redraw_ground_control_points_table(project_drone_imagery_ground_control_points_saved_div_table, 'project_drone_imagery_ground_control_points_draw_points', 'project_drone_imagery_ground_control_points_delete_one');

                drawWaypointsSVG(project_drone_imagery_ground_control_points_svg_div, project_drone_imagery_ground_control_points_saved_array, 1);
            },
            error: function(response){
                alert('Error getting image for GCP saving!')
            }
        });
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_ground_control_points_draw_points"]', function(){
        console.log(project_drone_imagery_ground_control_points_saved_array);
        drawWaypointsSVG(project_drone_imagery_ground_control_points_svg_div, project_drone_imagery_ground_control_points_saved_array, 1);
    });

    //
    // Apply other Vegetation Indices
    //

    var project_drone_imagery_apply_other_vi_drone_run_project_id;
    var project_drone_imagery_apply_other_vi_drone_run_project_name;
    var project_drone_imagery_apply_other_vi_drone_run_company_id;
    var project_drone_imagery_apply_other_vi_drone_run_company_is_private;
    var project_drone_imagery_apply_other_vi_field_trial_id;
    var project_drone_imagery_apply_other_vi_selected_indices;

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_other_vi"]', function(){
        project_drone_imagery_apply_other_vi_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        project_drone_imagery_apply_other_vi_drone_run_project_name = jQuery(this).data('drone_run_project_name');
        project_drone_imagery_apply_other_vi_field_trial_id = jQuery(this).data('field_trial_id');
        project_drone_imagery_apply_other_vi_drone_run_company_id = jQuery(this).data('private_company_id');
        project_drone_imagery_apply_other_vi_drone_run_company_is_private = jQuery(this).data('private_company_is_private');

        jQuery.ajax({
            url: '/api/drone_imagery/check_available_applicable_vi?drone_run_project_id='+project_drone_imagery_apply_other_vi_drone_run_project_id+'&field_trial_id='+project_drone_imagery_apply_other_vi_field_trial_id,
            beforeSend: function(){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                console.log(response);
                jQuery('#working_modal').modal('hide');

                var html = '<div class="form-horizontal"><div class="form-group"><label class="col-sm-3 control-label">Vegetative Indices Available: </label><div class="col-sm-9">';

                if(response.error) {
                    alert(response.error);
                }
                else {
                    jQuery('#drone_imagery_apply_other_vi_dialog').modal('show');

                    var name_defs = {
                        'TGI':'TGI (Triangular Greenness Index)',
                        'VARI':'VARI (Visible Atmospheric Resistant Index)',
                        'NDVI':'Normalized Difference Vegetation Index)',
                        'NDRE':'Normalized Difference RedEdge Vegetation Index)',
                        'CCC':'CCC (Canopy Cover Canopea Algorithm Index)'
                    };

                    var p = response.vi;
                    for (var key in p) {
                        if (p.hasOwnProperty(key)) {
                            var val = p[key];
                            if (val == 0) {
                                html = html + '<input name="drone_imagery_apply_other_vi_indices_select" value="'+key+'" type="checkbox"> '+name_defs[key]+'<br/>'
                            }
                            else if (val == 2) {
                                html = html + '<input name="drone_imagery_apply_other_vi_indices_completed_select" value="'+key+'" type="checkbox" > '+name_defs[key]+' <span class="text-success">(Completed for some plots in field experiment)</span><br/>'
                            }
                            else if (val == 1) {
                                html = html + '<input name="drone_imagery_apply_other_vi_indices_completed_select" value="'+key+'" type="checkbox" checked disabled> '+name_defs[key]+' <span class="text-success">(Completed for all plots in field experiment)</span><br/>'
                            }
                        }
                    }
                }
                html = html + '</div></div></div>';
                jQuery('#drone_imagery_apply_other_vi_div').html(html);
            },
            error: function(response){
                jQuery('#working_modal').modal('hide');
                alert('Error getting available applicable vegetation indices!');
            }
        });

    });

    jQuery('#drone_imagery_apply_other_vi_select').click(function(){
        project_drone_imagery_apply_other_vi_selected_indices = [];
        jQuery('input[name="drone_imagery_apply_other_vi_indices_select"]:checked').each(function() {
            project_drone_imagery_apply_other_vi_selected_indices.push(jQuery(this).val());
        });
        if (project_drone_imagery_apply_other_vi_selected_indices.length < 1){
            alert('Please select at least one vegetative index!');
            return false;
        }
        else {
            jQuery.ajax({
                type: 'POST',
                url: '/api/drone_imagery/apply_other_selected_vi',
                data: {
                    'drone_run_project_id':project_drone_imagery_apply_other_vi_drone_run_project_id,
                    'selected_vi':JSON.stringify(project_drone_imagery_apply_other_vi_selected_indices),
                    'private_company_id':project_drone_imagery_apply_other_vi_drone_run_company_id,
                    'private_company_id_is_private':project_drone_imagery_apply_other_vi_drone_run_company_is_private
                },
                beforeSend: function(){
                    jQuery('#working_modal').modal('show');
                },
                success: function(response){
                    console.log(response);
                    jQuery('#working_modal').modal('hide');

                    if(response.error) {
                        alert(response.error);
                    }
                },
                error: function(response){
                    jQuery('#working_modal').modal('hide');
                    alert('Error applying other vegetation indices!');
                }
            });

            alert('It will take some time to process the selected vegetation indices and extract phenotypes for them.');
            location.reload();
        }
    });

    //
    // Standard process on raw images
    //

    var manage_drone_imagery_standard_process_raw_images_private_company_id;
    var manage_drone_imagery_standard_process_raw_images_private_company_is_private;
    var manage_drone_imagery_standard_process_raw_images_field_trial_id;
    var manage_drone_imagery_standard_process_raw_images_drone_run_id;
    var manage_drone_imagery_standard_process_raw_images_drone_run_band_id;
    var manage_drone_imagery_standard_process_raw_images_image_id;
    var manage_drone_imagery_standard_process_raw_images_stack_image_ids;
    var manage_drone_imagery_standard_process_raw_images_rotated_image_id;
    var manage_drone_imagery_standard_process_raw_images_polygon = [];
    var manage_drone_imagery_standard_process_raw_images_previous_polygon;
    var manage_drone_imagery_standard_process_raw_images_rotate_angle = 0.00;
    var manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new = {};
    var manage_drone_imagery_standard_process_raw_images_previous_polygons = [];
    var manage_drone_imagery_standard_process_raw_images_image_select_type = '';
    var ctx;
    var dronecroppingImg;

    jQuery(document).on('click', 'button[name="project_drone_imagery_stadard_process_raw_images_add_images"]', function(){
        manage_drone_imagery_standard_process_raw_images_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_standard_process_raw_images_drone_run_id = jQuery(this).data('drone_run_project_id');
        manage_drone_imagery_standard_process_raw_images_private_company_id = jQuery(this).data('private_company_id');
        manage_drone_imagery_standard_process_raw_images_private_company_is_private = jQuery(this).data('private_company_is_private');

        jQuery('#upload_drone_imagery_additional_raw_images_private_company_id').val(manage_drone_imagery_standard_process_raw_images_private_company_id);
        jQuery('#upload_drone_imagery_additional_raw_images_private_company_is_private').val(manage_drone_imagery_standard_process_raw_images_private_company_is_private);
        jQuery('#upload_drone_imagery_additional_raw_images_drone_run_id').val(manage_drone_imagery_standard_process_raw_images_drone_run_id);
        jQuery('#upload_drone_imagery_additional_raw_images_field_trial_id').val(manage_drone_imagery_standard_process_raw_images_field_trial_id);

        jQuery.ajax ({
            url : '/ajax/breeders/trial/'+manage_drone_imagery_standard_process_raw_images_drone_run_id+'/get_uploaded_additional_file',
            beforeSend : function(){
                jQuery('#upload_drone_imagery_additional_raw_images_div').html("[LOADING...]");
            },
            success: function(response){
                //console.log(response);
                var html = "<table class='table table-hover table-condensed table-bordered' id='upload_drone_imagery_additional_raw_images_table'><thead><tr><th>Filename</th><th>Date Uploaded</th><th>Uploaded By</th><th>Options</th></tr></thead><tbody>";
                for (i=0; i<response.files.length; i++) {
                    html = html + '<tr><td>'+response.files[i][4]+'</td><td>'+response.files[i][1]+'</td><td><a href="/solpeople/profile/'+response.files[i][2]+'">'+response.files[i][3]+'</a></td><td><a href="/breeders/phenotyping/download/'+response.files[i][0]+'">Download</a> | <a href="javascript:obsolete_additional_file_aerial_images('+manage_drone_imagery_standard_process_raw_images_drone_run_id+', '+response.files[i][0]+')">Remove</a></td></tr>';
                }
                html = html + "</tbody></table>";
                jQuery('#upload_drone_imagery_additional_raw_images_div').html(html);
                jQuery('#upload_drone_imagery_additional_raw_images_table').DataTable();
            },
            error: function(response){
                alert("Error retrieving aerial imagery additional raw captures uploaded files.");
            }
       });

        jQuery('#upload_drone_imagery_standard_process_additional_raw_images_dialog').modal('show');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_standard_process_raw_images"]', function() {
        showManageDroneImagerySection('manage_drone_imagery_standard_process_raw_images_div');

        manage_drone_imagery_standard_process_raw_images_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_standard_process_raw_images_drone_run_id = jQuery(this).data('drone_run_project_id');

        get_select_box('micasense_aligned_raw_images_grid','drone_imagery_standard_process_raw_images_image_id_select_div', {'name': 'drone_imagery_standard_process_raw_images_image_id_select', 'id': 'drone_imagery_standard_process_raw_images_image_id_select', 'empty':1, 'drone_run_project_id':manage_drone_imagery_standard_process_raw_images_drone_run_id });

        get_select_box('plot_polygon_templates_partial','drone_imagery_standard_process_raw_images_previous_polygons_div', {'name': 'drone_imagery_standard_process_raw_images_plot_sizes_select', 'id':'drone_imagery_standard_process_raw_images_plot_sizes_select', 'drone_run_project_id':manage_drone_imagery_standard_process_raw_images_drone_run_id, 'empty':1});

        get_select_box('trained_keras_mask_r_cnn_models','drone_imagery_standard_process_raw_images_retrain_mask_rcnn_models_div', {'name': 'drone_imagery_standard_process_raw_images_retrain_mask_rcnn_models_select', 'id':'drone_imagery_standard_process_raw_images_retrain_mask_rcnn_models_select' });

        jQuery.ajax({
            url : '/api/drone_imagery/get_drone_run_image_counts?drone_run_id='+manage_drone_imagery_standard_process_raw_images_drone_run_id,
            success: function(response){
                console.log(response);
                var html = '<table class="table table-bordered table-hover" id="manage_drone_imagery_standard_process_assigned_plot_images"><thead><tr><th>Plot Name</th><th>Plot Number</th><th>Image Counts</th></thead><tbody>';
                for (var i=0; i<response.data.length; i++) {
                    html = html + '<tr><td>'+response.data[i]['plot_name'] + '</td><td>' + response.data[i]['plot_number'] + '</td><td>' + response.data[i]['image_counts'] + '</td></tr>';
                }
                html = html +'</tbody></table>';
                jQuery('#drone_imagery_standard_process_raw_images_assigned_plot_images').html(html);
                jQuery('#manage_drone_imagery_standard_process_assigned_plot_images').DataTable();
            },
            error: function(response){
                alert('Error retrieving imaging event image counts!')
            }
        });
    });

    jQuery(document).on('click', 'span[name="drone_imagery_standard_process_raw_images_image_id_select"]', function() {
        manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new = {};
        crop_points = [];
        plot_polygons_generated_polygons = [];

        if (manage_drone_imagery_standard_process_raw_images_image_select_type == 'another_image') {
            var manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons_string = jQuery(this).data('polygons');
            var manage_drone_imagery_standard_process_raw_images_another_image_id = jQuery(this).data('image_id');

            manage_drone_imagery_standard_process_raw_images_image_select_type = '';

            if (!manage_drone_imagery_standard_process_raw_images_image_id) {
                alert('Please select an image from the images above first!');
                return false;
            }

            jQuery.ajax({
                url : '/api/drone_imagery/get_image?size=original_converted&image_id='+manage_drone_imagery_standard_process_raw_images_another_image_id,
                success: function(response){
                    console.log(response);

                    var canvas = document.getElementById('drone_imagery_standard_process_raw_images_show_another_image');
                    ctx = canvas.getContext('2d');
                    var image = new Image();
                    image.onload = function () {
                        canvas.width = this.naturalWidth;
                        canvas.height = this.naturalHeight;
                        ctx.drawImage(this, 0, 0);

                        var manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons = [];
                        if (manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons_string != '') {
                            manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons = JSON.parse(decodeURI(manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons_string));
                        }
                        console.log(manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons);

                        for (var i=0; i<manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons.length; i++) {
                            var previous_polygon = manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons[i];
                            console.log(previous_polygon);
                            for (var property in previous_polygon) {
                                if (previous_polygon.hasOwnProperty(property)) {
                                    plot_polygons_ind_4_points = previous_polygon[property];
                                    console.log(plot_polygons_ind_4_points);
                                    plot_polygons_display_points = plot_polygons_ind_4_points;
                                    if (plot_polygons_display_points.length == 4) {
                                        plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
                                    }
                                    drawPolyline(plot_polygons_display_points);
                                    drawWaypoints(plot_polygons_display_points, property, 0);
                                }
                            }
                        }
                    };
                    image.src = response.image_url;

                    jQuery.ajax({
                        url : '/api/drone_imagery/get_image?size=original_converted&image_id='+manage_drone_imagery_standard_process_raw_images_image_id,
                        success: function(response){
                            console.log(response);

                            background_image_width = response.image_width;
                            background_image_height = response.image_height;

                            var canvas = document.getElementById('drone_imagery_standard_process_raw_images_show');
                            ctx = canvas.getContext('2d');
                            var image = new Image();
                            image.onload = function () {
                                canvas.width = this.naturalWidth;
                                canvas.height = this.naturalHeight;
                                ctx.drawImage(this, 0, 0);
                            };
                            image.src = response.image_url;
                            dronecroppingImg = canvas;
                            dronecroppingImg.onmousedown = GetCoordinatesCroppedImage;

                            manage_drone_imagery_standard_process_raw_images_drone_run_band_id = response.drone_run_band_project_id;
                        },
                        error: function(response){
                            alert('Error retrieving image!')
                        }
                    });
                },
                error: function(response){
                    alert('Error retrieving image!')
                }
            });
        }
        if (manage_drone_imagery_standard_process_raw_images_image_select_type == 'another_image_second') {
            var manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons_string = jQuery(this).data('polygons');
            var manage_drone_imagery_standard_process_raw_images_another_image_id = jQuery(this).data('image_id');

            manage_drone_imagery_standard_process_raw_images_image_select_type = '';

            if (!manage_drone_imagery_standard_process_raw_images_image_id) {
                alert('Please select an image from the images above first!');
                return false;
            }

            jQuery.ajax({
                url : '/api/drone_imagery/get_image?size=original_converted&image_id='+manage_drone_imagery_standard_process_raw_images_another_image_id,
                success: function(response){
                    console.log(response);

                    var canvas = document.getElementById('drone_imagery_standard_process_raw_images_show_another_image_second');
                    ctx = canvas.getContext('2d');
                    var image = new Image();
                    image.onload = function () {
                        canvas.width = this.naturalWidth;
                        canvas.height = this.naturalHeight;
                        ctx.drawImage(this, 0, 0);

                        var manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons = [];
                        if (manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons_string != '') {
                            manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons = JSON.parse(decodeURI(manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons_string));
                        }
                        console.log(manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons);

                        for (var i=0; i<manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons.length; i++) {
                            var previous_polygon = manage_drone_imagery_standard_process_raw_images_another_image_previous_polygons[i];
                            console.log(previous_polygon);
                            for (var property in previous_polygon) {
                                if (previous_polygon.hasOwnProperty(property)) {
                                    plot_polygons_ind_4_points = previous_polygon[property];
                                    console.log(plot_polygons_ind_4_points);
                                    plot_polygons_display_points = plot_polygons_ind_4_points;
                                    if (plot_polygons_display_points.length == 4) {
                                        plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
                                    }
                                    drawPolyline(plot_polygons_display_points);
                                    drawWaypoints(plot_polygons_display_points, property, 0);
                                }
                            }
                        }
                    };
                    image.src = response.image_url;

                    jQuery.ajax({
                        url : '/api/drone_imagery/get_image?size=original_converted&image_id='+manage_drone_imagery_standard_process_raw_images_image_id,
                        success: function(response){
                            console.log(response);

                            background_image_width = response.image_width;
                            background_image_height = response.image_height;

                            var canvas = document.getElementById('drone_imagery_standard_process_raw_images_show');
                            ctx = canvas.getContext('2d');
                            var image = new Image();
                            image.onload = function () {
                                canvas.width = this.naturalWidth;
                                canvas.height = this.naturalHeight;
                                ctx.drawImage(this, 0, 0);
                            };
                            image.src = response.image_url;
                            dronecroppingImg = canvas;
                            dronecroppingImg.onmousedown = GetCoordinatesCroppedImage;

                            manage_drone_imagery_standard_process_raw_images_drone_run_band_id = response.drone_run_band_project_id;
                        },
                        error: function(response){
                            alert('Error retrieving image!')
                        }
                    });
                },
                error: function(response){
                    alert('Error retrieving image!')
                }
            });
        }
        else {
            manage_drone_imagery_standard_process_raw_images_image_id = jQuery(this).data('image_id');
            manage_drone_imagery_standard_process_raw_images_rotated_image_id = jQuery(this).data('image_id');
            manage_drone_imagery_standard_process_raw_images_stack_image_ids = jQuery(this).data('image_ids');
            var manage_drone_imagery_standard_process_raw_images_previous_polygons_string = jQuery(this).data('polygons');
            if (manage_drone_imagery_standard_process_raw_images_previous_polygons_string != '') {
                manage_drone_imagery_standard_process_raw_images_previous_polygons = JSON.parse(decodeURI(manage_drone_imagery_standard_process_raw_images_previous_polygons_string));
            }
            console.log(manage_drone_imagery_standard_process_raw_images_previous_polygons);

            jQuery.ajax({
                url : '/api/drone_imagery/get_image?size=original_converted&image_id='+manage_drone_imagery_standard_process_raw_images_image_id,
                success: function(response){
                    console.log(response);

                    background_image_width = response.image_width;
                    background_image_height = response.image_height;

                    var canvas = document.getElementById('drone_imagery_standard_process_raw_images_show');
                    ctx = canvas.getContext('2d');
                    var image = new Image();
                    image.onload = function () {
                        canvas.width = this.naturalWidth;
                        canvas.height = this.naturalHeight;
                        ctx.drawImage(this, 0, 0);
                    };
                    image.src = response.image_url;
                    dronecroppingImg = canvas;
                    dronecroppingImg.onmousedown = GetCoordinatesCroppedImage;

                    manage_drone_imagery_standard_process_raw_images_drone_run_band_id = response.drone_run_band_project_id;
                },
                error: function(response){
                    alert('Error retrieving image!')
                }
            });
        }
    });

    jQuery('#drone_imagery_standard_process_raw_images_draw_polygons').click(function(){
        var manage_drone_imagery_standard_process_raw_images_num_rows = jQuery('#drone_imagery_standard_process_raw_images_number_rows').val();
        var manage_drone_imagery_standard_process_raw_images_num_columns = jQuery('#drone_imagery_standard_process_raw_images_number_columns').val();

        if (manage_drone_imagery_standard_process_raw_images_num_rows == '') {
            alert('Please give the number of rows in the area of interest!');
            return false;
        }
        if (manage_drone_imagery_standard_process_raw_images_num_columns == '') {
            alert('Please give the number of columns in the area of interest!');
            return false;
        }

        if (crop_points.length < 4) {
            alert('Please select an area of interest on the image first by clicking the four corner points.');
            return false;
        }

        plot_polygons_num_rows_generated = parseInt(manage_drone_imagery_standard_process_raw_images_num_rows);
        plot_polygons_num_cols_generated = parseInt(manage_drone_imagery_standard_process_raw_images_num_columns);

        var section_width = background_image_width;
        var section_height = background_image_height;
        var section_top_row_left_offset = parseInt(crop_points[0]['x']);
        var section_bottom_row_left_offset = parseInt(crop_points[3]['x']);
        var section_left_column_top_offset = parseInt(crop_points[0]['y']);
        var section_left_column_bottom_offset = parseInt(background_image_height - crop_points[3]['y']);
        var section_top_row_right_offset = parseInt(background_image_width - crop_points[1]['x']);
        var section_right_column_bottom_offset = parseInt(background_image_height - crop_points[2]['y']);

        var total_gradual_left_shift = section_bottom_row_left_offset - section_top_row_left_offset;
        var col_left_shift_increment = total_gradual_left_shift / plot_polygons_num_rows_generated;

        var total_gradual_vertical_shift = section_right_column_bottom_offset - section_left_column_bottom_offset;
        var col_vertical_shift_increment = total_gradual_vertical_shift / plot_polygons_num_cols_generated;

        var col_width = (section_width - section_top_row_left_offset - section_top_row_right_offset) / plot_polygons_num_cols_generated;
        var row_height = (section_height - section_left_column_top_offset - section_left_column_bottom_offset) / plot_polygons_num_rows_generated;

        var x_pos = section_top_row_left_offset;
        var y_pos = section_left_column_top_offset;

        var row_num = 1;
        for (var i=0; i<plot_polygons_num_rows_generated; i++) {
            for (var j=0; j<plot_polygons_num_cols_generated; j++) {
                var x_pos_val = x_pos;
                var y_pos_val = y_pos;
                plot_polygons_generated_polygons.push([
                    {x:x_pos_val, y:y_pos_val},
                    {x:x_pos_val + col_width, y:y_pos_val},
                    {x:x_pos_val + col_width, y:y_pos_val + row_height},
                    {x:x_pos_val, y:y_pos_val + row_height}
                ]);
                x_pos = x_pos + col_width;
                y_pos = y_pos - col_vertical_shift_increment;
            }
            x_pos = section_top_row_left_offset + (row_num * col_left_shift_increment);
            y_pos = y_pos + row_height + total_gradual_vertical_shift;
            row_num = row_num + 1;
        }
        console.log(plot_polygons_generated_polygons);

        plot_polygons_total_height_generated = row_height * plot_polygons_num_rows_generated;
        plot_polygons_number_generated = plot_polygons_generated_polygons.length;

        manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new = {};
        var drone_imagery_plot_polygons_display_new = {};

        for (var i=0; i<plot_polygons_generated_polygons.length; i++) {
            plot_polygons_ind_4_points = plot_polygons_generated_polygons[i];
            plot_polygons_display_points = plot_polygons_ind_4_points;
            if (plot_polygons_display_points.length == 4) {
                plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
            }
            drawPolyline(plot_polygons_display_points);
            drawWaypoints(plot_polygons_display_points, i, 0);
            drone_imagery_plot_generated_polygons[i] = plot_polygons_ind_4_points;
            manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new[i] = plot_polygons_ind_4_points;
            drone_imagery_plot_polygons_display[i] = plot_polygons_display_points;
            drone_imagery_plot_polygons_display_new[i] = plot_polygons_display_points;
        }

        plot_polygons_template_dimensions.push({
            'num_rows':plot_polygons_num_rows_generated,
            'num_cols':plot_polygons_num_cols_generated,
            'total_plot_polygons':plot_polygons_num_rows_generated*plot_polygons_num_cols_generated,
            'plot_polygons':manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new,
            'plot_polygons_display':drone_imagery_plot_polygons_display_new
        });
        console.log(plot_polygons_template_dimensions);

        var table_html = '<table class="table table-bordered table-hover"><thead><tr><th>Generated Index</th><th>Plot Number</th></tr></thead><tbody>';
        for (var gen_index in manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new) {
            if (manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new.hasOwnProperty(gen_index)) {
                table_html = table_html + '<tr><td>'+gen_index+'</td><td><input type="text" class="form-control" placeholder="e.g. 1001" name="manage_drone_imagery_standard_process_raw_images_given_plot_number" data-generated_index="'+gen_index+'"></td></tr>';
            }
        }
        table_html = table_html + '</tbody></table>';

        jQuery('#drone_imagery_standard_process_raw_images_polygon_assign_table').html(table_html);
    });

    jQuery('#drone_imagery_standard_process_raw_images_assign_plot').click(function(){

        var manage_drone_imagery_standard_process_raw_images_partial_template_name = jQuery('#drone_imagery_standard_process_raw_images_partial_template_name').val();
        if (manage_drone_imagery_standard_process_raw_images_partial_template_name == '') {
            alert('Please give a partial template name');
            return false;
        }
        var manage_drone_imagery_standard_process_raw_images_given_plot_numbers = {};
        jQuery('input[name="manage_drone_imagery_standard_process_raw_images_given_plot_number"]').each(function() {
            if (jQuery(this).val() != '') {
                manage_drone_imagery_standard_process_raw_images_given_plot_numbers[jQuery(this).data('generated_index')] = jQuery(this).val();
            }
        });
        if (Object.keys(manage_drone_imagery_standard_process_raw_images_given_plot_numbers).length < 1) {
            alert('Please give the plot numbers corresponding to the generated index numbers of the plot polygons!');
            return false;
        }

        jQuery.ajax({
            url : '/api/drone_imagery/manual_assign_plot_polygon_save_partial_template',
            type : 'POST',
            data : {
                'field_trial_id':manage_drone_imagery_standard_process_raw_images_field_trial_id,
                'drone_run_project_id':manage_drone_imagery_standard_process_raw_images_drone_run_id,
                'image_ids':manage_drone_imagery_standard_process_raw_images_stack_image_ids,
                'polygon':JSON.stringify(manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new),
                'polygon_plot_numbers':JSON.stringify(manage_drone_imagery_standard_process_raw_images_given_plot_numbers),
                'angle_rotated':manage_drone_imagery_standard_process_raw_images_rotate_angle,
                'partial_template_name':manage_drone_imagery_standard_process_raw_images_partial_template_name
            },
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                } else if (response.warning) {
                    alert(response.warning);
                } else {
                    get_select_box('plot_polygon_templates_partial','drone_imagery_standard_process_raw_images_previous_polygons_div', {'name': 'drone_imagery_standard_process_raw_images_plot_sizes_select', 'id':'drone_imagery_standard_process_raw_images_plot_sizes_select', 'drone_run_project_id':manage_drone_imagery_standard_process_raw_images_drone_run_id, 'empty':1});

                    get_select_box('micasense_aligned_raw_images_grid','drone_imagery_standard_process_raw_images_image_id_select_div', {'name': 'drone_imagery_standard_process_raw_images_image_id_select', 'id': 'drone_imagery_standard_process_raw_images_image_id_select', 'empty':1, 'drone_run_project_id':manage_drone_imagery_standard_process_raw_images_drone_run_id });

                    jQuery.ajax({
                        url : '/api/drone_imagery/get_drone_run_image_counts?drone_run_id='+manage_drone_imagery_standard_process_raw_images_drone_run_id,
                        success: function(response){
                            console.log(response);
                            var html = '<table class="table table-bordered table-hover" id="manage_drone_imagery_standard_process_assigned_plot_images"><thead><tr><th>Plot Name</th><th>Plot Number</th><th>Image Counts</th></thead><tbody>';
                            for (var i=0; i<response.data.length; i++) {
                                html = html + '<tr><td>'+response.data[i]['plot_name'] + '</td><td>' + response.data[i]['plot_number'] + '</td><td>' + response.data[i]['image_counts'] + '</td></tr>';
                            }
                            html = html +'</tbody></table>';
                            jQuery('#drone_imagery_standard_process_raw_images_assigned_plot_images').html(html);
                            jQuery('#manage_drone_imagery_standard_process_assigned_plot_images').DataTable();
                        },
                        error: function(response){
                            alert('Error retrieving imaging event image counts!')
                        }
                    });

                    //alert('Plot-images saved!');
                }
            },
            error: function(response){
                alert('Error saving partial template!')
            }
        });

        jQuery.ajax({
            url : '/api/drone_imagery/manual_assign_plot_polygon',
            type : 'POST',
            data : {
                'field_trial_id':manage_drone_imagery_standard_process_raw_images_field_trial_id,
                'drone_run_project_id':manage_drone_imagery_standard_process_raw_images_drone_run_id,
                'image_ids':manage_drone_imagery_standard_process_raw_images_stack_image_ids,
                'polygon':JSON.stringify(manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new),
                'polygon_plot_numbers':JSON.stringify(manage_drone_imagery_standard_process_raw_images_given_plot_numbers),
                'angle_rotated':manage_drone_imagery_standard_process_raw_images_rotate_angle,
                'partial_template_name':manage_drone_imagery_standard_process_raw_images_partial_template_name
            },
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                } else if (response.warning) {
                    alert(response.warning);
                } else {
                    //alert('Plot-images saved!');
                }
            },
            error: function(response){
                alert('Error cropping and saving plot images!')
            }
        });
        return false;
    });

    jQuery('#drone_imagery_standard_process_raw_images_rotate_image').click(function(){
    });

    jQuery('#drone_imagery_standard_process_raw_images_clear_polygon').click(function(){
        crop_points = [];
        manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new = {};
        plot_polygons_generated_polygons = [];

        jQuery.ajax({
            url : '/api/drone_imagery/get_image?size=original_converted&image_id='+manage_drone_imagery_standard_process_raw_images_image_id,
            success: function(response){
                console.log(response);

                var canvas = document.getElementById('drone_imagery_standard_process_raw_images_show');
                ctx = canvas.getContext('2d');
                var image = new Image();
                image.onload = function () {
                    canvas.width = this.naturalWidth;
                    canvas.height = this.naturalHeight;
                    ctx.drawImage(this, 0, 0);
                };
                image.src = response.image_url;
                dronecroppingImg = canvas;
                dronecroppingImg.onmousedown = GetCoordinatesCroppedImage;
            },
            error: function(response){
                alert('Error retrieving image!')
            }
        });
    });

    jQuery('#drone_imagery_standard_process_raw_images_save_polygon').click(function() {
        if (crop_points.length != 4) {
            alert('Click the four corners of the plot in the image first!');
            return false;
        }
        else {
            manage_drone_imagery_standard_process_raw_images_polygon = crop_points;
        }
    });

    jQuery('#drone_imagery_standard_process_raw_images_paste_polygon').click(function(){
        if (manage_drone_imagery_standard_process_raw_images_polygon.length != 4) {
            alert('First save a plot-polygon!');
            return false;
        }
        else {
            drone_imagery_standard_process_plot_polygon_click_type = 'standard_process_raw_images_paste_polygon';
            alert('Now click a point on the image where to paste the top-left corner of the saved polygon.');
        }
    });

    jQuery('#drone_imagery_standard_process_raw_images_paste_previous_polygon').click(function(){
        manage_drone_imagery_standard_process_raw_images_previous_polygon = jQuery('#drone_imagery_standard_process_raw_images_plot_sizes_select').val();
        console.log(manage_drone_imagery_standard_process_raw_images_previous_polygon);
        if (manage_drone_imagery_standard_process_raw_images_previous_polygon == '') {
            alert('To do this first select a previously used polygon, if there exists one!');
            return false;
        }
        drone_imagery_standard_process_plot_polygon_click_type = 'standard_process_raw_images_paste_previous_polygon';
        alert('Now click a point on the image where to paste the top-left corner of the saved polygon.');
    });

    //
    // Mask RCNN
    //

    var drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_name = '';
    var drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_desc = '';
    var drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_type = '';
    var drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_id = '';

    jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn_modal_button').click(function(){
        jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn_modal').modal('show');
        return false;
    });

    jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn').click(function(){
        drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_name = jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_name').val();
        drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_desc = jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_desc').val();
        drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_type = jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn_models_select').val();

        if (drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_name == '' || drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_desc == '') {
            alert('Please give a model name and description');
            return false;
        }
        else {
            jQuery.ajax({
                type: 'GET',
                url: '/api/drone_imagery/retrain_mask_rcnn?model_name='+drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_name+'&model_description='+drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_desc+'&model_type='+drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_type,
                dataType: "json",
                beforeSend: function() {
                    jQuery('#working_modal').modal('show');
                },
                success: function(response){
                    jQuery('#working_modal').modal('hide');
                    console.log(response);
                    if (response.error) {
                        alert(response.error);
                    }
                },
                error: function(response){
                    jQuery('#working_modal').modal('hide');
                    alert('Error training mask rcnn!');
                }
            });
        }
    });

    jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn_predict_button').click(function(){
        drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_id = jQuery('#drone_imagery_standard_process_raw_images_retrain_mask_rcnn_models_select').val();

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/predict_mask_rcnn?model_id='+drone_imagery_standard_process_raw_images_retrain_mask_rcnn_model_id+'&image_id='+manage_drone_imagery_standard_process_raw_images_image_id,
            dataType: "json",
            beforeSend: function() {
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                jQuery('#working_modal').modal('hide');
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }
            },
            error: function(response){
                jQuery('#working_modal').modal('hide');
                alert('Error predicting mask rcnn!');
            }
        });
    });

    jQuery('#drone_imagery_standard_process_raw_images_paste_previous_polygon_in_place').click(function(){
        for (var i=0; i<manage_drone_imagery_standard_process_raw_images_previous_polygons.length; i++) {
            var previous_polygon = manage_drone_imagery_standard_process_raw_images_previous_polygons[i];
            for (var property in previous_polygon) {
                if (previous_polygon.hasOwnProperty(property)) {
                    plot_polygons_ind_4_points = previous_polygon[property];
                    plot_polygons_display_points = plot_polygons_ind_4_points;
                    if (plot_polygons_display_points.length == 4) {
                        plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
                    }
                    drawPolyline(plot_polygons_display_points);
                    drawWaypoints(plot_polygons_display_points, property, 0);
                }
            }
        }
    });

    jQuery('#drone_imagery_standard_process_raw_images_paste_previous_polygon_view_image').click(function(){
        manage_drone_imagery_standard_process_raw_images_image_select_type = 'another_image';
        alert('Now choose the image from the grid above');
    });

    jQuery('#drone_imagery_standard_process_raw_images_paste_previous_polygon_view_image_second').click(function(){
        manage_drone_imagery_standard_process_raw_images_image_select_type = 'another_image_second';
        alert('Now choose the image from the grid above');
    });

    //
    // Phenotype calc buttons
    //

    jQuery(document).on('click', 'button[name="project_drone_imagery_phenotype_run"]', function(){
        manage_drone_imagery_standard_process_drone_run_project_id = jQuery(this).data('drone_run_project_id');

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id,
            dataType: "json",
            beforeSend: function (){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                jQuery('#working_modal').modal('hide');
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }

                var html = "<center><b>Field Trial Planting Date</b>: "+response.planting_date+"<br/><b>Imaging Event Date</b>: "+response.drone_run_date+"<br/><b>Number of Weeks</b>: "+response.rounded_time_difference_weeks+"<br/><b>Number of Weeks Ontology Term</b>: "+response.time_ontology_week_term+"<br/><b>Number of Days</b>:"+response.time_difference_days+"<br/><b>Number of Days Ontology Term</b>: "+response.time_ontology_day_term+"<br/><br/></center>";
                jQuery('#drone_imagery_week_term_div').html(html);

                manage_drone_imagery_standard_process_phenotype_time = response.time_ontology_day_cvterm_id;

                jQuery('#drone_imagery_calc_phenotypes_trial_dialog').modal('show');
            },
            error: function(response){
                alert('Error getting time terms!');
                jQuery('#working_modal').modal('hide');
            }
        });

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/retrieve_preview_plot_images?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id,
            dataType: "json",
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }
                else {
                    manage_drone_imagery_standard_process_preview_image_urls = response.plot_polygon_preview_urls;
                    manage_drone_imagery_standard_process_preview_image_sizes = response.plot_polygon_preview_image_sizes;

                    drone_imagery_standard_process_preview_plot_polygons_draw('drone_imagery_generate_phenotypes_process_preview_svg_div', 5, 5);
                }
            },
            error: function(response){
                alert('Error getting plot images to preview!');
            }
        });
    });

    jQuery(document).on("change", "#drone_imagery_generate_phenotypes_process_margin_top_bottom", function() {
        var plot_margin_left_right = jQuery('#drone_imagery_generate_phenotypes_process_margin_left_right').val();
        var plot_margin_top_bottom = jQuery('#drone_imagery_generate_phenotypes_process_margin_top_bottom').val();
        if (plot_margin_left_right != '' && plot_margin_top_bottom != '') {
            if (plot_margin_left_right >= 50 || plot_margin_top_bottom >= 50) {
                alert('Margins cannot be greater or equal to 50%! That would exclude the entire photo!');
                return false
            }
            drone_imagery_standard_process_preview_plot_polygons_draw('drone_imagery_generate_phenotypes_process_preview_svg_div', plot_margin_left_right, plot_margin_top_bottom);
        }
        else {
            alert('Please give margin values!');
            return false;
        }
    });

    jQuery(document).on("change", "#drone_imagery_generate_phenotypes_process_margin_left_right", function() {
        var plot_margin_left_right = jQuery('#drone_imagery_generate_phenotypes_process_margin_left_right').val();
        var plot_margin_top_bottom = jQuery('#drone_imagery_generate_phenotypes_process_margin_top_bottom').val();
        if (plot_margin_left_right != '' && plot_margin_top_bottom != '') {
            if (plot_margin_left_right >= 50 || plot_margin_top_bottom >= 50) {
                alert('Margins cannot be greater or equal to 50%! That would exclude the entire photo!');
                return false
            }
            drone_imagery_standard_process_preview_plot_polygons_draw('drone_imagery_generate_phenotypes_process_preview_svg_div', plot_margin_left_right, plot_margin_top_bottom);
        }
        else {
            alert('Please give margin values!');
            return false;
        }
    });

    jQuery('#drone_imagery_calculate_phenotypes_zonal_stats_trial_select').click(function(){
        if (manage_drone_imagery_standard_process_phenotype_time == '') {
            alert('Time of phenotype not set! This should not happen so please contact us!');
            return false;
        }

        var plot_margin_left_right = jQuery('#drone_imagery_generate_phenotypes_process_margin_left_right').val();
        var plot_margin_top_bottom = jQuery('#drone_imagery_generate_phenotypes_process_margin_top_bottom').val();

        if (plot_margin_top_bottom == '') {
            alert('Please give a plot polygon margin on top and bottom for phenotypes!');
            return false;
        }
        if (plot_margin_left_right == '') {
            alert('Please give a plot polygon margin on left and right for phenotypes!');
            return false;
        }
        if (plot_margin_left_right >= 50 || plot_margin_top_bottom >= 50) {
            alert('Margins cannot be greater or equal to 50%! That would exclude the entire photo!');
            return false
        }

        alert("Phenotype generation will occur in the background. You can check the indicator on this page by refreshing the page.");

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/generate_phenotypes?drone_run_project_id='+manage_drone_imagery_standard_process_drone_run_project_id+'&time_cvterm_id='+manage_drone_imagery_standard_process_phenotype_time+'&standard_process_type='+jQuery('#drone_imagery_generate_phenotypes_process_type').val()+'&phenotypes_plot_margin_top_bottom='+plot_margin_top_bottom+'&phenotypes_plot_margin_right_left='+plot_margin_left_right,
            dataType: "json",
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }
                if (response.success) {
                    alert('Imaging event phenotypes stored!');
                }
            },
            error: function(response){
                alert('Error generating imaging event phenotypes!');
            }
        });

        location.reload();
    });

    //
    // Minimal VI Standard Process ()
    //

    var manage_drone_imagery_standard_process_minimal_vi_drone_run_project_id;
    var manage_drone_imagery_standard_process_minimal_vi_phenotype_time = '';

    jQuery(document).on('click', 'button[name=project_drone_imagery_standard_process_minimal_vi]', function(){
        manage_drone_imagery_standard_process_minimal_vi_drone_run_project_id = jQuery(this).data('drone_run_project_id');

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_standard_process_minimal_vi_drone_run_project_id,
            dataType: "json",
            beforeSend: function (){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                jQuery('#working_modal').modal('hide');
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }

                var html = "<center><b>Field Trial Planting Date</b>: "+response.planting_date+"<br/><b>Imaging Event Date</b>: "+response.drone_run_date+"<br/><b>Number of Weeks</b>: "+response.rounded_time_difference_weeks+"<br/><b>Number of Weeks Ontology Term</b>: "+response.time_ontology_week_term+"<br/><b>Number of Days</b>:"+response.time_difference_days+"<br/><b>Number of Days Ontology Term</b>: "+response.time_ontology_day_term+"<br/><br/></center>";
                jQuery('#drone_imagery_minimal_vi_standard_process_week_term_div').html(html);
                manage_drone_imagery_standard_process_minimal_vi_phenotype_time = response.time_ontology_day_cvterm_id;
            },
            error: function(response){
                alert('Error getting time terms!');
                jQuery('#working_modal').modal('hide');
            }
        });

        jQuery('#drone_imagery_minimal_vi_standard_process_dialog').modal('show');
    });

    jQuery('#drone_imagery_minimal_vi_standard_process_select').click(function() {
        if (manage_drone_imagery_standard_process_minimal_vi_phenotype_time == '') {
            alert('Time of phenotype not set for minimal vi process! This should not happen so please contact us');
            return false;
        }

        alert("Minimal vegetative index standard process will occur in the background. You can check the indicator on this page by refreshing the page.");

        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/standard_process_minimal_vi_apply?drone_run_project_id='+manage_drone_imagery_standard_process_minimal_vi_drone_run_project_id,
            dataType: "json",
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                } else {
                    alert('Minimal vegetative index standard process complete! Phenotype generation may still be occurring.');
                    location.reload();
                }
            },
            error: function(response){
                alert('Error running minimal vegetative index standard process!');
            }
        });

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/generate_phenotypes?drone_run_project_id='+manage_drone_imagery_standard_process_minimal_vi_drone_run_project_id+'&time_cvterm_id='+manage_drone_imagery_standard_process_minimal_vi_phenotype_time+'&standard_process_type=minimal,minimal_vi',
            dataType: "json",
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }
                if (response.success) {
                    alert('Drone image phenotypes stored for minimal vegetative index standard process!');
                }
            },
            error: function(response){
                alert('Error generating drone image phenotypes for minial vegetative index standard process!');
            }
        });

        location.reload();
    });

    //
    // Extended Standard Process
    //

    var manage_drone_imagery_standard_process_extended_drone_run_project_id;
    var manage_drone_imagery_standard_process_extended_phenotype_time = '';

    jQuery(document).on('click', 'button[name="project_drone_imagery_standard_process_extended"]', function() {
        manage_drone_imagery_standard_process_extended_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_standard_process_extended_drone_run_project_id,
            dataType: "json",
            beforeSend: function (){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                jQuery('#working_modal').modal('hide');
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }

                var html = "<center><b>Field Trial Planting Date</b>: "+response.planting_date+"<br/><b>Imaging Event Date</b>: "+response.drone_run_date+"<br/><b>Number of Weeks</b>: "+response.rounded_time_difference_weeks+"<br/><b>Number of Weeks Ontology Term</b>: "+response.time_ontology_week_term+"<br/><b>Number of Days</b>:"+response.time_difference_days+"<br/><b>Number of Days Ontology Term</b>: "+response.time_ontology_day_term+"<br/><br/></center>";
                jQuery('#drone_imagery_extended_standard_process_week_term_div').html(html);
                manage_drone_imagery_standard_process_extended_phenotype_time = response.time_ontology_day_cvterm_id;
            },
            error: function(response){
                alert('Error getting time terms!');
                jQuery('#working_modal').modal('hide');
            }
        });
        jQuery('#drone_imagery_extended_standard_process_dialog').modal('show');
    });

    jQuery('#drone_imagery_extended_standard_process_select').click(function(){
        if (manage_drone_imagery_standard_process_extended_phenotype_time == '') {
            alert('Time of phenotype not set for extended standard process! This should not happen so please contact us!');
            return false;
        }

        alert("Extended standard process will occur in the background. You can check the indicator on this page by refreshing the page.");

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/standard_process_extended_apply?drone_run_project_id='+manage_drone_imagery_standard_process_extended_drone_run_project_id+'&time_days_cvterm_id='+manage_drone_imagery_standard_process_extended_phenotype_time+'&standard_process_type=extended',
            dataType: "json",
            success: function(response){
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }
            },
            error: function(response){
                alert('Error running extended standard process!');
            }
        });

        location.reload();
    });

    //
    // Download Phenotypes
    //

    var manage_drone_imagery_download_phenotypes_field_trial_id = undefined;
    var manage_drone_imagery_download_phenotypes_trait_ids = [];
    var manage_drone_imagery_download_phenotypes_image_type_ids = [];

    jQuery('#download_phenotypes_drone_imagery_link').click(function(){
        jQuery('#drone_imagery_download_phenotypes_dialog').modal('show');
        get_select_box('trials', 'drone_imagery_download_phenotypes_trial_select_div', { 'name' : 'drone_imagery_download_phenotypes_field_trial_id', 'id' : 'drone_imagery_download_phenotypes_field_trial_id', 'empty':1, 'multiple':0 });

        manage_drone_imagery_download_phenotypes_field_trial_id = undefined;
        manage_drone_imagery_download_phenotypes_trait_ids = [];
    });

    jQuery('#drone_imagery_download_phenotypes_field_trial_select_step').click(function(){
        manage_drone_imagery_download_phenotypes_field_trial_id = jQuery('#drone_imagery_download_phenotypes_field_trial_id').val();
        if (manage_drone_imagery_download_phenotypes_field_trial_id == '') {
            alert('Please select a field trial first!');
        } else {
            get_select_box('traits', 'drone_imagery_download_phenotypes_trait_select_div', { 'name' : 'drone_imagery_download_phenotypes_trait_id_select', 'id' : 'drone_imagery_download_phenotypes_trait_id_select', 'empty':0, 'multiple':1, 'size': 20, 'trial_ids':manage_drone_imagery_download_phenotypes_field_trial_id, 'stock_type':'plot' });

            get_select_box('drone_imagery_plot_polygon_types', 'drone_imagery_download_phenotypes_image_type_select_div', { 'name' : 'drone_imagery_download_phenotypes_image_type_select_ids', 'id' : 'drone_imagery_download_phenotypes_image_type_select_ids', 'empty':0, 'multiple':1, 'size': 20 });

            Workflow.complete("#drone_imagery_download_phenotypes_field_trial_select_step");
            Workflow.focus('#drone_imagery_download_phenotypes_workflow', 1);
        }
        return false;
    });

    jQuery('#drone_imagery_download_phenotypes_trait_select_step').click(function(){
        manage_drone_imagery_download_phenotypes_trait_ids = jQuery('#drone_imagery_download_phenotypes_trait_id_select').val();
        if (manage_drone_imagery_download_phenotypes_trait_ids == null || manage_drone_imagery_download_phenotypes_trait_ids == undefined) {
            alert('Please select at least one observation variable!');
            return false;
        }
        if (manage_drone_imagery_download_phenotypes_trait_ids.length < 1){
            alert('Please select at least one observation variable!');
        } else {
            Workflow.complete("#drone_imagery_download_phenotypes_trait_select_step");
            Workflow.focus('#drone_imagery_download_phenotypes_workflow', 2);
        }
        return false;
    });

    jQuery('#drone_imagery_download_phenotypes_image_type_select_step').click(function(){
        manage_drone_imagery_download_phenotypes_image_type_ids = jQuery('#drone_imagery_download_phenotypes_image_type_select_ids').val();
        if (manage_drone_imagery_download_phenotypes_image_type_ids == null || manage_drone_imagery_download_phenotypes_image_type_ids == undefined) {
            alert('Please select at least one image type!');
            return false;
        }
        if (manage_drone_imagery_download_phenotypes_image_type_ids.length < 1){
            alert('Please select at least one image type!');
        } else {
            Workflow.complete("#drone_imagery_download_phenotypes_image_type_select_step");
            Workflow.focus('#drone_imagery_download_phenotypes_workflow', 3);
        }
        return false;
    });

    jQuery('#drone_imagery_download_phenotypes_confirm_step').click(function() {
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/analysis_query',
            dataType: "json",
            data: {
                'observation_variable_id_list':JSON.stringify(manage_drone_imagery_download_phenotypes_trait_ids),
                'field_trial_id_list':JSON.stringify([manage_drone_imagery_download_phenotypes_field_trial_id]),
                'project_image_type_id_list':JSON.stringify(manage_drone_imagery_download_phenotypes_image_type_ids),
                'format':'csv'
            },
            beforeSend: function (){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                jQuery('#working_modal').modal('hide');
                console.log(response);
                if(response.error) {
                    alert(response.error);
                }
                jQuery('#drone_imagery_download_phenotypes_file_div').html('Download File: <a href="'+response.file+'">'+response.file+'</a>');
            },
            error: function(response){
                alert('Error downloading drone image phenotypes!');
                jQuery('#working_modal').modal('hide');
            }
        });
    });

    //
    // Growing Degree Days Calculation
    //

    var manage_drone_imagery_calculate_gdd_field_trial_id;
    var manage_drone_imagery_calculate_gdd_drone_run_project_id;
    var manage_drone_imagery_calculate_gdd_phenotype_time;

    jQuery(document).on('click', 'button[name=drone_imagery_drone_run_calculate_gdd]', function() {
        manage_drone_imagery_calculate_gdd_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_calculate_gdd_drone_run_project_id = jQuery(this).data('drone_run_project_id');

        jQuery.ajax({
            url : '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_calculate_gdd_drone_run_project_id,
            success: function(response){
                console.log(response);
                var html = "<center><b>Field Trial Planting Date</b>: "+response.planting_date+"<br/><b>Imaging Event Date</b>: "+response.drone_run_date+"<br/><b>Number of Weeks</b>: "+response.rounded_time_difference_weeks+"<br/><b>Number of Weeks Ontology Term</b>: "+response.time_ontology_week_term+"<br/><b>Number of Days</b>:"+response.time_difference_days+"<br/><b>Number of Days Ontology Term</b>: "+response.time_ontology_day_term+"<br/><br/></center>";
                jQuery('#drone_imagery_calculate_gdd_time_div').html(html);
                manage_drone_imagery_calculate_gdd_phenotype_time = response.time_ontology_day_cvterm_id;

                jQuery('#drone_imagery_calculate_gdd_dialog').modal('show');
            },
            error: function(response){
                alert('Error getting gdd!')
            }
        });
    });

    jQuery('#drone_imagery_upload_gdd_submit').click(function(){
        var manage_drone_imagery_calculate_gdd_base_temp = jQuery('#drone_imagery_calculate_gdd_base_temperature_input').val();
        var manage_drone_imagery_calculate_gdd_formula = jQuery('#drone_imagery_calculate_gdd_formula_input').val();

        if (manage_drone_imagery_calculate_gdd_base_temp == '') {
            alert('Please select the temperature threshold first!');
            return false;
        }
        else {
            jQuery.ajax({
                url : '/api/drone_imagery/growing_degree_days?drone_run_project_id='+manage_drone_imagery_calculate_gdd_drone_run_project_id+'&formula='+manage_drone_imagery_calculate_gdd_formula+'&gdd_base_temperature='+manage_drone_imagery_calculate_gdd_base_temp+'&field_trial_id='+manage_drone_imagery_calculate_gdd_field_trial_id,
                beforeSend: function(){
                    jQuery('#working_modal').modal('show');
                },
                success: function(response){
                    console.log(response);
                    jQuery('#working_modal').modal('hide');
                    location.reload();
                },
                error: function(response){
                    jQuery('#working_modal').modal('hide');
                    alert('Error calculating growing degree days!');
                }
            });
        }
    });

    //
    // Precipitation Sum Calculation
    //

    var manage_drone_imagery_calculate_precipitation_field_trial_id;
    var manage_drone_imagery_calculate_precipitation_drone_run_project_id;
    var manage_drone_imagery_calculate_precipitation_phenotype_time;

    jQuery(document).on('click', 'button[name=drone_imagery_drone_run_calculate_precipitation_sum]', function() {
        manage_drone_imagery_calculate_precipitation_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_calculate_precipitation_drone_run_project_id = jQuery(this).data('drone_run_project_id');

        jQuery.ajax({
            url : '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_calculate_precipitation_drone_run_project_id,
            success: function(response){
                console.log(response);
                var html = "<center><b>Field Trial Planting Date</b>: "+response.planting_date+"<br/><b>Imaging Event Date</b>: "+response.drone_run_date+"<br/><b>Number of Weeks</b>: "+response.rounded_time_difference_weeks+"<br/><b>Number of Weeks Ontology Term</b>: "+response.time_ontology_week_term+"<br/><b>Number of Days</b>:"+response.time_difference_days+"<br/><b>Number of Days Ontology Term</b>: "+response.time_ontology_day_term+"<br/><br/></center>";
                jQuery('#drone_imagery_calculate_precipitation_time_div').html(html);
                manage_drone_imagery_calculate_precipitation_phenotype_time = response.time_ontology_day_cvterm_id;

                jQuery('#drone_imagery_calculate_precipitation_dialog').modal('show');
            },
            error: function(response){
                alert('Error getting gdd!')
            }
        });
    });

    jQuery('#drone_imagery_upload_precipitation_sum_submit').click(function(){
        var manage_drone_imagery_calculate_precipitation_sum_formula = jQuery('#drone_imagery_calculate_precipitation_sum_formula_input').val();
        jQuery.ajax({
            url : '/api/drone_imagery/precipitation_sum?drone_run_project_id='+manage_drone_imagery_calculate_precipitation_drone_run_project_id+'&formula='+manage_drone_imagery_calculate_precipitation_sum_formula+'&field_trial_id='+manage_drone_imagery_calculate_precipitation_field_trial_id,
            beforeSend: function(){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                console.log(response);
                jQuery('#working_modal').modal('hide');
                location.reload();
            },
            error: function(response){
                jQuery('#working_modal').modal('hide');
                alert('Error calculating precipitation sum!');
            }
        });
    });

    //
    // Add GeoCoordinate Params
    //

    var manage_drone_imagery_add_geocoordinate_params_field_trial_id;
    var manage_drone_imagery_add_geocoordinate_params_drone_run_project_id;

    jQuery(document).on('click', 'button[name=drone_imagery_drone_run_band_add_geocoordinate_params]', function() {
        manage_drone_imagery_add_geocoordinate_params_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_add_geocoordinate_params_drone_run_project_id = jQuery(this).data('drone_run_project_id');

        jQuery('#upload_drone_imagery_geocoordinate_param_field_trial_id').val(manage_drone_imagery_add_geocoordinate_params_field_trial_id);
        jQuery('#upload_drone_imagery_geocoordinate_param_drone_run_id').val(manage_drone_imagery_add_geocoordinate_params_drone_run_project_id);

        jQuery('#upload_drone_imagery_geocoordinate_param_dialog').modal('show');
    });

    jQuery('#upload_drone_imagery_geocoordinate_param_form').submit(function() {
        jQuery('#working_msg').html('This can potentially take time to complete. Ensure the file(s) have completely transferred to the server before closing this tab.');
        jQuery('#working_modal').modal('show');
        return true;
    });

    //
    // Keras CNN Training JS
    //

    var manage_drone_imagery_train_keras_drone_run_ids = [];
    var manage_drone_imagery_train_keras_field_trial_id_array = [];
    var manage_drone_imagery_train_keras_field_trial_id_string = '';
    var manage_drone_imagery_train_keras_trait_id;
    var manage_drone_imagery_train_keras_aux_trait_ids;
    var manage_drone_imagery_train_keras_plot_polygon_type_ids = [];
    var manage_drone_imagery_train_keras_temporary_model_file = '';
    var manage_drone_imagery_train_keras_temporary_model_input_file = '';
    var manage_drone_imagery_train_keras_temporary_model_input_aux_file = '';
    var manage_drone_imagery_train_keras_class_map = '';

    var manage_drone_imagery_predict_keras_drone_run_ids = [];
    var manage_drone_imagery_predict_keras_field_trial_id_array = [];
    var manage_drone_imagery_predict_keras_field_trial_id_string = '';
    var manage_drone_imagery_predict_keras_plot_polygon_type_ids = [];
    var manage_drone_imagery_predict_keras_model_id = '';
    var manage_drone_imagery_predict_keras_aux_trait_ids;

    var manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_array = [];
    var manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_string = '';
    var manage_drone_imagery_autoencoder_keras_vi_drone_run_ids_training = [];
    var manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids_training = [];
    var manage_drone_imagery_autoencoder_keras_vi_field_trial_id_array = [];
    var manage_drone_imagery_autoencoder_keras_vi_field_trial_id_string = '';
    var manage_drone_imagery_autoencoder_keras_vi_drone_run_ids = [];
    var manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids = [];
    var manage_drone_imagery_autoencoder_keras_vi_time_cvterm_id = '';

    jQuery('#keras_cnn_drone_imagery_link').click(function(){
        jQuery('#drone_imagery_keras_cnn_dialog').modal('show');
    });

    jQuery('#drone_imagery_keras_cnn_train_link').click(function(){
        get_select_box('trials', 'drone_imagery_train_keras_cnn_trial_select_div', { 'name' : 'drone_imagery_train_keras_cnn_field_trial_id', 'id' : 'drone_imagery_train_keras_cnn_field_trial_id', 'empty':1, 'multiple':1 });

        jQuery('#drone_imagery_train_keras_cnn_dialog').modal('show');
    });

    jQuery('#drone_imagery_train_keras_model_field_trial_select_step').click(function(){
        manage_drone_imagery_train_keras_field_trial_id_array = [];
        manage_drone_imagery_train_keras_field_trial_id_string = '';
        manage_drone_imagery_train_keras_field_trial_id_array = jQuery('#drone_imagery_train_keras_cnn_field_trial_id').val();
        manage_drone_imagery_train_keras_field_trial_id_string = manage_drone_imagery_train_keras_field_trial_id_array.join(",");
        if (manage_drone_imagery_train_keras_field_trial_id_string == '') {
            alert('Please select a field trial first!');
        } else {
            get_select_box('traits', 'drone_imagery_train_keras_cnn_trait_select_div', { 'name' : 'drone_imagery_train_keras_cnn_trait_id', 'id' : 'drone_imagery_train_keras_cnn_trait_id', 'empty':1, 'trial_ids':manage_drone_imagery_train_keras_field_trial_id_string, 'stock_type':'plot' });

            get_select_box('traits', 'drone_imagery_train_keras_cnn_aux_trait_select_div', { 'name' : 'drone_imagery_train_keras_cnn_aux_trait_ids', 'id' : 'drone_imagery_train_keras_cnn_aux_trait_ids', 'empty':1, 'multiple':1, 'trial_ids':manage_drone_imagery_train_keras_field_trial_id_string, 'stock_type':'plot' });

            jQuery('#drone_image_train_keras_drone_runs_table').DataTable({
                paging : false,
                destroy : true,
                ajax : '/api/drone_imagery/drone_runs?select_checkbox_name=train_keras_drone_imagery_drone_run_select&checkbox_select_all=1&field_trial_ids='+manage_drone_imagery_train_keras_field_trial_id_string
            });

            Workflow.complete("#drone_imagery_train_keras_model_field_trial_select_step");
            Workflow.focus('#drone_imagery_train_keras_model_workflow', 2);
        }
        return false;
    });

    jQuery('#drone_imagery_train_keras_model_trait_select_step').click(function(){
        manage_drone_imagery_train_keras_trait_id = undefined;
        manage_drone_imagery_train_keras_aux_trait_ids = undefined;
        manage_drone_imagery_train_keras_trait_id = jQuery('#drone_imagery_train_keras_cnn_trait_id').val();
        manage_drone_imagery_train_keras_aux_trait_ids = jQuery('#drone_imagery_train_keras_cnn_aux_trait_ids').val();
        if (manage_drone_imagery_train_keras_trait_id == undefined || manage_drone_imagery_train_keras_trait_id == 'null' || manage_drone_imagery_train_keras_trait_id == '') {
            alert('Please select a phenotyped trait first!');
        } else {

            get_select_box('stocks', 'drone_imagery_train_keras_cnn_population_select_div', { 'name' : 'drone_imagery_train_keras_cnn_population_id', 'id' : 'drone_imagery_train_keras_cnn_population_id', 'empty':1, 'multiple':1, 'stock_type_name':'population' });

            Workflow.complete("#drone_imagery_train_keras_model_trait_select_step");
            Workflow.focus('#drone_imagery_train_keras_model_workflow', 3);
        }
        return false;
    });

    jQuery('#drone_imagery_train_keras_model_population_select_step').click(function(){
        Workflow.complete("#drone_imagery_train_keras_model_population_select_step");
        Workflow.focus('#drone_imagery_train_keras_model_workflow', 4);
    });

    jQuery('#drone_imagery_train_keras_model_drone_run_select_step').click(function(){
        manage_drone_imagery_train_keras_drone_run_ids = [];
        jQuery('input[name="train_keras_drone_imagery_drone_run_select"]:checked').each(function() {
            manage_drone_imagery_train_keras_drone_run_ids.push(jQuery(this).val());
        });
        if (manage_drone_imagery_train_keras_drone_run_ids.length < 1){
            alert('Please select at least one imaging event!');
        } else {

            jQuery('#drone_image_train_keras_plot_polygon_image_type_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/plot_polygon_types?checkbox_select_standard_4=1&select_checkbox_name=train_keras_drone_imagery_plot_polygon_type_select&field_trial_ids='+manage_drone_imagery_train_keras_field_trial_id_string+'&drone_run_ids='+JSON.stringify(manage_drone_imagery_train_keras_drone_run_ids)
            });

            Workflow.complete("#drone_imagery_train_keras_model_drone_run_select_step");
            Workflow.focus('#drone_imagery_train_keras_model_workflow', 5);
        }
        return false;
    });

    jQuery('#drone_image_train_keras_drone_runs_table_select_all').change(function(){
        jQuery('input[name="train_keras_drone_imagery_drone_run_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_train_keras_drone_runs_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_image_train_keras_plot_polygon_image_type_table_select_all').change(function() {
        jQuery('input[name="train_keras_drone_imagery_plot_polygon_type_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_train_keras_plot_polygon_image_type_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_imagery_train_keras_model_plot_polygon_type_select_step').click(function(){
        manage_drone_imagery_train_keras_plot_polygon_type_ids = [];
        jQuery('input[name="train_keras_drone_imagery_plot_polygon_type_select"]:checked').each(function() {
            manage_drone_imagery_train_keras_plot_polygon_type_ids.push(jQuery(this).val());
        });
        if (manage_drone_imagery_train_keras_plot_polygon_type_ids.length < 1){
            alert('Please select at least one plot polygon type!');
        } else {
            Workflow.complete("#drone_imagery_train_keras_model_plot_polygon_type_select_step");
            Workflow.focus('#drone_imagery_train_keras_model_workflow', 6);
        }

        get_select_box('genotyping_protocol', 'drone_image_train_keras_model_genotyping_protocol_div', { 'name' : 'drone_image_train_keras_model_genotyping_protocol_select', 'id' : 'drone_image_train_keras_model_genotyping_protocol_select', 'empty':1 });

        return false;
    });

    jQuery('#drone_imagery_train_keras_model_confirm_step').click(function(){
        manage_drone_imagery_train_keras_temporary_model_file = '';
        manage_drone_imagery_train_keras_temporary_model_input_file = '';
        manage_drone_imagery_train_keras_temporary_model_input_aux_file = '';
        manage_drone_imagery_train_keras_class_map = '';

        var drone_imagery_keras_model_name = jQuery('#drone_image_train_keras_model_name').val();
        var drone_imagery_keras_model_desc = jQuery('#drone_image_train_keras_model_desc').val();
        var drone_imagery_keras_model_type = jQuery('#drone_image_train_keras_model_type').val();
        if (drone_imagery_keras_model_type =='' || drone_imagery_keras_model_name == '' || drone_imagery_keras_model_desc == '') {
            alert('Please give a model type, name, and description!');
            return false;
        }
        else if (manage_drone_imagery_train_keras_plot_polygon_type_ids.length / manage_drone_imagery_train_keras_drone_run_ids.length != 4) {
            alert('This only works for Micasense 5-band camera currently, where plot images are extracted for blue, green, red, NIR, and red-edge bands, and the standard process has been completed! So only select imaging events that meet this criteria!');
            return false;
        }
        else {
            jQuery.ajax({
                url : '/api/drone_imagery/train_keras_model',
                type: "POST",
                data : {
                    'field_trial_ids' : manage_drone_imagery_train_keras_field_trial_id_string,
                    'trait_id' : manage_drone_imagery_train_keras_trait_id,
                    'aux_trait_id' : manage_drone_imagery_train_keras_aux_trait_ids,
                    'drone_run_ids' : JSON.stringify(manage_drone_imagery_train_keras_drone_run_ids),
                    'plot_polygon_type_ids' : JSON.stringify(manage_drone_imagery_train_keras_plot_polygon_type_ids),
                    'save_model' : 1,
                    'model_name' : drone_imagery_keras_model_name,
                    'model_description' : drone_imagery_keras_model_desc,
                    'model_type' : drone_imagery_keras_model_type,
                    'population_id' : jQuery('#drone_imagery_train_keras_cnn_population_id').val(),
                    'nd_protocol_id' : jQuery('#drone_image_train_keras_model_genotyping_protocol_select').val(),
                    'use_parents_grm' : jQuery('#drone_image_train_keras_model_use_parents_grm').val()
                },
                beforeSend: function() {
                    jQuery("#working_modal").modal("show");
                },
                success: function(response){
                    console.log(response);
                    jQuery("#working_modal").modal("hide");

                    if (response.error) {
                        alert(response.error);
                    }
                    else {
                        alert("Trained Keras CNN Model saved!");
                    }

                    var html = "<hr><a href='"+response.loss_history_file+"' target=_blank>Loss History</a><hr><h4>Results</h4><br/><br/>";
                    html = html + "<table class='table table-bordered table-hover'><thead><tr><th>Results</th></tr></thead><tbody>";
                    for (var i=0; i<response.results.length; i++) {
                        html = html + "<tr><td>"+response.results[i]+"</td></tr>";
                    }
                    html = html + "</tbody></table>";

                    //html = html + '<hr><h3>Save Model for Predictions</h3><div class="form-horizontal"><div class="form-group"><label class="col-sm-6 control-label">Model Name: </label><div class="col-sm-6"><input class="form-control" id="drone_imagery_save_keras_model_name" name="drone_imagery_save_keras_model_name" type="text" /></div></div><div class="form-group"><label class="col-sm-6 control-label">Model Description: </label><div class="col-sm-6"><input class="form-control" id="drone_imagery_save_keras_model_desc" name="drone_imagery_save_keras_model_desc" type="text" /></div></div></div><button class="btn btn-primary" id="drone_imagery_keras_model_save">Save Model (Required For Using For Prediction)</button>';

                    manage_drone_imagery_train_keras_temporary_model_input_file = response.model_input_file;
                    manage_drone_imagery_train_keras_temporary_model_input_aux_file = response.model_input_aux_file;
                    manage_drone_imagery_train_keras_temporary_model_file = response.model_temp_file;
                    manage_drone_imagery_train_keras_class_map = response.class_map;

                    jQuery('#drone_imagery_train_keras_model_results_div').html(html);
                },
                error: function(response){
                    jQuery("#working_modal").modal("hide");
                    alert('Error training keras model!')
                }
            });
        }
    });

    jQuery(document).on('click', '#drone_imagery_keras_model_save', function() {
        var manage_drone_imagery_train_keras_model_save_name = jQuery('#drone_imagery_save_keras_model_name').val();
        var manage_drone_imagery_train_keras_model_save_desc = jQuery('#drone_imagery_save_keras_model_desc').val();
        if (manage_drone_imagery_train_keras_model_save_name == '' || manage_drone_imagery_train_keras_model_save_desc == '') {
            alert('A model name and description are required for saving!');
            return false;
        }
        else {
            jQuery.ajax({
                url : '/api/drone_imagery/save_keras_model?field_trial_ids='+manage_drone_imagery_train_keras_field_trial_id_string+'&drone_run_ids='+JSON.stringify(manage_drone_imagery_train_keras_drone_run_ids)+'&plot_polygon_type_ids='+JSON.stringify(manage_drone_imagery_train_keras_plot_polygon_type_ids)+'&model_file='+manage_drone_imagery_train_keras_temporary_model_file+'&model_input_file='+manage_drone_imagery_train_keras_temporary_model_input_file+'&model_input_aux_file='+manage_dromanage_drone_imagery_train_keras_temporary_model_input_aux_file+'&model_name='+manage_drone_imagery_train_keras_model_save_name+'&model_description='+manage_drone_imagery_train_keras_model_save_desc+'&class_map='+JSON.stringify(manage_drone_imagery_train_keras_class_map)+'&trait_id='+manage_drone_imagery_train_keras_trait_id,
                beforeSend: function() {
                    jQuery("#working_modal").modal("show");
                },
                success: function(response){
                    console.log(response);
                    jQuery("#working_modal").modal("hide");
                    if (response.error) {
                        alert(response.error);
                    }
                    else {
                        alert('Trained Keras CNN Model Saved! You can now use it for prediction!');
                    }
                },
                error: function(response){
                    jQuery("#working_modal").modal("hide");
                    alert('Error saving keras model!')
                }
            });
        }
    });

    jQuery('#drone_imagery_keras_cnn_predict_link').click(function(){
        get_select_box('trials', 'drone_imagery_predict_keras_cnn_trial_select_div', { 'name' : 'drone_imagery_predict_keras_cnn_field_trial_id', 'id' : 'drone_imagery_predict_keras_cnn_field_trial_id', 'empty':1, 'multiple':0 });
        get_select_box('trained_keras_cnn_models', 'drone_imagery_predict_keras_cnn_model_select_div', { 'name' : 'drone_imagery_predict_keras_cnn_model_id', 'id' : 'drone_imagery_predict_keras_cnn_model_id', 'empty':1 });

        jQuery('#drone_imagery_predict_keras_cnn_dialog').modal('show');
    });

    jQuery('#drone_imagery_predict_keras_model_field_trial_select_step').click(function(){
        manage_drone_imagery_predict_keras_field_trial_id_array = [];
        manage_drone_imagery_predict_keras_field_trial_id_string = '';
        manage_drone_imagery_predict_keras_field_trial_id_string = jQuery('#drone_imagery_predict_keras_cnn_field_trial_id').val();
        //manage_drone_imagery_predict_keras_field_trial_id_array = jQuery('#drone_imagery_predict_keras_cnn_field_trial_id').val();
        //manage_drone_imagery_predict_keras_field_trial_id_string = manage_drone_imagery_predict_keras_field_trial_id_array.join(",");
        if (manage_drone_imagery_predict_keras_field_trial_id_string == '') {
            alert('Please select a field trial first!');
        } else {

            jQuery('#drone_image_predict_keras_drone_runs_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/drone_runs?select_checkbox_name=predict_keras_drone_imagery_drone_run_select&checkbox_select_all=1&field_trial_ids='+manage_drone_imagery_predict_keras_field_trial_id_string
            });

            get_select_box('traits', 'drone_imagery_predict_keras_cnn_aux_trait_select_div', { 'name' : 'drone_imagery_predict_keras_cnn_aux_trait_ids', 'id' : 'drone_imagery_predict_keras_cnn_aux_trait_ids', 'empty':1, 'multiple':1, 'trial_ids':manage_drone_imagery_predict_keras_field_trial_id_string, 'stock_type':'plot' });

            Workflow.complete("#drone_imagery_predict_keras_model_field_trial_select_step");
            Workflow.focus('#drone_imagery_predict_keras_model_workflow', 2);
        }
        return false;
    });

    jQuery('#drone_image_predict_keras_drone_runs_table_select_all').change(function(){
        jQuery('input[name="predict_keras_drone_imagery_drone_run_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_predict_keras_drone_runs_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_imagery_predict_keras_model_select_step').click(function(){
        manage_drone_imagery_predict_keras_model_id = '';
        manage_drone_imagery_predict_keras_aux_trait_ids = undefined;
        manage_drone_imagery_predict_keras_model_id = jQuery('#drone_imagery_predict_keras_cnn_model_id').val();
        manage_drone_imagery_predict_keras_aux_trait_ids = jQuery('#drone_imagery_predict_keras_cnn_aux_trait_ids').val();
        if (manage_drone_imagery_predict_keras_model_id == '') {
            alert('Please select a trained Keras CNN model before proceeding!');
        }
        else {
            get_select_box('stocks', 'drone_imagery_predict_keras_cnn_population_select_div', { 'name' : 'drone_imagery_predict_keras_cnn_population_id', 'id' : 'drone_imagery_predict_keras_cnn_population_id', 'empty':1, 'multiple':1, 'stock_type_name':'population' });

            Workflow.complete("#drone_imagery_predict_keras_model_select_step");
            Workflow.focus('#drone_imagery_predict_keras_model_workflow', 3);
        }
        return false;
    });

    jQuery('#drone_imagery_predict_keras_model_population_select_step').click(function(){
        Workflow.complete("#drone_imagery_predict_keras_model_population_select_step");
        Workflow.focus('#drone_imagery_predict_keras_model_workflow', 4);
    });

    jQuery('#drone_imagery_predict_keras_model_drone_run_select_step').click(function(){
        manage_drone_imagery_predict_keras_drone_run_ids = [];
        jQuery('input[name="predict_keras_drone_imagery_drone_run_select"]:checked').each(function() {
            manage_drone_imagery_predict_keras_drone_run_ids.push(jQuery(this).val());
        });
        if (manage_drone_imagery_predict_keras_drone_run_ids.length < 1){
            alert('Please select at least one imaging event!');
        } else {

            jQuery('#drone_image_predict_keras_plot_polygon_image_type_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/plot_polygon_types?checkbox_select_standard_4=1&select_checkbox_name=predict_keras_drone_imagery_plot_polygon_type_select&field_trial_ids='+manage_drone_imagery_predict_keras_field_trial_id_string+'&drone_run_ids='+JSON.stringify(manage_drone_imagery_predict_keras_drone_run_ids)
            });

            Workflow.complete("#drone_imagery_predict_keras_model_drone_run_select_step");
            Workflow.focus('#drone_imagery_predict_keras_model_workflow', 5);
        }
        return false;
    });

    jQuery('#drone_image_predict_keras_plot_polygon_image_type_table_select_all').change(function() {
        jQuery('input[name="predict_keras_drone_imagery_plot_polygon_type_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_predict_keras_plot_polygon_image_type_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_imagery_predict_keras_model_plot_polygon_type_select_step').click(function(){
        manage_drone_imagery_predict_keras_plot_polygon_type_ids = [];
        jQuery('input[name="predict_keras_drone_imagery_plot_polygon_type_select"]:checked').each(function() {
            manage_drone_imagery_predict_keras_plot_polygon_type_ids.push(jQuery(this).val());
        });
        if (manage_drone_imagery_predict_keras_plot_polygon_type_ids.length < 1){
            alert('Please select at least one plot polygon type!');
        } else {
            Workflow.complete("#drone_imagery_predict_keras_model_plot_polygon_type_select_step");
            Workflow.focus('#drone_imagery_predict_keras_model_workflow', 6);
        }
        return false;
    });

    jQuery('#drone_imagery_keras_model_prediction_select').change(function(){
        if (jQuery(this).val() == 'cnn_prediction_mixed_model') {
            jQuery('#drone_imagery_keras_model_prediction_cnn_prediction_mixed_model_div').show();
        }
        else {
            jQuery('#drone_imagery_keras_model_prediction_cnn_prediction_mixed_model_div').hide();
        }
    });

    jQuery('#drone_imagery_predict_keras_model_confirm_step').click(function(){
        jQuery.ajax({
            url : '/api/drone_imagery/predict_keras_model',
            type: "POST",
            data: {
                'field_trial_ids' : manage_drone_imagery_predict_keras_field_trial_id_string,
                'drone_run_ids' : JSON.stringify(manage_drone_imagery_predict_keras_drone_run_ids),
                'plot_polygon_type_ids' : JSON.stringify(manage_drone_imagery_predict_keras_plot_polygon_type_ids),
                'model_id' : manage_drone_imagery_predict_keras_model_id,
                'model_prediction_type' : jQuery('#drone_imagery_keras_model_prediction_select').val(),
                'population_id' : jQuery('#drone_imagery_predict_keras_cnn_population_id').val(),
                'aux_trait_ids' : manage_drone_imagery_predict_keras_aux_trait_ids
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");
                if (response.error) {
                    alert(response.error);
                }

                var html = "<hr><h4>Prediction Results: "+response.trained_trait_name+"</h4>";
                html = html + "<table class='table table-bordered table-hover'><thead><tr><th>Stock</th><th>Prediction</th><th>True Phenotype Value</th></tr></thead><tbody>";
                for (var i=0; i<response.results.length; i++) {
                    html = html + "<tr><td><a href='/stock/"+response.results[i][1]+"/view' target=_blank>"+response.results[i][0]+"</a></td><td>"+response.results[i][2]+"</td><td>"+response.results[i][3]+"</td></tr>";
                }
                html = html + "</tbody></table>";

                html = html + "<a href='"+response.activation_output+"' target=_blank>Download Activation Result</a><a href='"+response.corr_plot+"' target=_blank>Download Correlation</a>";

                if (response.evaluation_results.length > 0) {
                    html = html + "<hr><h4>Model Evaluation Results</h4><br/><br/>";
                    html = html + "<table class='table table-bordered table-hover'><thead><tr><th>Results</th></tr></thead><tbody>";
                    for (var i=0; i<response.evaluation_results.length; i++) {
                        html = html + "<tr><td>"+response.evaluation_results[i]+"</td></tr>";
                    }
                    html = html + "</tbody></table>";
                }

                jQuery('#drone_imagery_predict_keras_model_results_div').html(html);
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error predicting keras model!')
            }
        });
    });

    jQuery('#drone_imagery_keras_cnn_autoencoder_vegetation_indices_link').click(function(){
        get_select_box('trials', 'drone_imagery_autoencoder_keras_cnn_vi_trial_training_select_div', { 'name' : 'drone_imagery_autoencoder_keras_cnn_vi_field_trial_id_training', 'id' : 'drone_imagery_autoencoder_keras_cnn_vi_field_trial_id_training', 'empty':1, 'multiple':1 });
        get_select_box('trials', 'drone_imagery_autoencoder_keras_cnn_vi_trial_select_div', { 'name' : 'drone_imagery_autoencoder_keras_cnn_vi_field_trial_id', 'id' : 'drone_imagery_autoencoder_keras_cnn_vi_field_trial_id', 'empty':1, 'multiple':0 });

        jQuery('#drone_imagery_keras_cnn_autoencoder_vi_dialog').modal('show');
    });

    jQuery('#drone_imagery_autoencoder_keras_vi_model_field_trial_training_select_step').click(function(){
        manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_array = jQuery('#drone_imagery_autoencoder_keras_cnn_vi_field_trial_id_training').val();
        manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_string = manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_array.join();

        if (manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_array.length < 1) {
            alert('Please select atleast one field trial!');
        }
        else if (manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_string == '') {
            alert('Please select a field trial first!');
        }
        else {

            jQuery('#drone_image_autoencoder_keras_vi_drone_runs_training_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/drone_runs?select_checkbox_name=autoencoder_keras_drone_imagery_drone_run_training_select&checkbox_select_all=1&field_trial_ids='+manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_string
            });

            Workflow.complete("#drone_imagery_autoencoder_keras_vi_model_field_trial_training_select_step");
            Workflow.focus('#drone_imagery_autoencoder_keras_model_vi_workflow', 2);
        }
        return false;
    });

    jQuery('#drone_image_autoencoder_keras_vi_drone_runs_training_table_select_all').change(function(){
        jQuery('input[name="autoencoder_keras_drone_imagery_drone_run_training_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_autoencoder_keras_vi_drone_runs_training_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_imagery_autoencoder_keras_vi_model_drone_run_training_select_step').click(function(){
        manage_drone_imagery_autoencoder_keras_vi_drone_run_ids_training = [];
        jQuery('input[name="autoencoder_keras_drone_imagery_drone_run_training_select"]:checked').each(function() {
            manage_drone_imagery_autoencoder_keras_vi_drone_run_ids_training.push(jQuery(this).val());
        });
        if (manage_drone_imagery_autoencoder_keras_vi_drone_run_ids_training.length < 1){
            alert('Please select atleast one imaging event!');
        } else {

            jQuery('#drone_image_autoencoder_keras_vi_plot_polygon_image_type_training_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/plot_polygon_types?checkbox_select_standard_ndvi_ndre=1&select_checkbox_name=autoencoder_keras_vi_drone_imagery_plot_polygon_type_training_select&field_trial_ids='+manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_string+'&drone_run_ids='+JSON.stringify(manage_drone_imagery_autoencoder_keras_vi_drone_run_ids_training)
            });

            Workflow.complete("#drone_imagery_autoencoder_keras_vi_model_drone_run_training_select_step");
            Workflow.focus('#drone_imagery_autoencoder_keras_model_vi_workflow', 3);
        }
        return false;
    });

    jQuery('#drone_image_autoencoder_keras_vi_plot_polygon_image_type_training_table_select_all').change(function() {
        jQuery('input[name="autoencoder_keras_vi_drone_imagery_plot_polygon_type_training_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_autoencoder_keras_vi_plot_polygon_image_type_training_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_imagery_autoencoder_keras_vi_model_plot_polygon_type_training_select_step').click(function(){
        manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids_training = [];
        jQuery('input[name="autoencoder_keras_vi_drone_imagery_plot_polygon_type_training_select"]:checked').each(function() {
            manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids_training.push(jQuery(this).val());
        });
        if (manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids_training.length < 1){
            alert('Please select at least one plot polygon type!');
        } else {
            Workflow.complete("#drone_imagery_autoencoder_keras_vi_model_plot_polygon_type_training_select_step");
            Workflow.focus('#drone_imagery_autoencoder_keras_model_vi_workflow', 4);
        }
        return false;
    });

    jQuery('#drone_imagery_autoencoder_keras_vi_model_field_trial_select_step').click(function(){
        manage_drone_imagery_autoencoder_keras_vi_field_trial_id_array = [];
        manage_drone_imagery_autoencoder_keras_vi_field_trial_id_string = '';
        manage_drone_imagery_autoencoder_keras_vi_field_trial_id_string = jQuery('#drone_imagery_autoencoder_keras_cnn_vi_field_trial_id').val();

        if (manage_drone_imagery_autoencoder_keras_vi_field_trial_id_string == '') {
            alert('Please select a field trial first!');
        } else {

            jQuery('#drone_image_autoencoder_keras_vi_drone_runs_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/drone_runs?select_checkbox_name=autoencoder_keras_drone_imagery_drone_run_select&checkbox_select_all=1&field_trial_ids='+manage_drone_imagery_autoencoder_keras_vi_field_trial_id_string
            });

            Workflow.complete("#drone_imagery_autoencoder_keras_vi_model_field_trial_select_step");
            Workflow.focus('#drone_imagery_autoencoder_keras_model_vi_workflow', 5);
        }
        return false;
    });

    jQuery('#drone_image_autoencoder_keras_vi_drone_runs_table_select_all').change(function(){
        jQuery('input[name="autoencoder_keras_drone_imagery_drone_run_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_autoencoder_keras_vi_drone_runs_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_imagery_autoencoder_keras_vi_model_drone_run_select_step').click(function(){
        manage_drone_imagery_autoencoder_keras_vi_drone_run_ids = [];
        jQuery('input[name="autoencoder_keras_drone_imagery_drone_run_select"]:checked').each(function() {
            manage_drone_imagery_autoencoder_keras_vi_drone_run_ids.push(jQuery(this).val());
        });
        if (manage_drone_imagery_autoencoder_keras_vi_drone_run_ids.length < 1){
            alert('Please select one imaging event!');
        } else if (manage_drone_imagery_autoencoder_keras_vi_drone_run_ids.length > 1){
            alert('Please select only one imaging event!');
        } else {

            jQuery.ajax({
                type: 'GET',
                url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_autoencoder_keras_vi_drone_run_ids[0],
                dataType: "json",
                beforeSend: function (){
                    jQuery('#working_modal').modal('show');
                },
                success: function(response){
                    jQuery('#working_modal').modal('hide');
                    console.log(response);
                    if (response.error) {
                        alert(response.error);
                    }

                    manage_drone_imagery_autoencoder_keras_vi_time_cvterm_id = response.time_ontology_day_cvterm_id;
                },
                error: function(response){
                    alert('Error getting time term!');
                    jQuery('#working_modal').modal('hide');
                }
            });

            jQuery('#drone_image_autoencoder_keras_vi_plot_polygon_image_type_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/plot_polygon_types?checkbox_select_standard_ndvi_ndre=1&select_checkbox_name=autoencoder_keras_vi_drone_imagery_plot_polygon_type_select&field_trial_ids='+manage_drone_imagery_autoencoder_keras_vi_field_trial_id_string+'&drone_run_ids='+JSON.stringify(manage_drone_imagery_autoencoder_keras_vi_drone_run_ids)
            });

            Workflow.complete("#drone_imagery_autoencoder_keras_vi_model_drone_run_select_step");
            Workflow.focus('#drone_imagery_autoencoder_keras_model_vi_workflow', 6);
        }
        return false;
    });

    jQuery('#drone_image_autoencoder_keras_vi_plot_polygon_image_type_table_select_all').change(function() {
        jQuery('input[name="autoencoder_keras_vi_drone_imagery_plot_polygon_type_select"]').each(function() {
            jQuery(this).prop('checked', jQuery('#drone_image_autoencoder_keras_vi_plot_polygon_image_type_table_select_all').prop("checked"));
        });
    });

    jQuery('#drone_imagery_autoencoder_keras_vi_model_plot_polygon_type_select_step').click(function(){
        manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids = [];
        jQuery('input[name="autoencoder_keras_vi_drone_imagery_plot_polygon_type_select"]:checked').each(function() {
            manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids.push(jQuery(this).val());
        });
        if (manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids.length < 1){
            alert('Please select at least one plot polygon type!');
        } else {
            Workflow.complete("#drone_imagery_autoencoder_keras_vi_model_plot_polygon_type_select_step");
            Workflow.focus('#drone_imagery_autoencoder_keras_model_vi_workflow', 7);
        }
        return false;
    });

    jQuery('#drone_imagery_autoencoder_keras_vi_model_confirm_step').click(function(){
        jQuery.ajax({
            url : '/api/drone_imagery/perform_autoencoder_vi',
            type: "POST",
            data: {
                'training_field_trial_ids' : manage_drone_imagery_autoencoder_keras_vi_field_trial_id_training_string,
                'training_drone_run_ids' : JSON.stringify(manage_drone_imagery_autoencoder_keras_vi_drone_run_ids_training),
                'training_plot_polygon_type_ids' : JSON.stringify(manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids_training),
                'field_trial_ids' : manage_drone_imagery_autoencoder_keras_vi_field_trial_id_string,
                'drone_run_ids' : JSON.stringify(manage_drone_imagery_autoencoder_keras_vi_drone_run_ids),
                'plot_polygon_type_ids' : JSON.stringify(manage_drone_imagery_autoencoder_keras_vi_plot_polygon_type_ids),
                'autoencoder_model_type' : jQuery('#drone_imagery_keras_model_autoencoder_vi_select').val(),
                'time_cvterm_id' : manage_drone_imagery_autoencoder_keras_vi_time_cvterm_id
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");
                if (response.error) {
                    alert(response.error);
                }
                else {
                    alert('Autoencoder phenotypes saved!');
                }
                var html = '';
                jQuery('#drone_imagery_autoencoder_keras_vi_model_results_div').html(html);
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error autoencoder keras CNN VI!')
            }
        });
    });

    //
    // Image Rotating JS
    //

    var manage_drone_imagery_standard_process_rotate_svg;

    function showRotateImageD3(rotate_stitched_image_id, canvas_div_id, load_div_id) {
        jQuery.ajax({
            url : '/api/drone_imagery/get_image?image_id='+rotate_stitched_image_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                manage_drone_imagery_standard_process_image_width = response.image_width;
                manage_drone_imagery_standard_process_image_height = response.image_height;

                manage_drone_imagery_standard_process_rotate_svg = d3.select(canvas_div_id).append("svg")
                    .attr("width", manage_drone_imagery_standard_process_image_width)
                    .attr("height", manage_drone_imagery_standard_process_image_height)
                    .attr("id", canvas_div_id+'_area')
                    .on("click", function(){
                        console.log(d3.mouse(this));
                    });
                var x_pos = 0;
                var y_pos = 0;
                var imageGroup = manage_drone_imagery_standard_process_rotate_svg.append("g")
                    .datum({position: x_pos,y_pos})
                    .attr("x_pos", x_pos)
                    .attr("y_pos", y_pos)
                    .attr("transform", d => "translate("+x_pos+","+y_pos+")");

                var imageElem = imageGroup.append("image")
                    .attr("xlink:href", response.image_url)
                    .attr("height", manage_drone_imagery_standard_process_image_height)
                    .attr("width", manage_drone_imagery_standard_process_image_width);

                jQuery('#'+load_div_id).hide();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving image!')
            }
        });
    }

    function getRandomColor() {
        var letters = '0123456789ABCDEF';
        var color = '#';
        for (var i = 0; i < 6; i++) {
            color += letters[Math.floor(Math.random() * 16)];
        }
        return color;
    }

    function drawRotateCrosshairsD3(color) {
        var row_line_width = 250;
        var col_line_width = 250;
        var number_col_lines = manage_drone_imagery_standard_process_image_width/col_line_width;
        var number_row_lines = manage_drone_imagery_standard_process_image_height/row_line_width;
        var current_row_val = row_line_width;
        var current_col_val = col_line_width;
        for (var i=0; i<number_col_lines; i++) {
            manage_drone_imagery_standard_process_rotate_svg.append('line')
                .style("stroke", color)
                .style("stroke-width", 5)
                .attr("x1", current_col_val)
                .attr("y1", 0)
                .attr("x2", current_col_val)
                .attr("y2", manage_drone_imagery_standard_process_image_height);
            current_col_val = current_col_val + col_line_width;
        }
        for (var i=0; i<number_col_lines; i++) {
            manage_drone_imagery_standard_process_rotate_svg.append('line')
                .style("stroke", color)
                .style("stroke-width", 5)
                .attr("x1", 0)
                .attr("y1", current_row_val)
                .attr("x2", manage_drone_imagery_standard_process_image_width)
                .attr("y2", current_row_val);
            current_row_val = current_row_val + row_line_width;
        }
    }

    //
    // Image Cropping JS
    //

    var trial_id;
    var stitched_image_id;
    var rotated_stitched_image_id;
    var stitched_image;
    var drone_run_project_id;
    var drone_run_band_project_id;
    var crop_points = [];
    var crop_display_points = [];
    var dronecroppingImg;

    function showCropImageStart(rotated_stitched_image_id, canvas_div_id, load_div_id) {
        crop_points = [];
        crop_display_points = [];
        jQuery.ajax({
            url : '/api/drone_imagery/get_image?image_id='+rotated_stitched_image_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                var canvas = document.getElementById(canvas_div_id);
                ctx = canvas.getContext('2d');
                var image = new Image();
                image.onload = function () {
                    canvas.width = this.naturalWidth;
                    canvas.height = this.naturalHeight;
                    ctx.drawImage(this, 0, 0);
                    jQuery('#'+load_div_id).hide();
                };
                image.src = response.image_url;
                dronecroppingImg = canvas;
                dronecroppingImg.onmousedown = GetCoordinatesCroppedImage;
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving image!')
            }
        });
    }

    function FindPosition(oElement) {
        if(typeof( oElement.offsetParent ) != "undefined") {
            for(var posX = 0, posY = 0; oElement; oElement = oElement.offsetParent) {
                posX += oElement.offsetLeft;
                posY += oElement.offsetTop;
            }
            return [ posX, posY ];
        } else {
            return [ oElement.x, oElement.y ];
        }
    }

    function GetCoordinatesCroppedImage(e) {
        var PosX = 0;
        var PosY = 0;
        var ImgPos;
        ImgPos = FindPosition(dronecroppingImg);
        if (!e) var e = window.event;
        if (e.pageX || e.pageY) {
            PosX = e.pageX;
            PosY = e.pageY;
        }
        else if (e.clientX || e.clientY) {
            PosX = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
            PosY = e.clientY + document.body.scrollTop + document.documentElement.scrollTop;
        }
        PosX = PosX - ImgPos[0];
        PosY = PosY - ImgPos[1];

        if (drone_imagery_standard_process_plot_polygon_click_type == 'standard_process_raw_images_paste_polygon') {
            plotPolygonsTemplatePasteRawImage(PosX, PosY, manage_drone_imagery_standard_process_raw_images_polygon);
            drone_imagery_standard_process_plot_polygon_click_type = '';
        }
        else if (drone_imagery_standard_process_plot_polygon_click_type == 'standard_process_raw_images_paste_previous_polygon') {
            manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new = {};
            var manage_drone_imagery_standard_process_raw_images_previous_polygon_template = JSON.parse(decodeURI(manage_drone_imagery_standard_process_raw_images_previous_polygon));

            manage_drone_imagery_standard_process_raw_images_previous_polygon = [];
            for (var index in manage_drone_imagery_standard_process_raw_images_previous_polygon_template) {
                if (manage_drone_imagery_standard_process_raw_images_previous_polygon_template.hasOwnProperty(index)) {
                    manage_drone_imagery_standard_process_raw_images_previous_polygon.push(manage_drone_imagery_standard_process_raw_images_previous_polygon_template[index]);
                }
            }
            console.log(manage_drone_imagery_standard_process_raw_images_previous_polygon);

            var PosX_shift = manage_drone_imagery_standard_process_raw_images_previous_polygon[0][0]['x']-PosX;
            var PosY_shift = manage_drone_imagery_standard_process_raw_images_previous_polygon[0][0]['y']-PosY;

            for (var i=0; i<manage_drone_imagery_standard_process_raw_images_previous_polygon.length; i++) {
                plot_polygons_ind_4_points = manage_drone_imagery_standard_process_raw_images_previous_polygon[i];
                plot_polygons_display_points = plot_polygons_ind_4_points;
                if (plot_polygons_display_points.length == 4) {
                    plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
                }
                console.log(plot_polygons_display_points);
                var plot_polygons_display_points_shifted = [];
                for (var j=0; j<plot_polygons_display_points.length; j++) {
                    plot_polygons_display_points_shifted.push({'x':plot_polygons_display_points[j]['x']-PosX_shift, 'y':plot_polygons_display_points[j]['y']-PosY_shift});
                }
                plot_polygons_display_points = plot_polygons_display_points_shifted;
                drawPolyline(plot_polygons_display_points);
                drawWaypoints(plot_polygons_display_points, i, 0);
                drone_imagery_plot_generated_polygons[i] = plot_polygons_display_points;
                manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new[i] = plot_polygons_display_points;
                drone_imagery_plot_polygons_display[i] = plot_polygons_display_points;
            }

            crop_points = manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new;

            var table_html = '<table class="table table-bordered table-hover"><thead><tr><th>Generated Index</th><th>Plot Number</th></tr></thead><tbody>';
            for (var gen_index in manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new) {
                if (manage_drone_imagery_standard_process_raw_images_drone_imagery_plot_polygons_new.hasOwnProperty(gen_index)) {
                    table_html = table_html + '<tr><td>'+gen_index+'</td><td><input type="text" class="form-control" placeholder="e.g. 1001" name="manage_drone_imagery_standard_process_raw_images_given_plot_number" data-generated_index="'+gen_index+'"></td></tr>';
                }
            }
            table_html = table_html + '</tbody></table>';

            jQuery('#drone_imagery_standard_process_raw_images_polygon_assign_table').html(table_html);

            drone_imagery_standard_process_plot_polygon_click_type = '';
        }
        else {
            if (crop_points.length < 4){
                crop_points.push({x:PosX, y:PosY});
                crop_display_points.push({x:PosX, y:PosY});
            } else {
                crop_display_points.push({x:PosX, y:PosY});
                console.log(crop_points);
            }
            if (crop_display_points.length > 5){
                crop_points = [];
                crop_display_points = [];
            }
            drawPolyline(crop_display_points);
            drawWaypoints(crop_display_points, undefined, 0);
        }
    }

    function drawPolyline(points){
        if (points.length == 4) {
            points.push(points[0]);
        }
        for(var i=0;i<points.length;i++){
            ctx.beginPath();
            ctx.moveTo(points[0].x,points[0].y);
            for(var i=1;i<points.length;i++){
                ctx.lineTo(points[i].x,points[i].y);
            }
            ctx.strokeStyle='blue';
            ctx.lineWidth=5;
            ctx.stroke();
        }
    }

    function drawWaypoints(points, label, random_factor){
        var plot_polygon_random_number = Math.random() * random_factor;
        if (points.length > 0 && label != undefined) {
            if (drone_imagery_plot_polygons_removed_numbers.includes(label)) {
                ctx.font = "bold 18px Arial";
                ctx.fillStyle = 'blue';
                ctx.fillText('NA', points[0].x + 3, points[0].y + 14 + plot_polygon_random_number);
            } else {
                ctx.font = "bold 18px Arial";
                ctx.fillStyle = 'red';
                ctx.fillText(label, parseInt(points[0].x) + 3, parseInt(points[0].y) + 14 + plot_polygon_random_number);
                //ctx.fillText(label.toString().substring(label.length - 3), points[0].x + 3, points[0].y + 14 + plot_polygon_random_number);
            }
        }
        for(var i=0;i<points.length;i++){
            ctx.beginPath();
            ctx.arc(points[i].x,points[i].y,4,0,Math.PI*2);
            ctx.closePath();
            ctx.strokeStyle='black';
            ctx.lineWidth=1;
            ctx.stroke();
            ctx.fillStyle='white';
            ctx.fill();
        }
    }

    function drawWaypointsSVG(svg_div_id, points, clear_markings){
        console.log(points);
        if (clear_markings) {
            d3.selectAll("path").remove();
            d3.selectAll("text").remove();
            d3.selectAll("circle").remove();
            d3.selectAll("rect").remove();
        }

        var svg = d3.select('#'+svg_div_id).select("svg");
        focus = svg.append("g");

        for (var i=0; i<points.length; i++) {
            focus.append("text")
                .attr("x", points[i]['x_pos']-12)
                .attr("y", points[i]['y_pos']-12)
                .style('fill', 'red')
                .style("font-size", "28px")
                .style("font-weight", 600)
                .text(points[i]['name']);
        }

        focus.selectAll('circle')
            .data(points)
            .enter()
            .append('circle')
            .attr('r', 10.0)
            .attr('cx', function(d) { return d['x_pos'];  })
            .attr('cy', function(d) { return d['y_pos']; })
            .style('cursor', 'pointer')
            .style('fill', 'red');
    }

    //
    //Define Plot Polygons JS
    //

    var canvas;
    var background_image_url;
    var background_image_width;
    var background_image_height;
    var plot_polygons_display_points = [];
    var plot_polygons_ind_points = [];
    var plot_polygons_ind_4_points = [];
    var drone_imagery_plot_polygons = {};
    var drone_imagery_plot_polygons_plot_names = {};
    var drone_imagery_plot_generated_polygons = {};
    var drone_imagery_plot_polygons_display = {};
    var plot_polygons_plot_names_colors = {};
    var plot_polygons_plot_names_plot_numbers = {};
    var plot_polygons_generated_polygons = [];
    var drone_imagery_plot_polygons_removed_numbers = [];
    var field_trial_layout_response = {};
    var field_trial_layout_responses = {};
    var field_trial_layout_response_names = [];
    var plot_polygon_name;
    var plotpolygonsImg;
    var drone_imagery_plot_polygons_available_stock_names = [];
    var trial_id;
    var cropped_stitched_image_id;
    var denoised_stitched_image_id;
    var background_removed_stitched_image_id;
    var drone_run_project_id;
    var drone_run_project_name;
    var drone_run_band_project_id;
    var assign_plot_polygons_type;
    var focus;

    jQuery(document).on('click', 'button[name="project_drone_imagery_plot_polygons"]', function(){
        trial_id = jQuery(this).data('field_trial_id');
        cropped_stitched_image_id = jQuery(this).data('cropped_stitched_image_id');
        denoised_stitched_image_id = jQuery(this).data('denoised_stitched_image_id');
        background_removed_stitched_image_id = jQuery(this).data('background_removed_stitched_image_id');
        drone_run_project_id = jQuery(this).data('drone_run_project_id');
        drone_run_project_name = jQuery(this).data('drone_run_project_name');
        drone_run_band_project_id = jQuery(this).data('drone_run_band_project_id');
        assign_plot_polygons_type = jQuery(this).data('assign_plot_polygons_type');

        get_select_box('drone_imagery_parameter_select','plot_polygons_previously_saved_plot_polygon_templates', {'empty':1, 'field_trial_id':trial_id, 'parameter':'plot_polygons' });

        plot_polygons_display_points = [];
        plot_polygons_ind_points = [];
        plot_polygons_ind_4_points = [];
        drone_imagery_plot_polygons = {};
        drone_imagery_plot_polygons_plot_names = {};
        drone_imagery_plot_generated_polygons = {};
        drone_imagery_plot_polygons_display = {};
        plot_polygons_plot_names_colors = {};
        plot_polygons_plot_names_plot_numbers = {};
        field_trial_layout_response = {};
        field_trial_layout_responses = {};
        field_trial_layout_response_names = [];

        jQuery('#manage_drone_imagery_plot_polygons_div_title').html('<center><h4>'+drone_run_project_name+'</h4></center>');

        showManageDroneImagerySection('manage_drone_imagery_plot_polygons_div');

        showPlotPolygonStart(background_removed_stitched_image_id, drone_run_band_project_id, 'drone_imagery_plot_polygons_original_stitched_div', 'drone_imagery_plot_polygons_top_section', 'manage_drone_imagery_plot_polygons_load_div', 0);

        jQuery.ajax({
            url : '/api/drone_imagery/get_field_trial_drone_run_projects_in_same_orthophoto?drone_run_project_id='+drone_run_project_id+'&field_trial_project_id='+trial_id,
            success: function(response){
                console.log(response);
                manage_drone_imagery_standard_process_drone_run_project_ids_in_same_orthophoto = response.drone_run_project_ids;
                manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto = response.drone_run_project_names;
                manage_drone_imagery_standard_process_field_trial_ids_in_same_orthophoto = response.drone_run_field_trial_ids;
                manage_drone_imagery_standard_process_field_trial_names_in_same_orthophoto = response.drone_run_field_trial_names;

                field_trial_layout_responses = response.drone_run_all_field_trial_layouts;
                field_trial_layout_response = field_trial_layout_responses[0];
                field_trial_layout_response_names = response.drone_run_all_field_trial_names;

                var field_trial_layout_counter = 0;
                for (var key in field_trial_layout_responses) {
                    if (field_trial_layout_responses.hasOwnProperty(key)) {
                        var response = field_trial_layout_responses[key];
                        var layout = response.output;

                        for (var i=1; i<layout.length; i++) {
                            drone_imagery_plot_polygons_available_stock_names.push(layout[i][0]);
                        }
                        droneImageryDrawLayoutTable(response, {}, 'drone_imagery_standard_process_trial_layout_div_'+field_trial_layout_counter, 'drone_imagery_standard_process_layout_table_'+field_trial_layout_counter);

                        field_trial_layout_counter = field_trial_layout_counter + 1;
                    }
                }

                plot_polygons_plot_names_colors = {};
                plot_polygons_plot_names_plot_numbers = {};
                var plot_polygons_field_trial_names_order = field_trial_layout_response_names;

                for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
                    var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
                    var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];

                    var randomColor = '#'+Math.floor(Math.random()*16777215).toString(16);

                    var plot_polygons_layout = field_trial_layout_response_current.output;
                    for (var i=1; i<plot_polygons_layout.length; i++) {
                        var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
                        var plot_polygons_plot_name = plot_polygons_layout[i][0];

                        plot_polygons_plot_names_colors[plot_polygons_plot_name] = randomColor;
                        plot_polygons_plot_names_plot_numbers[plot_polygons_plot_name] = plot_polygons_plot_number;
                    }
                }

                //var html = '<div class="panel panel-default"><div class="panel-body"><p>The image contains the '+project_drone_imagery_ground_control_points_drone_run_project_name+' imaging event';

                //if (manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto.length > 0) {
                //    html = html + ' as well as the following imaging events: '+manage_drone_imagery_standard_process_drone_run_project_names_in_same_orthophoto.join();
                //}

                //html = html + '.</p><p><b>Use one of the following three options to assign the generated polygons to the field experiment(s) of these imaging event(s).</b></p></div></div>';

                //jQuery('#drone_imagery_standard_process_generated_polygons_table_header_div').html(html);
            },
            error: function(response){
                alert('Error getting other field trial imaging events in the same orthophoto!');
            }
        });
    });

    function showPlotPolygonStart(background_removed_stitched_image_id, drone_run_band_project_id, canvas_div_id, info_div_id, load_div_id, hover_plot_layout){
        //jQuery.ajax({
        //    url : '/api/drone_imagery/get_contours?image_id='+background_removed_stitched_image_id+'&drone_run_band_project_id='+drone_run_band_project_id,
        //    beforeSend: function() {
        //        jQuery("#working_modal").modal("show");
        //    },
        //    success: function(response){
        //        console.log(response);
        //        jQuery("#working_modal").modal("hide");
        //        background_image_url = response.image_url;

        //        background_image_width = response.image_width;
        //        background_image_height = response.image_height;

        //        var top_section_html = '<h4>Total Image Width: '+response.image_width+'px. Total Image Height: '+response.image_height+'px.</h4>';
        //        top_section_html = top_section_html + '<button class="btn btn-default btn-sm" id="drone_imagery_plot_polygons_switch" data-image_url="'+response.image_url+'" data-image_fullpath="'+response.image_fullpath+'" data-contours_image_url="'+response.contours_image_url+'" data-contours_image_fullpath="'+response.contours_image_fullpath+'">Switch Image View</button><br/><br/>';
        //        jQuery('#'+info_div_id).html(top_section_html);

        //        canvas = document.getElementById(canvas_div_id);
        //        ctx = canvas.getContext('2d');
        //        draw_canvas_image(background_image_url, 0);

        //        plotpolygonsImg = document.getElementById(canvas_div_id);
                //plotpolygonsImg.onmousedown = GetCoordinatesPlotPolygons;
        //        plotpolygonsImg.onmousedown = GetCoordinatesPlotPolygonsPoint;

        //        jQuery('#'+load_div_id).hide();

        //    },
        //    error: function(response){
        //        jQuery("#working_modal").modal("hide");
        //        alert('Error retrieving contours for image!')
        //    }
        //});

        jQuery.ajax({
            url : '/api/drone_imagery/get_image?image_id='+background_removed_stitched_image_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                background_image_url = response.image_url;

                background_image_width = response.image_width;
                background_image_height = response.image_height;

                var top_section_html = '<p>Total Image Width: '+response.image_width+'px. Total Image Height: '+response.image_height+'px.</p>';

                jQuery('#'+info_div_id).html(top_section_html);

                canvas = document.getElementById(canvas_div_id);
                ctx = canvas.getContext('2d');
                draw_canvas_image(background_image_url, 0);

                plotpolygonsImg = document.getElementById(canvas_div_id);
                if (hover_plot_layout == 1) {
                    console.log('hover plot');
                    plotpolygonsImg.onmousemove = handleMouseMovePlotLayoutHover;
                    plotpolygonsImg.onmousedown = handleMouseMovePlotLayoutHoverClick;
                }
                else {
                    //plotpolygonsImg.onmousedown = GetCoordinatesPlotPolygons;
                    plotpolygonsImg.onmousedown = GetCoordinatesPlotPolygonsPoint;
                }

                jQuery('#'+load_div_id).hide();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving plot polygon image!')
            }
        });
    }

    function showPlotPolygonStartSVG(background_removed_stitched_image_id, drone_run_band_project_id, svg_div_id, info_div_id, load_div_id, hover_plot_layout, draw_labeled_plots, alert_plot_names_assigned, gcp_template_allow_drag_corner, show_loading_model, draw_waypoints, waypoints, waypoints_clear_markings){
        jQuery.ajax({
            url : '/api/drone_imagery/get_image?image_id='+background_removed_stitched_image_id,
            beforeSend: function() {
                if (show_loading_model) {
                    jQuery("#working_modal").modal("show");
                }
            },
            success: function(response){
                console.log(response);
                if (show_loading_model) {
                    jQuery("#working_modal").modal("hide");
                }

                background_image_url = response.image_url;

                background_image_width = response.image_width;
                background_image_height = response.image_height;

                var top_section_html = '<p>Total Image Width: '+response.image_width+'px. Total Image Height: '+response.image_height+'px.</p>';

                jQuery('#'+info_div_id).html(top_section_html);

                d3.select('#'+svg_div_id).selectAll("*").remove();
                var svgElement = d3.select('#'+svg_div_id).append("svg")
                    .attr("width", background_image_width)
                    .attr("height", background_image_height)
                    .attr("id", svg_div_id+'_area')
                    .attr("x_pos", 0)
                    .attr("y_pos", 0)
                    .attr("x", 0)
                    .attr("y", 0)
                    .on("click", function(){
                        var coords = d3.mouse(this);
                        var PosX = Math.round(coords[0]);
                        var PosY = Math.round(coords[1]);

                        if (drone_imagery_plot_polygon_click_type == '' && drone_imagery_standard_process_plot_polygon_click_type == '') {
                            alert('X Coordinate: '+PosX+'. Y Coordinate: '+PosY+'.');
                        }
                        else if (drone_imagery_plot_polygon_click_type == 'plot_polygon_template_paste') {
                            drone_imagery_plot_polygon_click_type = '';

                            plotPolygonsTemplatePasteSVG(PosX, PosY, parseInt(drone_imagery_current_plot_polygon_index_options_id), 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
                            plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
                        }
                        else if (drone_imagery_standard_process_plot_polygon_click_type == 'top_left') {
                            drone_imagery_standard_process_plot_polygon_click_type = '';
                            jQuery('#drone_imagery_standard_process_plot_polygons_left_column_top_offset').val(PosY);
                            jQuery('#drone_imagery_standard_process_plot_polygons_top_row_left_offset').val(PosX);

                            alert('Now click the top right corner of the area to create a template for on the image below.');
                            drone_imagery_standard_process_plot_polygon_click_type = 'top_right';
                        }
                        else if (drone_imagery_standard_process_plot_polygon_click_type == 'top_right') {
                            drone_imagery_standard_process_plot_polygon_click_type = '';
                            jQuery('#drone_imagery_standard_process_plot_polygons_top_row_right_offset').val(background_image_width-PosX);

                            alert('Now click the bottom right corner of the area to create a template for on the image below.');
                            drone_imagery_standard_process_plot_polygon_click_type = 'bottom_right';
                        }
                        else if (drone_imagery_standard_process_plot_polygon_click_type == 'bottom_right') {
                            drone_imagery_standard_process_plot_polygon_click_type = '';

                            jQuery('#drone_imagery_standard_process_plot_polygons_right_col_bottom_offset').val(background_image_height-PosY);

                            alert('Now click the bottom left corner of the area to create a template for on the image below.');
                            drone_imagery_standard_process_plot_polygon_click_type = 'bottom_left';
                        }
                        else if (drone_imagery_standard_process_plot_polygon_click_type == 'bottom_left') {
                            drone_imagery_standard_process_plot_polygon_click_type = '';
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
                        else if (drone_imagery_standard_process_plot_polygon_click_type == 'get_distance') {
                            if (plot_polygons_get_distance_point_1x != '') {
                                var distance = Math.round(Math.sqrt(Math.pow(plot_polygons_get_distance_point_1x - PosX, 2) + Math.pow(plot_polygons_get_distance_point_1y - PosY, 2)));
                                alert('Distance='+distance+'. X1='+plot_polygons_get_distance_point_1x+'. Y1='+plot_polygons_get_distance_point_1y+'. X2='+PosX+'. Y2='+PosY);
                                plot_polygons_get_distance_point_1x = '';
                                plot_polygons_get_distance_point_1y = '';
                                drone_imagery_plot_polygon_click_type = '';
                            } else {
                                plot_polygons_get_distance_point_1x = PosX;
                                plot_polygons_get_distance_point_1y = PosY;
                            }
                        }
                        else if (drone_imagery_plot_polygon_click_type == 'save_ground_control_point') {
                            //alert('X Coordinate: '+PosX+'. Y Coordinate: '+PosY+'.');
                            jQuery('#project_drone_imagery_ground_control_points_form_input_x_pos').val(PosX);
                            jQuery('#project_drone_imagery_ground_control_points_form_input_y_pos').val(PosY);
                            jQuery('#project_drone_imagery_ground_control_points_form_dialog').modal('show');
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
                    .attr("xlink:href", background_image_url)
                    .attr("height", background_image_height)
                    .attr("width", background_image_width);


                svgElement.append('rect')
                    .attr('class', 'zoom')
                    .attr('cursor', 'move')
                    .attr('fill', 'none')
                    .attr('pointer-events', 'all')
                    .attr('width', background_image_width)
                    .attr('height', background_image_height);

                jQuery('#'+load_div_id).hide();

                if (draw_labeled_plots) {
                    draw_polygons_svg_plots_labeled(svg_div_id, undefined, gcp_template_allow_drag_corner, alert_plot_names_assigned);
                }
                if (draw_waypoints) {
                    drawWaypointsSVG(svg_div_id, waypoints, waypoints_clear_markings);
                }
            },
            error: function(response){
                if (show_loading_model) {
                    jQuery("#working_modal").modal("hide");
                }
                alert('Error retrieving plot polygon image SVG!')
            }
        });
    }

    var handleMouseMovePlotLayoutHoverPlotInfo = {};
    var handleMouseMovePlotLayoutHoverTraitId;
    var handleMouseMovePlotLayoutHoverPlotPolygonsSeen = {};
    function handleMouseMovePlotLayoutHover(e){
        var PosX = 0;
        var PosY = 0;
        var ImgPos;
        ImgPos = FindPosition(plotpolygonsImg);
        if (!e) var e = window.event;
        if (e.pageX || e.pageY) {
            PosX = e.pageX;
            PosY = e.pageY;
        }
        else if (e.clientX || e.clientY) {
            PosX = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
            PosY = e.clientY + document.body.scrollTop + document.documentElement.scrollTop;
        }
        PosX = PosX - ImgPos[0];
        PosY = PosY - ImgPos[1];

        //ctx.clearRect(0,0,background_image_width,background_image_height);

        var hovering_plot_name;
        for (key in drone_imagery_plot_polygons_display) {
            if (drone_imagery_plot_polygons_display.hasOwnProperty(key)) {
                var s = drone_imagery_plot_polygons_display[key];

                ctx.beginPath();
                ctx.moveTo(s[0].x,s[0].y);
                for(var i=1;i<s.length;i++){
                    ctx.lineTo(s[i].x,s[i].y);
                }
                ctx.closePath();

                if (ctx.isPointInPath(PosX,PosY)){
                    hovering_plot_name = key;
                }
            }
        }

        //draw_canvas_image(background_image_url, 0);

        for (key in drone_imagery_plot_polygons_display) {
            if (drone_imagery_plot_polygons_display.hasOwnProperty(key)) {

                if (key == hovering_plot_name && drone_imagery_plot_polygons_display_plot_field_layout.hasOwnProperty(key)) {
                    var plot_info = drone_imagery_plot_polygons_display_plot_field_layout[key];
                    handleMouseMovePlotLayoutHoverPlotInfo = plot_info;
                }

                if (!handleMouseMovePlotLayoutHoverPlotPolygonsSeen.hasOwnProperty(key)) {
                    var plot_polygons_display_points_again = drone_imagery_plot_polygons_display[key];
                    drawPolyline(plot_polygons_display_points_again);
                    drawWaypoints(plot_polygons_display_points_again, key, undefined);
                    handleMouseMovePlotLayoutHoverPlotPolygonsSeen[key] = 1;
                }
            }
        }
    };

    function handleMouseMovePlotLayoutHoverClick(e) {
        console.log(handleMouseMovePlotLayoutHoverPlotInfo);
        var html = "<center><h4>Go To <a href='/stock/"+handleMouseMovePlotLayoutHoverPlotInfo.plot_id+"/view' target='_blank'>"+handleMouseMovePlotLayoutHoverPlotInfo.plot_name+" Detail Page</a></h4></center><hr>";

        html = html + '<div class="form-horizontal"><div class="form-group"><label class="col-sm-3 control-label">Select a Trait:</label><div class="col-sm-9" ><div id="drone_imagery_time_series_hover_trait_select_div"></div></div></div></div>';

        jQuery('#manage_drone_imagery_field_trial_time_series_popup_content').html(html);

        get_select_box('traits', 'drone_imagery_time_series_hover_trait_select_div', {'id':'drone_imagery_time_series_hover_trait_select_id', 'name':'drone_imagery_time_series_hover_trait_select_id', 'stock_id':handleMouseMovePlotLayoutHoverPlotInfo.accession_id, 'empty':1});

        jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure1').html("");
        jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure2').html("");
        jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure3').html("");

        jQuery('#manage_drone_imagery_field_trial_time_series_popup').modal('show');
    }

    jQuery(document).on('change', '#drone_imagery_time_series_hover_trait_select_id', function() {
        handleMouseMovePlotLayoutHoverTraitId = jQuery(this).val();

        jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure1').html("");
        jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure2').html("");
        jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure3').html("");

        jQuery.ajax({
            url : '/api/drone_imagery/accession_phenotype_histogram?accession_id='+handleMouseMovePlotLayoutHoverPlotInfo.accession_id+'&trait_id='+handleMouseMovePlotLayoutHoverTraitId+'&plot_id='+handleMouseMovePlotLayoutHoverPlotInfo.plot_id+'&figure_type=all_pheno_of_this_accession',
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if (response.error) {
                    alert(response.error);
                    return false;
                }

                jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure2').html("<div class='well well-sm'><center><h3>Performance of accession: <a href='/stock/"+handleMouseMovePlotLayoutHoverPlotInfo.accession_id+"/view' target=_blank>"+handleMouseMovePlotLayoutHoverPlotInfo.accession_name+"</a> in the current field plot compared to all phenotypes of this accession</h3><p>The mean value of this accession is in green.<p><p>The value of the current field plot is drawn in red.</p><img src='"+response.figure+"' width='500' height='400'></center></div>");
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving accession phenotype plot!')
            }
        });

        jQuery.ajax({
            url : '/api/drone_imagery/accession_phenotype_histogram?field_trial_id='+manage_drone_imagery_field_trial_time_series_field_trial_id+'&trait_id='+handleMouseMovePlotLayoutHoverTraitId+'&plot_id='+handleMouseMovePlotLayoutHoverPlotInfo.plot_id+'&accession_id='+handleMouseMovePlotLayoutHoverPlotInfo.accession_id+'&figure_type=all_pheno_of_this_trial',
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if (response.error) {
                    alert(response.error);
                    return false;
                }

                jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure1').html("<div class='well well-sm'><center><h3>Performance of accession: <a href='/stock/"+handleMouseMovePlotLayoutHoverPlotInfo.accession_id+"/view' target=_blank>"+handleMouseMovePlotLayoutHoverPlotInfo.accession_name+"</a> in the current field plot compared to all other phenotypes in this field trial</h3><p>The mean value of this accession is in green.<p><p>The value of the current field plot is drawn in red</p><img src='"+response.figure+"' width='500' height='400'></center></div>");
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving accession phenotype plot for field trial!')
            }
        });

        jQuery.ajax({
            url : '/api/drone_imagery/accession_phenotype_histogram?trait_id='+handleMouseMovePlotLayoutHoverTraitId+'&plot_id='+handleMouseMovePlotLayoutHoverPlotInfo.plot_id+'&accession_id='+handleMouseMovePlotLayoutHoverPlotInfo.accession_id+'&figure_type=all_pheno_in_database',
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if (response.error) {
                    alert(response.error);
                    return false;
                }

                jQuery('#manage_drone_imagery_field_trial_time_series_popup_content_figure3').html("<div class='well well-sm'><center><h3>Performance of accession: <a href='/stock/"+handleMouseMovePlotLayoutHoverPlotInfo.accession_id+"/view' target=_blank>"+handleMouseMovePlotLayoutHoverPlotInfo.accession_name+"</a> in the current plot compared to all other phenotypes in the database</h3><p>The mean value of this accession is in green.<p><p>The value of the current field plot is drawn in red</p><img src='"+response.figure+"' width='500' height='400'></center></div>");
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving accession phenotype plot for field trial!')
            }
        });
    });

    var drone_imagery_plot_polygon_click_type = '';
    jQuery('#drone_imagery_plot_polygons_top_left_click').click(function(){
        alert('Now click the top left corner of your field on the image below.');
        drone_imagery_plot_polygon_click_type = 'top_left';
    });
    jQuery('#drone_imagery_plot_polygons_top_right_click').click(function(){
        alert('Now click the top right corner of your field on the image below.');
        drone_imagery_plot_polygon_click_type = 'top_right';
    });
    jQuery('#drone_imagery_plot_polygons_bottom_left_click').click(function(){
        alert('Now click the bottom left corner of your field on the image below.');
        drone_imagery_plot_polygon_click_type = 'bottom_left';
    });
    jQuery('#drone_imagery_plot_polygons_bottom_right_click').click(function(){
        alert('Now click the bottom right corner of your field on the image below.');
        drone_imagery_plot_polygon_click_type = 'bottom_right';
    });
    jQuery(document).on('click', '#drone_imagery_plot_polygons_get_distance', function(){
        alert('Click on two points in image. The distance will be returned.');
        drone_imagery_plot_polygon_click_type = 'get_distance';
        return false;
    });

    var drone_imagery_plot_polygon_current_background_toggle = 1;
    jQuery(document).on('click', '#drone_imagery_plot_polygons_switch', function(){
        var image_url;
        if (drone_imagery_plot_polygon_current_background_toggle == 0) {
            drone_imagery_plot_polygon_current_background_toggle = 1;
            image_url = jQuery(this).data('contours_image_url');
        } else if (drone_imagery_plot_polygon_current_background_toggle == 1) {
            drone_imagery_plot_polygon_current_background_toggle = 0;
            image_url = jQuery(this).data('image_url');
        }
        draw_canvas_image(image_url, plot_polygons_total_height_generated/plot_polygons_num_rows_generated);

        return;
    });

    jQuery('#plot_polygons_use_previously_saved_template').click(function() {
        var plot_polygons_use_previously_saved_template = jQuery('#drone_imagery_plot_polygon_select').val();
        if (plot_polygons_use_previously_saved_template == '') {
            alert('Please select a previously saved template before trying to apply it. If there is not a template listed, then you can create one using the templating tool above.');
            return;
        }

        jQuery.ajax({
            url : '/api/drone_imagery/retrieve_parameter_template?plot_polygons_template_projectprop_id='+plot_polygons_use_previously_saved_template,
            success: function(response){
                console.log(response);

                drone_imagery_plot_polygons_display = response.parameter;
                drone_imagery_plot_polygons = response.parameter;

                draw_canvas_image(background_image_url, 0);
                droneImageryDrawLayoutTable(field_trial_layout_response, drone_imagery_plot_polygons, 'drone_imagery_trial_layout_div', 'drone_imagery_layout_table');
                droneImageryRectangleLayoutTable(drone_imagery_plot_polygons, 'drone_imagery_generated_polygons_div', 'drone_imagery_plot_polygons_generated_assign', 'drone_imagery_plot_polygons_submit_bottom');
            },
            error: function(response){
                alert('Error retrieving plot polygons template!');
            }
        });
        return;
    });

    var plot_polygons_num_rows_generated;
    var plot_polygons_num_cols_generated;
    var plot_polygons_number_generated;
    var plot_polygons_total_height_generated;
    var plot_polygons_template_dimensions_svg = [];
    var plot_polygons_template_dimensions_template_number_svg = 0;
    var plot_polygons_template_dimensions_deleted_templates_svg = [];

    jQuery('#drone_imagery_plot_polygons_rectangles_apply').click(function() {
        plot_polygons_display_points = [];
        plot_polygons_ind_points = [];
        plot_polygons_ind_4_points = [];

        var num_rows_val = jQuery('#drone_imagery_plot_polygons_num_rows').val();
        var num_cols_val = jQuery('#drone_imagery_plot_polygons_num_cols').val();
        var section_top_row_left_offset_val = jQuery('#drone_imagery_plot_polygons_top_row_left_offset').val();
        var section_bottom_row_left_offset_val = jQuery('#drone_imagery_plot_polygons_bottom_row_left_offset').val();
        var section_left_column_top_offset_val = jQuery('#drone_imagery_plot_polygons_left_column_top_offset').val();
        var section_left_column_bottom_offset_val = jQuery('#drone_imagery_plot_polygons_left_column_bottom_offset').val();
        var section_top_row_right_offset_val = jQuery('#drone_imagery_plot_polygons_top_row_right_offset').val();
        var section_right_column_bottom_offset_val = jQuery('#drone_imagery_plot_polygons_right_col_bottom_offset').val();

        plotPolygonsRectanglesApply(num_rows_val, num_cols_val, section_top_row_left_offset_val, section_bottom_row_left_offset_val, section_left_column_top_offset_val, section_left_column_bottom_offset_val, section_top_row_right_offset_val, section_right_column_bottom_offset_val, 'drone_imagery_generated_polygons_div', 'drone_imagery_generated_polygons_table', 'drone_imagery_plot_polygons_generated_assign', 'drone_imagery_plot_polygons_submit_bottom', 'drone_imagery_plot_polygons_active_templates');

        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
    });

    function plotPolygonManualAssignPlotNumberTableStandard(div_id, table_id, input_name, generate_assign_button, save_button) {
        var html = '<div class="panel panel-default"><div class="panel-body"><ul><li>If Option 1 was unable to fit your field experiments, Option 2 or 3 offers greater flexibility.</li><li>If you want to skip a generated polygon, leave the plot number blank and it will be skipped.</li></ul>';
        html = html + '</div></div>';
        html = html + '<div class="panel panel-default"><div class="panel-body">';
        html = html + '<table class="table table-bordered table-hover" id="'+table_id+'"><thead><tr><th>Polygon Number</th><th>Plot Number</th><th>Field Trial</th></tr></thead><tbody>';
        for(var i=0; i<plot_polygons_generated_polygons.length; i++) {
            html = html + '<tr>';
            html = html + '<td>'+i+'</td>';
            html = html + '<td><input type="number" class="form-control" data-polygon_number="'+i+'" name="'+input_name+'" /></td>';
            html = html + '<td><select class="form-control" data-polygon_number="'+i+'" name="'+input_name+'_field_trial" >';
            for (var j=0; j<field_trial_layout_response_names.length; j++) {
                html = html + '<option value="' + field_trial_layout_response_names[j] + '">' + field_trial_layout_response_names[j] + '</option>';
            }
            html = html + '</select></td>';
            html = html + '</tr>';
        }
        html = html + '</tbody></table><hr>';
        html = html + '<button class="btn btn-primary" id="'+generate_assign_button+'">Generate Assignments From Manual Input (Does Not Save)</button>&nbsp;&nbsp;&nbsp;<button class="btn btn-primary" name="'+save_button+'">Finish and Save Polygons To Plots</button></div></div>';
        //console.log(html);
        jQuery('#'+div_id).html(html);
        jQuery('#'+table_id).DataTable({'paging':false});
    }

    function plotPolygonsRectanglesApply(num_rows_val, num_cols_val, section_top_row_left_offset_val, section_bottom_row_left_offset_val, section_left_column_top_offset_val, section_left_column_bottom_offset_val, section_top_row_right_offset_val, section_right_column_bottom_offset_val, plot_polygons_assignment_info, plot_polygons_assignment_table, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button, drone_imagery_plot_polygons_active_templates) {
        if (num_rows_val == ''){
            alert('Please give the number of rows!');
            return;
        }
        if (num_cols_val == ''){
            alert('Please give the number of columns!');
            return;
        }
        if (section_top_row_left_offset_val == ''){
            alert('Please give the top-most rows left margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_bottom_row_left_offset_val == ''){
            alert('Please give the bottom-most rows left margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_left_column_top_offset_val == ''){
            alert('Please give the left-most columns top margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_left_column_bottom_offset_val == ''){
            alert('Please give the left-most columns bottom margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_top_row_right_offset_val == ''){
            alert('Please give the top-most rows right margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_right_column_bottom_offset_val == ''){
            alert('Please give the right-most columns bottom margin! This can be 0 if there is no offset.');
            return;
        }

        plot_polygons_num_rows_generated = parseInt(num_rows_val);
        plot_polygons_num_cols_generated = parseInt(num_cols_val);

        var section_width = background_image_width;
        var section_height = background_image_height;
        var section_top_row_left_offset = parseInt(section_top_row_left_offset_val);
        var section_bottom_row_left_offset = parseInt(section_bottom_row_left_offset_val);
        var section_left_column_top_offset = parseInt(section_left_column_top_offset_val);
        var section_left_column_bottom_offset = parseInt(section_left_column_bottom_offset_val);
        var section_top_row_right_offset = parseInt(section_top_row_right_offset_val);
        var section_right_column_bottom_offset = parseInt(section_right_column_bottom_offset_val);

        var total_gradual_left_shift = section_bottom_row_left_offset - section_top_row_left_offset;
        var col_left_shift_increment = total_gradual_left_shift / plot_polygons_num_rows_generated;

        var total_gradual_vertical_shift = section_right_column_bottom_offset - section_left_column_bottom_offset;
        var col_vertical_shift_increment = total_gradual_vertical_shift / plot_polygons_num_cols_generated;

        var col_width = (section_width - section_top_row_left_offset - section_top_row_right_offset) / plot_polygons_num_cols_generated;
        var row_height = (section_height - section_left_column_top_offset - section_left_column_bottom_offset) / plot_polygons_num_rows_generated;

        var x_pos = section_top_row_left_offset;
        var y_pos = section_left_column_top_offset;

        var row_num = 1;
        for (var i=0; i<plot_polygons_num_rows_generated; i++) {
            for (var j=0; j<plot_polygons_num_cols_generated; j++) {
                var x_pos_val = x_pos;
                var y_pos_val = y_pos;
                plot_polygons_generated_polygons.push([
                    {x:x_pos_val, y:y_pos_val},
                    {x:x_pos_val + col_width, y:y_pos_val},
                    {x:x_pos_val + col_width, y:y_pos_val + row_height},
                    {x:x_pos_val, y:y_pos_val + row_height}
                ]);
                x_pos = x_pos + col_width;
                y_pos = y_pos - col_vertical_shift_increment;
            }
            x_pos = section_top_row_left_offset + (row_num * col_left_shift_increment);
            y_pos = y_pos + row_height + total_gradual_vertical_shift;
            row_num = row_num + 1;
        }
        //console.log(plot_polygons_generated_polygons);

        plot_polygons_total_height_generated = row_height * plot_polygons_num_rows_generated;
        plot_polygons_number_generated = plot_polygons_generated_polygons.length;

        var drone_imagery_plot_polygons_new = {};
        var drone_imagery_plot_polygons_display_new = {};

        for (var i=0; i<plot_polygons_generated_polygons.length; i++) {
            plot_polygons_ind_4_points = plot_polygons_generated_polygons[i];
            plot_polygons_display_points = plot_polygons_ind_4_points;
            if (plot_polygons_display_points.length == 4) {
                plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
            }
            drawPolyline(plot_polygons_display_points);
            drawWaypoints(plot_polygons_display_points, i, 0);
            drone_imagery_plot_generated_polygons[i] = plot_polygons_ind_4_points;
            drone_imagery_plot_polygons_new[i] = plot_polygons_ind_4_points;
            drone_imagery_plot_polygons_display[i] = plot_polygons_display_points;
            drone_imagery_plot_polygons_display_new[i] = plot_polygons_display_points;
        }

        plot_polygons_template_dimensions.push({
            'num_rows':plot_polygons_num_rows_generated,
            'num_cols':plot_polygons_num_cols_generated,
            'total_plot_polygons':plot_polygons_num_rows_generated*plot_polygons_num_cols_generated,
            'plot_polygons':drone_imagery_plot_polygons_new,
            'plot_polygons_display':drone_imagery_plot_polygons_display_new
        });

        droneImageryDrawPlotPolygonActiveTemplatesTable(drone_imagery_plot_polygons_active_templates, plot_polygons_template_dimensions);

        droneImageryRectangleLayoutTable(drone_imagery_plot_generated_polygons, plot_polygons_assignment_info, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button);
    }

    var line = d3.line()
        .x(function(d) { return d[0]; })
        .y(function(d) { return d[1]; });

    function dragstarted(d) {
        d3.select(this).raise().classed('active', true);
    }

    function dragged(d) {
        var x = d3.event.x;
        var y = d3.event.y;
        var corner = d3.select(this).attr('corner');
        var template_number = d3.select(this).attr('template_number');
        //console.log([x,y,corner,template_number]);

        if (corner == 'top_left') {
            plot_polygons_template_dimensions_svg[template_number]['section_top_row_left_offset_val'] = x;
            plot_polygons_template_dimensions_svg[template_number]['section_left_column_top_offset_val'] = y;
        }
        if (corner == 'top_right') {
            plot_polygons_template_dimensions_svg[template_number]['section_top_row_right_offset_val'] = background_image_width - x;
        }
        if (corner == 'bottom_left') {
            plot_polygons_template_dimensions_svg[template_number]['section_bottom_row_left_offset_val'] = x;
            plot_polygons_template_dimensions_svg[template_number]['section_left_column_bottom_offset_val'] = background_image_height - y;
        }
        if (corner == 'bottom_right') {
            plot_polygons_template_dimensions_svg[template_number]['section_right_column_bottom_offset_val'] = background_image_height - y;
        }
    }

    function dragended(d) {
        var x = d3.event.x;
        var y = d3.event.y;
        d3.select(this).classed('active', false);
        var template_number = d3.select(this).attr('template_number');
        var corner = d3.select(this).attr('corner');

        plot_polygons_template_dimensions_deleted_templates_svg.push(parseInt(template_number));

        var circles = plot_polygons_template_dimensions_svg[template_number]['plot_polygons_generated_polygons_circles_svg'];
        var corners_circles = {};
        for (var i=0; i<circles.length; i++) {
            corners_circles[circles[i][2]] = [circles[i][0], circles[i][1]];
        }
        //console.log(corners_circles);

        if (corner == 'top_right') {
            var tr_corner_y = corners_circles[corner][1];
            var tr_y_diff = tr_corner_y - y;
            var old = parseInt(plot_polygons_template_dimensions_svg[template_number]['section_right_column_bottom_offset_val']);
            plot_polygons_template_dimensions_svg[template_number]['section_right_column_bottom_offset_val'] = old + tr_y_diff;
        }
        if (corner == 'bottom_right') {
            var br_corner_x = corners_circles[corner][0];
            var br_x_diff = br_corner_x - x;
            var old = plot_polygons_template_dimensions_svg[template_number]['section_top_row_right_offset_val'];
            plot_polygons_template_dimensions_svg[template_number]['section_top_row_right_offset_val'] = old + br_x_diff;
        }

        var num_rows_val = plot_polygons_template_dimensions_svg[template_number]['num_rows_val'];
        var num_cols_val = plot_polygons_template_dimensions_svg[template_number]['num_cols_val'];
        var section_top_row_left_offset_val = plot_polygons_template_dimensions_svg[template_number]['section_top_row_left_offset_val'];
        var section_top_row_right_offset_val = plot_polygons_template_dimensions_svg[template_number]['section_top_row_right_offset_val'];
        var section_bottom_row_left_offset_val = plot_polygons_template_dimensions_svg[template_number]['section_bottom_row_left_offset_val'];
        var section_left_column_top_offset_val = plot_polygons_template_dimensions_svg[template_number]['section_left_column_top_offset_val'];
        var section_left_column_bottom_offset_val = plot_polygons_template_dimensions_svg[template_number]['section_left_column_bottom_offset_val'];
        var section_right_column_bottom_offset_val = plot_polygons_template_dimensions_svg[template_number]['section_right_column_bottom_offset_val'];
        var polygon_margin_top_bottom_val = plot_polygons_template_dimensions_svg[template_number]['polygon_margin_top_bottom_val'];
        var polygon_margin_left_right_val = plot_polygons_template_dimensions_svg[template_number]['polygon_margin_left_right_val'];

        plotPolygonsRectanglesApplySVG(num_rows_val, num_cols_val, section_top_row_left_offset_val, section_bottom_row_left_offset_val, section_left_column_top_offset_val, section_left_column_bottom_offset_val, section_top_row_right_offset_val, section_right_column_bottom_offset_val, polygon_margin_top_bottom_val, polygon_margin_left_right_val, 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom', 'drone_imagery_standard_process_plot_polygons_active_templates' );
    }

    let drag = d3.drag()
        .on('start', dragstarted)
        .on('drag', dragged)
        .on('end', dragended);

    function dragstartedgcptemplate(d) {
        d3.select(this).raise().classed('active', true);
    }

    function draggedgcptemplate(d) {
        var x = d3.event.x;
        var y = d3.event.y;
        //console.log([x,y]);
    }

    function dragendedgcptemplate(d) {
        var x = d3.event.x;
        var y = d3.event.y;
        d3.select(this).classed('active', false);
        var orig_x = d3.select(this).attr('cx');
        var orig_y = d3.select(this).attr('cy');
        var corner = d3.select(this).attr('corner');
        //console.log(drone_imagery_plot_polygons_display);

        var drone_imagery_plot_polygons_display_gcp_dragged = {};
        if (corner == 'top_left') {
            if (drone_imagery_standard_process_ground_control_points_original_x == 0) {
                drone_imagery_standard_process_ground_control_points_original_x = orig_x;
            }
            if (drone_imagery_standard_process_ground_control_points_original_y == 0) {
                drone_imagery_standard_process_ground_control_points_original_y = orig_y;
            }

            drone_imagery_standard_process_ground_control_points_x_diff = drone_imagery_standard_process_ground_control_points_original_x - x;
            drone_imagery_standard_process_ground_control_points_y_diff = drone_imagery_standard_process_ground_control_points_original_y - y;

            var x_diff = orig_x - x;
            var y_diff = orig_y - y;

            for (key in drone_imagery_plot_polygons_display) {
                if (drone_imagery_plot_polygons_display.hasOwnProperty(key)) {
                    var plot_polygons_display_points_again = drone_imagery_plot_polygons_display[key];

                    drone_imagery_plot_polygons_display_gcp_dragged[key] = [
                        {'x': plot_polygons_display_points_again[0].x - x_diff, 'y': plot_polygons_display_points_again[0].y - y_diff},
                        {'x': plot_polygons_display_points_again[1].x - x_diff, 'y': plot_polygons_display_points_again[1].y - y_diff},
                        {'x': plot_polygons_display_points_again[2].x - x_diff, 'y': plot_polygons_display_points_again[2].y - y_diff},
                        {'x': plot_polygons_display_points_again[3].x - x_diff, 'y': plot_polygons_display_points_again[3].y - y_diff},
                    ];
                }
            }
            drone_imagery_plot_polygons_display = drone_imagery_plot_polygons_display_gcp_dragged;
        }
        if (corner == 'bottom_right') {
            if (drone_imagery_standard_process_ground_control_points_original_resize_x == 0) {
                drone_imagery_standard_process_ground_control_points_original_resize_x = orig_x;
            }
            if (drone_imagery_standard_process_ground_control_points_original_resize_y == 0) {
                drone_imagery_standard_process_ground_control_points_original_resize_y = orig_y;
            }

            drone_imagery_standard_process_ground_control_points_resize_x_diff = drone_imagery_standard_process_ground_control_points_original_resize_x - x;
            drone_imagery_standard_process_ground_control_points_resize_y_diff = drone_imagery_standard_process_ground_control_points_original_resize_y - y;

            var x_diff = orig_x - x;
            var y_diff = orig_y - y;

        }
        //console.log(drone_imagery_plot_polygons_display);
        draw_polygons_svg_plots_labeled('project_drone_imagery_standard_process_ground_control_points_svg_div', undefined, 1, undefined);
    }

    let draggcptemplate = d3.drag()
        .on('start', dragstartedgcptemplate)
        .on('drag', draggedgcptemplate)
        .on('end', dragendedgcptemplate);

    function plotPolygonsRectanglesApplySVG(num_rows_val, num_cols_val, section_top_row_left_offset_val, section_bottom_row_left_offset_val, section_left_column_top_offset_val, section_left_column_bottom_offset_val, section_top_row_right_offset_val, section_right_column_bottom_offset_val, polygon_margin_top_bottom_val, polygon_margin_left_right_val, plot_polygons_assignment_info, plot_polygons_assignment_table, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button, drone_imagery_plot_polygons_active_templates) {
        if (num_rows_val == ''){
            alert('Please give the number of rows!');
            return;
        }
        if (num_cols_val == ''){
            alert('Please give the number of columns!');
            return;
        }
        if (section_top_row_left_offset_val == ''){
            alert('Please give the top-most rows left margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_bottom_row_left_offset_val == ''){
            alert('Please give the bottom-most rows left margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_left_column_top_offset_val == ''){
            alert('Please give the left-most columns top margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_left_column_bottom_offset_val == ''){
            alert('Please give the left-most columns bottom margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_top_row_right_offset_val == ''){
            alert('Please give the top-most rows right margin! This can be 0 if there is no offset.');
            return;
        }
        if (section_right_column_bottom_offset_val == ''){
            alert('Please give the right-most columns bottom margin! This can be 0 if there is no offset.');
            return;
        }

        plot_polygons_num_rows_generated = parseInt(num_rows_val);
        plot_polygons_num_cols_generated = parseInt(num_cols_val);

        var section_width = background_image_width;
        var section_height = background_image_height;
        var section_top_row_left_offset = parseInt(section_top_row_left_offset_val);
        var section_bottom_row_left_offset = parseInt(section_bottom_row_left_offset_val);
        var section_left_column_top_offset = parseInt(section_left_column_top_offset_val);
        var section_left_column_bottom_offset = parseInt(section_left_column_bottom_offset_val);
        var section_top_row_right_offset = parseInt(section_top_row_right_offset_val);
        var section_right_column_bottom_offset = parseInt(section_right_column_bottom_offset_val);

        var total_gradual_left_shift = section_bottom_row_left_offset - section_top_row_left_offset;
        var col_left_shift_increment = total_gradual_left_shift / plot_polygons_num_rows_generated;

        var total_gradual_vertical_shift = section_right_column_bottom_offset - section_left_column_bottom_offset;
        var col_vertical_shift_increment = total_gradual_vertical_shift / plot_polygons_num_cols_generated;

        var col_width = (section_width - section_top_row_left_offset - section_top_row_right_offset) / plot_polygons_num_cols_generated;
        var row_height = (section_height - section_left_column_top_offset - section_left_column_bottom_offset) / plot_polygons_num_rows_generated;

        var col_width_margin = col_width * polygon_margin_left_right_val/100;
        var row_height_margin = row_height * polygon_margin_top_bottom_val/100;

        var x_pos = section_top_row_left_offset;
        var y_pos = section_left_column_top_offset;

        var row_num = 1;

        var plot_polygons_generated_polygons_svg = [];
        var plot_polygons_generated_polygons_rows_svg = [];
        var plot_polygons_generated_polygons_circles_svg = [];
        for (var i=0; i<plot_polygons_num_rows_generated; i++) {

            for (var j=0; j<plot_polygons_num_cols_generated; j++) {
                var x_pos_val = x_pos + col_width_margin;
                var y_pos_val = y_pos + row_height_margin;
                var tl_x = x_pos_val + col_width_margin;
                var tl_y = y_pos_val + row_height_margin;
                var tr_x = x_pos_val + col_width - col_width_margin;
                var tr_y = y_pos_val + row_height_margin;
                var br_x = x_pos_val + col_width - col_width_margin;
                var br_y = y_pos_val + row_height - row_height_margin;
                var bl_x = x_pos_val + col_width_margin;
                var bl_y = y_pos_val + row_height - row_height_margin;
                plot_polygons_generated_polygons_svg.push([
                    {x:tl_x, y:tl_y},
                    {x:tr_x, y:tr_y},
                    {x:br_x, y:br_y},
                    {x:bl_x, y:bl_y}
                ]);
                var row_svg = [];
                row_svg.push([tl_x, tl_y]);
                row_svg.push([tr_x, tr_y]);
                row_svg.push([br_x, br_y]);
                row_svg.push([bl_x, bl_y]);
                row_svg.push([tl_x, tl_y]);
                plot_polygons_generated_polygons_rows_svg.push(row_svg);

                if (i == 0 && j==0) {
                    plot_polygons_generated_polygons_circles_svg.push([tl_x-col_width_margin, tl_y-row_height_margin, 'top_left']);
                }
                if (i == plot_polygons_num_rows_generated-1 && j == 0) {
                    plot_polygons_generated_polygons_circles_svg.push([bl_x-col_width_margin, bl_y+row_height_margin, 'bottom_left']);
                }
                if (i == 0 && j == plot_polygons_num_cols_generated-1) {
                    plot_polygons_generated_polygons_circles_svg.push([tr_x+col_width_margin, tr_y-row_height_margin, 'top_right']);
                }
                if (i == plot_polygons_num_rows_generated-1 && j == plot_polygons_num_cols_generated-1) {
                    plot_polygons_generated_polygons_circles_svg.push([br_x+col_width_margin, br_y+row_height_margin, 'bottom_right']);
                }

                x_pos = x_pos + col_width;
                y_pos = y_pos - col_vertical_shift_increment;
            }

            x_pos = section_top_row_left_offset + (row_num * col_left_shift_increment);
            y_pos = y_pos + row_height + total_gradual_vertical_shift;
            row_num = row_num + 1;
        }
        //console.log(plot_polygons_generated_polygons_svg);
        //console.log(plot_polygons_generated_polygons_rows_svg);
        //console.log(plot_polygons_generated_polygons_circles_svg);

        plot_polygons_total_height_generated = row_height * plot_polygons_num_rows_generated;
        plot_polygons_number_generated = plot_polygons_generated_polygons.length;

        var drone_imagery_plot_generated_polygons_new = [];
        var drone_imagery_plot_polygons_display_new = [];

        for (var i=0; i<plot_polygons_generated_polygons_svg.length; i++) {
            plot_polygons_ind_4_points = plot_polygons_generated_polygons_svg[i];
            plot_polygons_display_points = plot_polygons_ind_4_points;
            if (plot_polygons_display_points.length == 4) {
                plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
            }
            drone_imagery_plot_generated_polygons_new.push(plot_polygons_ind_4_points);
            drone_imagery_plot_polygons_display_new.push(plot_polygons_display_points);
        }

        plot_polygons_template_dimensions_svg.push({
            'template_number':plot_polygons_template_dimensions_template_number_svg,
            'num_rows':plot_polygons_num_rows_generated,
            'num_cols':plot_polygons_num_cols_generated,
            'num_rows_val':num_rows_val,
            'num_cols_val':num_cols_val,
            'section_top_row_left_offset_val':section_top_row_left_offset_val,
            'section_bottom_row_left_offset_val':section_bottom_row_left_offset_val,
            'section_left_column_top_offset_val':section_left_column_top_offset_val,
            'section_left_column_bottom_offset_val':section_left_column_bottom_offset_val,
            'section_top_row_right_offset_val':section_top_row_right_offset_val,
            'section_right_column_bottom_offset_val':section_right_column_bottom_offset_val,
            'total_plot_polygons':plot_polygons_num_rows_generated*plot_polygons_num_cols_generated,
            'drone_imagery_plot_generated_polygons':drone_imagery_plot_generated_polygons_new,
            'drone_imagery_plot_polygons_display':drone_imagery_plot_polygons_display_new,
            'plot_polygons_generated_polygons_svg':plot_polygons_generated_polygons_svg,
            'plot_polygons_generated_polygons_rows_svg':plot_polygons_generated_polygons_rows_svg,
            'plot_polygons_generated_polygons_circles_svg':plot_polygons_generated_polygons_circles_svg,
            'polygon_margin_top_bottom_val':polygon_margin_top_bottom_val,
            'polygon_margin_left_right_val':polygon_margin_left_right_val,
            'col_width':col_width,
            'row_height':row_height,
            'col_width_margin':col_width_margin,
            'row_height_margin':row_height_margin
        });
        console.log(plot_polygons_template_dimensions_svg);

        plot_polygons_template_dimensions_template_number_svg = plot_polygons_template_dimensions_template_number_svg + 1;

        draw_polygons_svg('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg');
        droneImageryDrawPlotPolygonActiveTemplatesTableSVG(drone_imagery_plot_polygons_active_templates, plot_polygons_template_dimensions_svg);
        droneImageryRectangleLayoutTable(drone_imagery_plot_generated_polygons, plot_polygons_assignment_info, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button);
        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
    }

    function draw_polygons_svg(svg_div_id) {
        d3.selectAll("path").remove();
        d3.selectAll("text").remove();
        d3.selectAll("circle").remove();
        d3.selectAll("rect").remove();

        var svg = d3.select('#'+svg_div_id).select("svg");
        focus = svg.append("g");

        console.log(plot_polygons_template_dimensions_deleted_templates_svg);

        var label_count = 0;
        var polygon_index = 0;
        var plot_polygons_generated_polygons_circles_svg_iteration_template = [];

        plot_polygons_generated_polygons = [];
        drone_imagery_plot_generated_polygons = {};
        drone_imagery_plot_polygons_display = {};
        plot_polygons_plot_names_colors = {};
        plot_polygons_plot_names_plot_numbers = {};

        for (var i=0; i<plot_polygons_template_dimensions_svg.length; i++) {
            if (plot_polygons_template_dimensions_deleted_templates_svg.includes(i)) {
                console.log('Not showing template: '+i);
            }
            else {
                var plot_polygons_generated_polygons_svg_iteration = plot_polygons_template_dimensions_svg[i]['plot_polygons_generated_polygons_svg'];
                var plot_polygons_generated_polygons_rows_svg_iteration = plot_polygons_template_dimensions_svg[i]['plot_polygons_generated_polygons_rows_svg'];
                var plot_polygons_generated_polygons_circles_svg_iteration = plot_polygons_template_dimensions_svg[i]['plot_polygons_generated_polygons_circles_svg'];
                var drone_imagery_plot_generated_polygons_iteration = plot_polygons_template_dimensions_svg[i]['drone_imagery_plot_generated_polygons'];
                var drone_imagery_plot_polygons_display_iteration = plot_polygons_template_dimensions_svg[i]['drone_imagery_plot_polygons_display'];

                for (var j=0; j<plot_polygons_generated_polygons_svg_iteration.length; j++) {
                    plot_polygons_generated_polygons.push(plot_polygons_generated_polygons_svg_iteration[j]);
                }
                //console.log(plot_polygons_generated_polygons);

                for (var j=0; j<drone_imagery_plot_generated_polygons_iteration.length; j++) {
                    drone_imagery_plot_generated_polygons[polygon_index] = drone_imagery_plot_generated_polygons_iteration[j];
                    drone_imagery_plot_polygons_display[polygon_index] = drone_imagery_plot_polygons_display_iteration[j];
                    polygon_index = polygon_index + 1;
                }
                //console.log(drone_imagery_plot_generated_polygons);
                //console.log(drone_imagery_plot_polygons_display);

                for (var j=0; j<plot_polygons_generated_polygons_circles_svg_iteration.length; j++) {
                    var circles_val = plot_polygons_generated_polygons_circles_svg_iteration[j];
                    circles_val.push(i);
                    plot_polygons_generated_polygons_circles_svg_iteration_template.push(circles_val);
                }

                for (var k=0; k<plot_polygons_generated_polygons_rows_svg_iteration.length; k++) {
                    var poly_points = plot_polygons_generated_polygons_rows_svg_iteration[k];
                    //console.log(poly_points);
                    focus.append("path")
                        .datum(poly_points)
                        .attr("fill", "none")
                        .attr("stroke", "steelblue")
                        .attr("stroke-linejoin", "round")
                        .attr("stroke-linecap", "round")
                        .attr("stroke-width", 4.5)
                        .attr("d", line);

                    var label_stroke;
                    var label_x;
                    var label_y;
                    if (drone_imagery_plot_polygons_removed_numbers.includes(label_count.toString())) {
                        label = 'NA';
                        label_stroke = 'blue';
                        label_x = poly_points[0][0] + 3;
                        label_y = poly_points[0][1] + 14;
                    } else {
                        label = label_count;
                        label_stroke = 'red';
                        label_x = parseInt(poly_points[0][0]) + 3;
                        label_y = parseInt(poly_points[0][1]) + 14;
                    }

                    focus.append("text")
                        .attr("x", label_x)
                        .attr("y", label_y)
                        .style('fill', label_stroke)
                        .style("font-size", "18px")
                        .style("font-weight", 500)
                        .text(label);

                    label_count = label_count + 1;
                }

                var template_x_point = plot_polygons_generated_polygons_rows_svg_iteration[0][0][0];
                var template_y_point = plot_polygons_generated_polygons_rows_svg_iteration[0][0][1];
                focus.append("text")
                    .attr("x", template_x_point-12)
                    .attr("y", template_y_point-12)
                    .style('fill', 'red')
                    .style("font-size", "28px")
                    .style("font-weight", 600)
                    .text(i);
            }
        }

        focus.selectAll('circle')
            .data(plot_polygons_generated_polygons_circles_svg_iteration_template)
            .enter()
            .append('circle')
            .attr('r', 10.0)
            .attr('cx', function(d) { return d[0];  })
            .attr('cy', function(d) { return d[1]; })
            .attr('corner', function(d) { return d[2]; })
            .attr('template_number', function(d) { return d[3]; })
            .style('cursor', 'pointer')
            .style('fill', 'red');

        focus.selectAll('circle')
                .call(drag);
    }

    function draw_polygons_svg_plots_labeled(svg_div_id, from_manual_assign, gcp_template_allow_drag_corner, alert_plot_names_assigned) {
        console.log(drone_imagery_plot_polygons_display);
        console.log(plot_polygons_plot_names_colors);

        d3.selectAll("path").remove();
        d3.selectAll("text").remove();
        d3.selectAll("circle").remove();
        d3.selectAll("rect").remove();

        var svg = d3.select('#'+svg_div_id).select("svg");

        var draw_polygons_svg_plots_labeled_min_x = 1000000000000000;
        var draw_polygons_svg_plots_labeled_min_y = 1000000000000000;
        var draw_polygons_svg_plots_labeled_max_x = -1000000000000000;
        var draw_polygons_svg_plots_labeled_max_y = -1000000000000000;

        var draw_polygons_svg_counter = 0;
        for (key in drone_imagery_plot_polygons_display) {
            if (drone_imagery_plot_polygons_display.hasOwnProperty(key)) {
                var plot_polygons_display_points_again = drone_imagery_plot_polygons_display[key];

                if (plot_polygons_display_points_again != undefined) {
                    var line_points = [
                        [plot_polygons_display_points_again[0].x, plot_polygons_display_points_again[0].y],
                        [plot_polygons_display_points_again[1].x, plot_polygons_display_points_again[1].y],
                        [plot_polygons_display_points_again[2].x, plot_polygons_display_points_again[2].y],
                        [plot_polygons_display_points_again[3].x, plot_polygons_display_points_again[3].y],
                        [plot_polygons_display_points_again[0].x, plot_polygons_display_points_again[0].y],
                    ];

                    if (plot_polygons_display_points_again[0].x < draw_polygons_svg_plots_labeled_min_x) {
                        draw_polygons_svg_plots_labeled_min_x = plot_polygons_display_points_again[0].x;
                    }
                    if (plot_polygons_display_points_again[0].y < draw_polygons_svg_plots_labeled_min_y) {
                        draw_polygons_svg_plots_labeled_min_y = plot_polygons_display_points_again[0].y;
                    }
                    if (plot_polygons_display_points_again[2].x > draw_polygons_svg_plots_labeled_max_x) {
                        draw_polygons_svg_plots_labeled_max_x = plot_polygons_display_points_again[2].x;
                    }
                    if (plot_polygons_display_points_again[2].y > draw_polygons_svg_plots_labeled_max_y) {
                        draw_polygons_svg_plots_labeled_max_y = plot_polygons_display_points_again[2].y;
                    }

                    var label = '';
                    var label_stroke = '';
                    var label_disp = '';
                    var rect_fill = '';
                    if (drone_imagery_plot_polygons_removed_numbers.includes(key.toString())) {
                        label = 'NA';
                        label_stroke = 'blue';
                        label_disp = 'NA';
                        rect_fill = '#D3D3D3';

                        if (from_manual_assign) {
                            draw_polygons_svg_counter = draw_polygons_svg_counter + 1;
                        }
                    }
                    else {
                        label = key;
                        label_stroke = 'red';
                        label_disp = plot_polygons_plot_names_plot_numbers[label];
                        rect_fill = plot_polygons_plot_names_colors[label];

                        draw_polygons_svg_counter = draw_polygons_svg_counter + 1;
                    }

                    focus = svg.append("g");

                    focus.append('rect')
                      .attr('x', plot_polygons_display_points_again[0].x)
                      .attr('y', plot_polygons_display_points_again[0].y)
                      .attr('width', plot_polygons_display_points_again[1].x - plot_polygons_display_points_again[0].x)
                      .attr('height', plot_polygons_display_points_again[3].y - plot_polygons_display_points_again[0].y)
                      .attr('stroke', 'black')
                      .attr('fill', rect_fill)
                      .attr('plot_name', label)
                      .style("opacity", 0.5)
                      .append("svg:title")
                          .text(label);

                    focus.append("path")
                        .datum(line_points)
                        .attr("fill", "none")
                        .attr("stroke", "steelblue")
                        .attr("stroke-linejoin", "round")
                        .attr("stroke-linecap", "round")
                        .attr("stroke-width", 4.5)
                        .attr("d", line);

                    focus.append("text")
                        .attr("x", parseInt(plot_polygons_display_points_again[0].x) + 3 )
                        .attr("y", parseInt(plot_polygons_display_points_again[0].y) + 14 )
                        .style('fill', label_stroke)
                        .style("font-size", "18px")
                        .style("font-weight", 500)
                        .attr("class", "visible")
                        .text(label_disp)
                        .append("svg:title")
                            .text(label);
                }
            }
        }

        if (gcp_template_allow_drag_corner) {
            focus = svg.append("g");
            focus.selectAll('circle')
                .data([
                    [draw_polygons_svg_plots_labeled_min_x, draw_polygons_svg_plots_labeled_min_y, 'top_left', 'black'],
                    //[draw_polygons_svg_plots_labeled_max_x, draw_polygons_svg_plots_labeled_max_y, 'bottom_right', 'yellow']
                ])
                .enter()
                .append('circle')
                .attr('r', 10.0)
                .attr('cx', function(d) { return d[0];  })
                .attr('cy', function(d) { return d[1]; })
                .attr('corner', function(d) { return d[2]; })
                .style('cursor', 'pointer')
                .style('fill', function(d) { return d[3]; });

            focus.selectAll('circle')
                    .call(draggcptemplate);
        }

        if (alert_plot_names_assigned) {
            alert('Plots successfully assigned to the polygons. You can hover over the polygons to verify the plot names.');
        }
    }

    function plotPolygonsTemplatePaste(posx, posy, plot_polygon_template_id, plot_polygons_assignment_info, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button, drone_imagery_plot_polygons_active_templates) {
        var plot_polygon_template_to_paste = plot_polygons_template_dimensions[plot_polygon_template_id];

        var plot_polygons_previous_plot_polygons = plot_polygon_template_to_paste['plot_polygons'];
        plot_polygons_num_rows_generated = plot_polygon_template_to_paste['num_rows'];
        plot_polygons_num_cols_generated = plot_polygon_template_to_paste['num_cols'];

        var section_width = background_image_width;
        var section_height = background_image_height;

        var plot_polygon_top_left_position = plot_polygons_previous_plot_polygons[0][0];
        var plot_polygon_template_paste_x_diff = plot_polygon_top_left_position['x'] - posx;
        var plot_polygon_template_paste_y_diff = plot_polygon_top_left_position['y'] - posy;

        for (var i in plot_polygons_previous_plot_polygons) {
            plot_polygons_generated_polygons.push([
                {x:plot_polygons_previous_plot_polygons[i][0]['x'] - plot_polygon_template_paste_x_diff, y:plot_polygons_previous_plot_polygons[i][0]['y']- plot_polygon_template_paste_y_diff},
                {x:plot_polygons_previous_plot_polygons[i][1]['x'] - plot_polygon_template_paste_x_diff, y:plot_polygons_previous_plot_polygons[i][1]['y'] - plot_polygon_template_paste_y_diff},
                {x:plot_polygons_previous_plot_polygons[i][2]['x'] - plot_polygon_template_paste_x_diff, y:plot_polygons_previous_plot_polygons[i][2]['y'] - plot_polygon_template_paste_y_diff},
                {x:plot_polygons_previous_plot_polygons[i][3]['x'] - plot_polygon_template_paste_x_diff, y:plot_polygons_previous_plot_polygons[i][3]['y'] - plot_polygon_template_paste_y_diff}
            ]);
        }

        plot_polygons_number_generated = plot_polygons_generated_polygons.length;
        console.log(plot_polygons_generated_polygons);

        var drone_imagery_plot_polygons_new = {};
        var drone_imagery_plot_polygons_display_new = {};

        for (var i=0; i<plot_polygons_generated_polygons.length; i++) {
            plot_polygons_ind_4_points = plot_polygons_generated_polygons[i];
            plot_polygons_display_points = plot_polygons_ind_4_points;
            if (plot_polygons_display_points.length == 4) {
                plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
            }
            drawPolyline(plot_polygons_display_points);
            drawWaypoints(plot_polygons_display_points, i, 0);
            drone_imagery_plot_generated_polygons[i] = plot_polygons_ind_4_points;
            drone_imagery_plot_polygons_new[i] = plot_polygons_ind_4_points;
            drone_imagery_plot_polygons_display[i] = plot_polygons_display_points;
            drone_imagery_plot_polygons_display_new[i] = plot_polygons_display_points;
        }

        plot_polygons_template_dimensions.push({
            'num_rows':plot_polygons_num_rows_generated,
            'num_cols':plot_polygons_num_cols_generated,
            'total_plot_polygons':plot_polygons_num_rows_generated*plot_polygons_num_cols_generated,
            'plot_polygons':drone_imagery_plot_polygons_new,
            'plot_polygons_display':drone_imagery_plot_polygons_display_new
        });

        droneImageryDrawPlotPolygonActiveTemplatesTable(drone_imagery_plot_polygons_active_templates, plot_polygons_template_dimensions);
        droneImageryRectangleLayoutTable(drone_imagery_plot_generated_polygons, plot_polygons_assignment_info, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button);
        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
    }

    function plotPolygonsTemplatePasteSVG(posx, posy, plot_polygon_template_id, plot_polygons_assignment_info, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button, drone_imagery_plot_polygons_active_templates) {
        console.log(plot_polygon_template_id);
        var plot_polygon_template_to_paste = plot_polygons_template_dimensions_svg[plot_polygon_template_id];
        console.log(plot_polygon_template_to_paste);

        var plot_polygons_previous_plot_polygons = plot_polygon_template_to_paste['plot_polygons_generated_polygons_svg'];
        plot_polygons_num_rows_generated = plot_polygon_template_to_paste['num_rows'];
        plot_polygons_num_cols_generated = plot_polygon_template_to_paste['num_cols'];

        var section_width = background_image_width;
        var section_height = background_image_height;

        var plot_polygon_top_left_position = plot_polygons_previous_plot_polygons[0][0];
        var plot_polygon_template_paste_x_diff = plot_polygon_top_left_position['x'] - posx;
        var plot_polygon_template_paste_y_diff = plot_polygon_top_left_position['y'] - posy;

        var plot_polygons_generated_polygons_svg = [];
        var plot_polygons_generated_polygons_rows_svg = [];
        var plot_polygons_generated_polygons_circles_svg = [];
        for (var i in plot_polygons_previous_plot_polygons) {
            var tl_x = plot_polygons_previous_plot_polygons[i][0]['x'] - plot_polygon_template_paste_x_diff;
            var tl_y = plot_polygons_previous_plot_polygons[i][0]['y']- plot_polygon_template_paste_y_diff;
            var tr_x = plot_polygons_previous_plot_polygons[i][1]['x'] - plot_polygon_template_paste_x_diff;
            var tr_y = plot_polygons_previous_plot_polygons[i][1]['y'] - plot_polygon_template_paste_y_diff;
            var br_x = plot_polygons_previous_plot_polygons[i][2]['x'] - plot_polygon_template_paste_x_diff;
            var br_y = plot_polygons_previous_plot_polygons[i][2]['y'] - plot_polygon_template_paste_y_diff;
            var bl_x = plot_polygons_previous_plot_polygons[i][3]['x'] - plot_polygon_template_paste_x_diff;
            var bl_y = plot_polygons_previous_plot_polygons[i][3]['y'] - plot_polygon_template_paste_y_diff;

            plot_polygons_generated_polygons_svg.push([
                {x:tl_x, y:tl_y},
                {x:tr_x, y:tr_y},
                {x:br_x, y:br_y},
                {x:bl_x, y:bl_y}
            ]);

            var row_svg = [];
            row_svg.push([tl_x, tl_y]);
            row_svg.push([tr_x, tr_y]);
            row_svg.push([br_x, br_y]);
            row_svg.push([bl_x, bl_y]);
            row_svg.push([tl_x, tl_y]);
            plot_polygons_generated_polygons_rows_svg.push(row_svg);
        }

        plot_polygons_number_generated = plot_polygons_generated_polygons_svg.length;
        console.log(plot_polygons_generated_polygons_svg);

        var drone_imagery_plot_generated_polygons_new = [];
        var drone_imagery_plot_polygons_display_new = [];

        for (var i=0; i<plot_polygons_generated_polygons_svg.length; i++) {
            plot_polygons_ind_4_points = plot_polygons_generated_polygons_svg[i];
            plot_polygons_display_points = plot_polygons_ind_4_points;
            if (plot_polygons_display_points.length == 4) {
                plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
            }
            drone_imagery_plot_generated_polygons_new.push(plot_polygons_ind_4_points);
            drone_imagery_plot_polygons_display_new.push(plot_polygons_display_points);
        }

        plot_polygons_template_dimensions_svg.push({
            'template_number':plot_polygons_template_dimensions_template_number_svg,
            'num_rows':plot_polygons_num_rows_generated,
            'num_cols':plot_polygons_num_cols_generated,
            'num_rows_val':plot_polygons_num_rows_generated.toString(),
            'num_cols_val':plot_polygons_num_cols_generated.toString(),
            'section_top_row_left_offset_val':plot_polygon_template_to_paste['section_top_row_left_offset_val'] - plot_polygon_template_paste_x_diff,
            'section_bottom_row_left_offset_val':plot_polygon_template_to_paste['section_bottom_row_left_offset_val'] - plot_polygon_template_paste_x_diff,
            'section_left_column_top_offset_val':plot_polygon_template_to_paste['section_left_column_top_offset_val'] - plot_polygon_template_paste_y_diff,
            'section_left_column_bottom_offset_val':plot_polygon_template_to_paste['section_left_column_bottom_offset_val'] - plot_polygon_template_paste_y_diff,
            'section_top_row_right_offset_val':plot_polygon_template_to_paste['section_top_row_right_offset_val'] - plot_polygon_template_paste_x_diff,
            'section_right_column_bottom_offset_val':plot_polygon_template_to_paste['section_right_column_bottom_offset_val'] - plot_polygon_template_paste_y_diff,
            'total_plot_polygons':plot_polygons_num_rows_generated*plot_polygons_num_cols_generated,
            'drone_imagery_plot_generated_polygons':drone_imagery_plot_generated_polygons_new,
            'drone_imagery_plot_polygons_display':drone_imagery_plot_polygons_display_new,
            'plot_polygons_generated_polygons_svg':plot_polygons_generated_polygons_svg,
            'plot_polygons_generated_polygons_rows_svg':plot_polygons_generated_polygons_rows_svg,
            'plot_polygons_generated_polygons_circles_svg':plot_polygons_generated_polygons_circles_svg
        });
        console.log(plot_polygons_template_dimensions_svg);

        plot_polygons_template_dimensions_template_number_svg = plot_polygons_template_dimensions_template_number_svg + 1;

        draw_polygons_svg('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg');
        droneImageryDrawPlotPolygonActiveTemplatesTableSVG('drone_imagery_standard_process_plot_polygons_active_templates', plot_polygons_template_dimensions_svg);
        droneImageryRectangleLayoutTable(drone_imagery_plot_generated_polygons, plot_polygons_assignment_info, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button);
        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
    }

    function plotPolygonsTemplatePasteRawImage(posx, posy, polygon) {
        var plot_polygon_top_left_position = polygon[0];
        var plot_polygon_template_paste_x_diff = plot_polygon_top_left_position['x'] - posx;
        var plot_polygon_template_paste_y_diff = plot_polygon_top_left_position['y'] - posy;

        crop_points = [
            {x:polygon[0]['x'] - plot_polygon_template_paste_x_diff, y:polygon[0]['y'] - plot_polygon_template_paste_y_diff},
            {x:polygon[1]['x'] - plot_polygon_template_paste_x_diff, y:polygon[1]['y'] - plot_polygon_template_paste_y_diff},
            {x:polygon[2]['x'] - plot_polygon_template_paste_x_diff, y:polygon[2]['y'] - plot_polygon_template_paste_y_diff},
            {x:polygon[3]['x'] - plot_polygon_template_paste_x_diff, y:polygon[3]['y'] - plot_polygon_template_paste_y_diff}
        ];

        plot_polygons_ind_4_points = JSON.parse(JSON.stringify(crop_points));
        plot_polygons_display_points = plot_polygons_ind_4_points;
        if (plot_polygons_display_points.length == 4) {
            plot_polygons_display_points.push(plot_polygons_ind_4_points[0]);
        }
        drawPolyline(plot_polygons_display_points);
        drawWaypoints(plot_polygons_display_points, 1, 0);
    }

    function droneImageryDrawPlotPolygonActiveTemplatesTable(div_id, plot_polygons_template_dimensions){
        var html = '<table class="table table-bordered table-hover"><thead><tr><th>Template Number</th><th>Rows</th><th>Columns</th><th>Total Polygons</th><th>Options</th></tr></thead><tbody>';
        for (var i=0; i<plot_polygons_template_dimensions.length; i++) {
            html = html + '<tr><td>'+i+'</td><td>'+plot_polygons_template_dimensions[i]['num_rows']+'</td><td>'+plot_polygons_template_dimensions[i]['num_cols']+'</td><td>'+plot_polygons_template_dimensions[i]['total_plot_polygons']+'</td><td><button class="btn btn-sm btn-primary" name="drone_imagery_plot_polygon_template_options" data-plot_polygon_template_id="'+i+'" >Options</button></td></tr>';
        }
        html = html + '</tbody></table>';
        jQuery('#'+div_id).html(html);
    }

    function droneImageryDrawPlotPolygonActiveTemplatesTableSVG(div_id, plot_polygons_template_dimensions_svg){
        var html = '<table class="table table-bordered table-hover"><thead><tr><th>Template Number</th><th>Rows</th><th>Columns</th><th>Total Polygons</th><th>Options</th></tr></thead><tbody>';
        for (var i=0; i<plot_polygons_template_dimensions_svg.length; i++) {
            if (!plot_polygons_template_dimensions_deleted_templates_svg.includes(i)) {
                html = html + '<tr><td>'+plot_polygons_template_dimensions_svg[i]['template_number']+'</td><td>'+plot_polygons_template_dimensions_svg[i]['num_rows']+'</td><td>'+plot_polygons_template_dimensions_svg[i]['num_cols']+'</td><td>'+plot_polygons_template_dimensions_svg[i]['total_plot_polygons']+'</td><td><button class="btn btn-sm btn-primary" name="drone_imagery_plot_polygon_template_options" data-plot_polygon_template_id="'+plot_polygons_template_dimensions_svg[i]['template_number']+'" >Options</button></td></tr>';
            }
        }
        html = html + '</tbody></table>';
        jQuery('#'+div_id).html(html);
    }

    var drone_imagery_current_plot_polygon_index_options_id = '';
    jQuery(document).on('click', 'button[name="drone_imagery_plot_polygon_template_options"]', function(){
        jQuery('#drone_imagery_plot_polygon_template_options_dialog').modal('show');
        drone_imagery_current_plot_polygon_index_options_id = jQuery(this).data('plot_polygon_template_id');
    });

    jQuery('#drone_imagery_plot_polygon_template_options_paste_click').click(function(){
        jQuery('#drone_imagery_plot_polygon_template_options_dialog').modal('hide');
        alert('Click on where the top left corner of the template will be pasted.');
        drone_imagery_plot_polygon_click_type = 'plot_polygon_template_paste';
    });

    jQuery('#drone_imagery_plot_polygon_template_options_remove_click').click(function(){
        plot_polygons_template_dimensions_deleted_templates_svg.push(parseInt(drone_imagery_current_plot_polygon_index_options_id));

        draw_polygons_svg('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg');
        droneImageryDrawPlotPolygonActiveTemplatesTableSVG('drone_imagery_standard_process_plot_polygons_active_templates', plot_polygons_template_dimensions_svg);
        droneImageryRectangleLayoutTable(drone_imagery_plot_generated_polygons, 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');

        jQuery('#drone_imagery_plot_polygon_template_options_dialog').modal('hide');
    });

    jQuery('input[name=drone_imagery_plot_polygons_autocomplete]').autocomplete({
        source: drone_imagery_plot_polygons_available_stock_names
    });

    jQuery(document).on('click', '#drone_imagery_plot_polygons_clear', function(){
        plot_polygons_display_points = [];
        plot_polygons_ind_points = [];
        plot_polygons_ind_4_points = [];
        drone_imagery_plot_polygons = {};
        drone_imagery_plot_polygons_plot_names = {};
        drone_imagery_plot_generated_polygons = {};
        drone_imagery_plot_polygons_display = {};
        plot_polygons_plot_names_colors = {};
        plot_polygons_plot_names_plot_numbers = {};
        plot_polygons_generated_polygons = [];
        drone_imagery_plot_generated_polygons = [];
        plot_polygons_template_dimensions = [];
        drone_imagery_plot_polygons_removed_numbers = [];
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        draw_canvas_image(background_image_url, 0);
        jQuery('#drone_imagery_generated_polygons_div').html('');
        droneImageryDrawLayoutTable(field_trial_layout_response, drone_imagery_plot_polygons, 'drone_imagery_trial_layout_div', 'drone_imagery_layout_table');
        droneImageryDrawPlotPolygonActiveTemplatesTable("drone_imagery_plot_polygons_active_templates", plot_polygons_template_dimensions);
        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
    });

    jQuery(document).on('click', '#drone_imagery_plot_polygons_clear_one', function(){
        jQuery('#drone_imagery_plot_polygon_remove_polygon').modal('show');
        return false;
    });

    jQuery("#drone_imagery_plot_polygon_remove_polygon_form").submit( function() {
        event.preventDefault();
        var polygon_number = jQuery('#drone_imagery_plot_polygon_remove_polygon_number').val();
        drone_imagery_plot_polygons_removed_numbers.push(polygon_number);

        draw_polygons_svg('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg');

        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
        return false;
    });

    jQuery('#drone_imagery_plot_polygon_remove_polygon_submit').click(function(){
        var polygon_number = jQuery('#drone_imagery_plot_polygon_remove_polygon_number').val();
        drone_imagery_plot_polygons_removed_numbers.push(polygon_number);

        draw_polygons_svg('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg');

        plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
        return false;
    });

    function draw_canvas_image(image_url, random_scaling) {
        var image = new Image();
        image.onload = function () {
            canvas.width = this.naturalWidth;
            canvas.height = this.naturalHeight;
            ctx.drawImage(this, 0, 0);

            for (key in drone_imagery_plot_polygons_display) {
                if (drone_imagery_plot_polygons_display.hasOwnProperty(key)) {
                    var plot_polygons_display_points_again = drone_imagery_plot_polygons_display[key];
                    drawPolyline(plot_polygons_display_points_again);
                    drawWaypoints(plot_polygons_display_points_again, key, random_scaling);
                }
            }
        };
        image.src = image_url;
    }

    function GetCoordinatesPlotPolygons(e) {
        var PosX = 0;
        var PosY = 0;
        var ImgPos;
        ImgPos = FindPosition(plotpolygonsImg);
        if (!e) var e = window.event;
        if (e.pageX || e.pageY) {
            PosX = e.pageX;
            PosY = e.pageY;
        }
        else if (e.clientX || e.clientY) {
            PosX = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
            PosY = e.clientY + document.body.scrollTop + document.documentElement.scrollTop;
        }
        PosX = PosX - ImgPos[0];
        PosY = PosY - ImgPos[1];
        if (plot_polygons_ind_points.length <= 4){
            plot_polygons_ind_points.push({x:PosX, y:PosY});
            plot_polygons_display_points.push({x:PosX, y:PosY});

            if (plot_polygons_ind_points.length == 4) {
                plot_polygons_ind_4_points = plot_polygons_ind_points;
            }
        } else if (plot_polygons_ind_points.length > 4) {
            if (plot_polygons_display_points.length == 5) {
                jQuery('#drone_imagery_assign_plot_dialog').modal('show');
            }
            plot_polygons_ind_points = [];
        }
        drawPolyline(plot_polygons_display_points);
        drawWaypoints(plot_polygons_display_points, undefined, 0);
    }

    var plot_polygons_get_distance_point_1x = '';
    var plot_polygons_get_distance_point_1y = '';

    function GetCoordinatesPlotPolygonsPoint(e) {
        var PosX = 0;
        var PosY = 0;
        var ImgPos;
        ImgPos = FindPosition(plotpolygonsImg);
        if (!e) var e = window.event;
        if (e.pageX || e.pageY) {
            PosX = e.pageX;
            PosY = e.pageY;
        }
        else if (e.clientX || e.clientY) {
            PosX = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
            PosY = e.clientY + document.body.scrollTop + document.documentElement.scrollTop;
        }
        PosX = PosX - ImgPos[0];
        PosY = PosY - ImgPos[1];

        if (drone_imagery_plot_polygon_click_type == '' && drone_imagery_standard_process_plot_polygon_click_type == '') {
            alert('X Coordinate: '+PosX+'. Y Coordinate: '+PosY+'.');
        }
        else if (drone_imagery_plot_polygon_click_type == 'top_left') {
            drone_imagery_plot_polygon_click_type = '';
            jQuery('#drone_imagery_plot_polygons_left_column_top_offset').val(PosY);
            jQuery('#drone_imagery_plot_polygons_top_row_left_offset').val(PosX);
        }
        else if (drone_imagery_plot_polygon_click_type == 'top_right') {
            drone_imagery_plot_polygon_click_type = '';
            jQuery('#drone_imagery_plot_polygons_top_row_right_offset').val(background_image_width-PosX);
        }
        else if (drone_imagery_plot_polygon_click_type == 'bottom_left') {
            drone_imagery_plot_polygon_click_type = '';
            jQuery('#drone_imagery_plot_polygons_bottom_row_left_offset').val(PosX);
            jQuery('#drone_imagery_plot_polygons_left_column_bottom_offset').val(background_image_height-PosY);
        }
        else if (drone_imagery_plot_polygon_click_type == 'bottom_right') {
            drone_imagery_plot_polygon_click_type = '';
            jQuery('#drone_imagery_plot_polygons_right_col_bottom_offset').val(background_image_height-PosY);
        }
        else if (drone_imagery_plot_polygon_click_type == 'get_distance') {
            if (plot_polygons_get_distance_point_1x != '') {
                var distance = Math.round(Math.sqrt(Math.pow(plot_polygons_get_distance_point_1x - PosX, 2) + Math.pow(plot_polygons_get_distance_point_1y - PosY, 2)));
                alert('Distance='+distance+'. X1='+plot_polygons_get_distance_point_1x+'. Y1='+plot_polygons_get_distance_point_1y+'. X2='+PosX+'. Y2='+PosY);
                plot_polygons_get_distance_point_1x = '';
                plot_polygons_get_distance_point_1y = '';
                drone_imagery_plot_polygon_click_type = '';
            } else {
                plot_polygons_get_distance_point_1x = PosX;
                plot_polygons_get_distance_point_1y = PosY;
            }
        }
        else if (drone_imagery_plot_polygon_click_type == 'plot_polygon_template_paste') {
            drone_imagery_plot_polygon_click_type = '';

            if (manage_drone_imagery_standard_process_field_trial_id == undefined) {
                plotPolygonsTemplatePaste(PosX, PosY, parseInt(drone_imagery_current_plot_polygon_index_options_id), 'drone_imagery_generated_polygons_div', 'drone_imagery_plot_polygons_generated_assign', 'drone_imagery_plot_polygons_submit_bottom');
            }
            else {
                plotPolygonsTemplatePaste(PosX, PosY, parseInt(drone_imagery_current_plot_polygon_index_options_id), 'drone_imagery_standard_process_generated_polygons_div', 'drone_imagery_standard_process_plot_polygons_generated_assign', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
            }
            plotPolygonManualAssignPlotNumberTableStandard('drone_imagery_standard_process_generated_polygons_table', 'drone_imagery_standard_process_generated_polygons_table_id', 'drone_imagery_standard_process_generated_polygons_table_input', 'drone_imagery_standard_process_generated_polygons_table_input_generate_button', 'drone_imagery_standard_process_plot_polygons_submit_bottom');
        }
        else if (drone_imagery_standard_process_plot_polygon_click_type == 'top_left') {
            drone_imagery_standard_process_plot_polygon_click_type = '';
            jQuery('#drone_imagery_standard_process_plot_polygons_left_column_top_offset').val(PosY);
            jQuery('#drone_imagery_standard_process_plot_polygons_top_row_left_offset').val(PosX);
        }
        else if (drone_imagery_standard_process_plot_polygon_click_type == 'top_right') {
            drone_imagery_standard_process_plot_polygon_click_type = '';
            jQuery('#drone_imagery_standard_process_plot_polygons_top_row_right_offset').val(background_image_width-PosX);
        }
        else if (drone_imagery_standard_process_plot_polygon_click_type == 'bottom_left') {
            drone_imagery_standard_process_plot_polygon_click_type = '';
            jQuery('#drone_imagery_standard_process_plot_polygons_bottom_row_left_offset').val(PosX);
            jQuery('#drone_imagery_standard_process_plot_polygons_left_column_bottom_offset').val(background_image_height-PosY);
        }
        else if (drone_imagery_standard_process_plot_polygon_click_type == 'bottom_right') {
            drone_imagery_standard_process_plot_polygon_click_type = '';
            jQuery('#drone_imagery_standard_process_plot_polygons_right_col_bottom_offset').val(background_image_height-PosY);
        }
        else if (drone_imagery_standard_process_plot_polygon_click_type == 'get_distance') {
            if (plot_polygons_get_distance_point_1x != '') {
                var distance = Math.round(Math.sqrt(Math.pow(plot_polygons_get_distance_point_1x - PosX, 2) + Math.pow(plot_polygons_get_distance_point_1y - PosY, 2)));
                alert('Distance='+distance+'. X1='+plot_polygons_get_distance_point_1x+'. Y1='+plot_polygons_get_distance_point_1y+'. X2='+PosX+'. Y2='+PosY);
                plot_polygons_get_distance_point_1x = '';
                plot_polygons_get_distance_point_1y = '';
                drone_imagery_plot_polygon_click_type = '';
            } else {
                plot_polygons_get_distance_point_1x = PosX;
                plot_polygons_get_distance_point_1y = PosY;
            }
        }
        else if (drone_imagery_plot_polygon_click_type == 'save_ground_control_point') {
            //alert('X Coordinate: '+PosX+'. Y Coordinate: '+PosY+'.');
            jQuery('#project_drone_imagery_ground_control_points_form_input_x_pos').val(PosX);
            jQuery('#project_drone_imagery_ground_control_points_form_input_y_pos').val(PosY);
            jQuery('#project_drone_imagery_ground_control_points_form_dialog').modal('show');
        }
    }

    jQuery('#drone_imagery_assign_plot_dialog').on('shown.bs.modal', function (e) {
        jQuery("#drone_imagery_plot_polygon_assign_plot_name").focus();
    });

    jQuery('#drone_imagery_assign_plot_dialog').on('hide.bs.modal', function (e) {
        drawPolyline(plot_polygons_display_points);
        drawWaypoints(plot_polygons_display_points, plot_polygon_name, 0);
        drone_imagery_plot_polygons_display[plot_polygon_name] = plot_polygons_display_points;
        plot_polygons_display_points = [];
    });

    jQuery('#drone_imagery_plot_polygon_assign_add').click(function(){
        plot_polygon_name = jQuery('#drone_imagery_plot_polygon_assign_plot_name').val();
        if (plot_polygon_name == ''){
            alert('Please give a name name (plot name, plant name, etc)');
        }
        drone_imagery_plot_polygons[plot_polygon_name] = plot_polygons_ind_4_points;
        jQuery('#drone_imagery_assign_plot_dialog').modal('hide');
        console.log(drone_imagery_plot_polygons);
        droneImageryDrawLayoutTable(field_trial_layout_response, drone_imagery_plot_polygons, 'drone_imagery_trial_layout_div', 'drone_imagery_layout_table');
    });

    jQuery('#drone_imagery_assign_plot_form').on('keyup keypress', function(e) {
        var keyCode = e.keyCode || e.which;
        if (keyCode === 13) {
            e.preventDefault();
            jQuery("#drone_imagery_plot_polygon_assign_add").trigger( "click" );
            return false;
        }
    });

    jQuery(document).on('click', 'button[name=drone_imagery_plot_polygons_submit_bottom]', function(){

        jQuery('input[name="drone_imagery_plot_polygons_autocomplete"]').each(function() {
            var stock_name = this.value;
            if (stock_name != '') {
                var polygon = drone_imagery_plot_generated_polygons[jQuery(this).data('generated_polygon_key')];
                drone_imagery_plot_polygons[stock_name] = polygon;
            }
        });

        submit_assignment_plot_polygons();
    });

    function submit_assignment_plot_polygons() {
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/assign_plot_polygons',
            dataType: "json",
            data: {
                'image_id': background_removed_stitched_image_id,
                'drone_run_band_project_id': drone_run_band_project_id,
                'stock_polygons': JSON.stringify(drone_imagery_plot_polygons),
                'assign_plot_polygons_type': assign_plot_polygons_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                }

                jQuery("#working_modal").modal("hide");
                location.reload();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error saving assigned plot polygons!')
            }
        });
    }

    jQuery(document).on('click', '#drone_imagery_plot_polygons_generated_assign', function() {
        generatePlotPolygonAssignments('drone_imagery_trial_layout_div', 'drone_imagery_layout_table');

        jQuery('input[name="drone_imagery_plot_polygons_autocomplete"]').each(function() {
            var stock_name = this.value;
            if (stock_name != '') {
                var polygon = drone_imagery_plot_generated_polygons[jQuery(this).data('generated_polygon_key')];
                drone_imagery_plot_polygons[stock_name] = polygon;
            }
        });
    });

    jQuery(document).on('click', '#drone_imagery_standard_process_generated_polygons_table_input_generate_button', function(){
        generatePlotPolygonAssignmentsStandardManualSVG('drone_imagery_standard_process_trial_layout_div_0', 'drone_imagery_standard_process_layout_table_0');
    });

    function generatePlotPolygonAssignmentsStandardManual(trial_layout_div, trial_layout_table) {
        var plot_polygons_layout = field_trial_layout_response.output;
        var plot_polygons_plot_numbers = [];
        var plot_polygons_plot_numbers_plot_names = {};
        for (var i=1; i<plot_polygons_layout.length; i++) {
            var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
            plot_polygons_plot_numbers.push(plot_polygons_plot_number);
            plot_polygons_plot_numbers_plot_names[plot_polygons_plot_number] = plot_polygons_layout[i][0];
        }

        var plot_polygon_new_display = {};
        jQuery('input[name="drone_imagery_standard_process_generated_polygons_table_input"]').each(function() {
            var plot_number = jQuery(this).val();
            var polygon_number = jQuery(this).data('polygon_number');

            if (drone_imagery_plot_polygons_removed_numbers.includes(polygon_number.toString())) {
                console.log("Skipping "+polygon_number);
                plot_polygon_new_display[polygon_number] = drone_imagery_plot_polygons_display[polygon_number];
            } else {
                plot_polygon_new_display[plot_polygons_plot_numbers_plot_names[plot_number]] = drone_imagery_plot_polygons_display[polygon_number];
                drone_imagery_plot_polygons[plot_polygons_plot_numbers_plot_names[plot_number]] = drone_imagery_plot_generated_polygons[polygon_number];
            }
        });

        droneImageryDrawLayoutTable(field_trial_layout_response, drone_imagery_plot_polygons, trial_layout_div, trial_layout_table);

        drone_imagery_plot_polygons_display = plot_polygon_new_display;
        draw_canvas_image(background_image_url, plot_polygons_total_height_generated/plot_polygons_num_rows_generated);
    }

    function generatePlotPolygonAssignmentsStandardManualSVG(trial_layout_div, trial_layout_table) {
        var plot_polygons_plot_numbers = [];
        var plot_polygons_plot_numbers_plot_names = {};
        var plot_polygons_field_trial_names_order = field_trial_layout_response_names;

        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
            plot_polygons_plot_numbers_plot_names[plot_polygons_field_trial_names_order_current] = {};
            drone_imagery_plot_polygons_plot_names[plot_polygons_field_trial_names_order_current] = {};
        }

        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
            var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];
            var plot_polygons_layout = field_trial_layout_response_current.output;
            for (var i=1; i<plot_polygons_layout.length; i++) {
                var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
                plot_polygons_plot_numbers.push(plot_polygons_plot_number);
                plot_polygons_plot_numbers_plot_names[plot_polygons_field_trial_names_order_current][plot_polygons_plot_number] = plot_polygons_layout[i][0];
            }
        }

        var plot_polygon_assign_manual_polygon_numbers_ordered = [];
        var plot_polygon_assign_manual_plot_numbers_ordered = [];
        var plot_polygon_assign_manual_field_trial_ordered = [];

        jQuery('input[name="drone_imagery_standard_process_generated_polygons_table_input"]').each(function() {
            var plot_number = jQuery(this).val();
            var polygon_number = jQuery(this).data('polygon_number');
            plot_polygon_assign_manual_polygon_numbers_ordered.push(polygon_number);
            plot_polygon_assign_manual_plot_numbers_ordered.push(plot_number);
        });

        jQuery('select[name="drone_imagery_standard_process_generated_polygons_table_input_field_trial"]').each(function() {
            var field_trial = jQuery(this).val();
            var polygon_number = jQuery(this).data('polygon_number');
            plot_polygon_assign_manual_field_trial_ordered.push(field_trial);
        });

        var plot_polygon_new_display = {};
        for (var i=0; i<plot_polygon_assign_manual_polygon_numbers_ordered.length; i++) {
            var polygon_number = plot_polygon_assign_manual_polygon_numbers_ordered[i];
            var plot_number = plot_polygon_assign_manual_plot_numbers_ordered[i];
            var field_trial = plot_polygon_assign_manual_field_trial_ordered[i];
            console.log([polygon_number, plot_number, field_trial]);

            if (plot_number != '') {
                if (drone_imagery_plot_polygons_removed_numbers.includes(polygon_number.toString())) {
                    console.log("Skipping "+polygon_number);
                    plot_polygon_new_display[polygon_number] = drone_imagery_plot_polygons_display[polygon_number];
                } else {
                    plot_polygon_new_display[plot_polygons_plot_numbers_plot_names[field_trial][plot_number]] = drone_imagery_plot_polygons_display[polygon_number];
                    drone_imagery_plot_polygons[plot_polygons_plot_numbers_plot_names[field_trial][plot_number]] = drone_imagery_plot_generated_polygons[polygon_number];
                    drone_imagery_plot_polygons_plot_names[field_trial][polygon_number] = plot_polygons_plot_numbers_plot_names[field_trial][plot_number];
                }
            }
        }
        drone_imagery_plot_polygons_display = plot_polygon_new_display;

        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
            var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];
            droneImageryDrawLayoutTable(field_trial_layout_response_current, drone_imagery_plot_polygons, trial_layout_div+'_'+plot_polygons_field_trial_name_iterator, trial_layout_table+'_'+plot_polygons_field_trial_name_iterator);
        }


        plot_polygons_plot_names_colors = {};
        plot_polygons_plot_names_plot_numbers = {};

        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
            var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];

            var randomColor = '#'+Math.floor(Math.random()*16777215).toString(16);

            var plot_polygons_layout = field_trial_layout_response_current.output;
            for (var i=1; i<plot_polygons_layout.length; i++) {
                var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
                var plot_polygons_plot_name = plot_polygons_layout[i][0];

                plot_polygons_plot_names_colors[plot_polygons_plot_name] = randomColor;
                plot_polygons_plot_names_plot_numbers[plot_polygons_plot_name] = plot_polygons_plot_number;
            }
        }

        draw_polygons_svg_plots_labeled('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg', 1, undefined, 1);
    }

    function generatePlotPolygonAssignments(trial_layout_div, trial_layout_table) {
        var plot_polygons_first_plot_start = jQuery('#drone_imagery_plot_polygons_first_plot_start').val();
        var plot_polygons_second_plot_follows = jQuery('#drone_imagery_plot_polygons_second_plot_follows').val();
        var plot_polygons_plot_orientation = jQuery('#drone_imagery_plot_polygons_plot_orientation').val();
        var plot_polygons_field_trial_names_order_string = jQuery('#drone_imagery_plot_polygons_field_trial_names_order').val();

        if (plot_polygons_field_trial_names_order_string == '') {
            alert('Please fill in the order of the field trials!');
            return false;
        }
        var plot_polygons_field_trial_names_order = plot_polygons_field_trial_names_order_string.split(',');

        var plot_polygons_plot_numbers = [];
        var plot_polygons_plot_numbers_field_trial_name = [];
        var plot_polygons_plot_numbers_plot_names = {};
        plot_polygons_plot_names_colors = {};
        plot_polygons_plot_names_plot_numbers = {};

        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];

            plot_polygons_plot_numbers_plot_names[plot_polygons_field_trial_names_order_current] = {};
            drone_imagery_plot_polygons_plot_names[plot_polygons_field_trial_names_order_current] = {};
        }

        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
            var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];

            var randomColor = '#'+Math.floor(Math.random()*16777215).toString(16);

            var plot_polygons_layout = field_trial_layout_response_current.output;
            var plot_polygons_plot_numbers_field_trial_current = [];
            var plot_polygons_plot_numbers_current = [];
            for (var i=1; i<plot_polygons_layout.length; i++) {
                var plot_polygons_plot_number = Number(plot_polygons_layout[i][2]);
                var plot_polygons_plot_name = plot_polygons_layout[i][0];

                plot_polygons_plot_numbers_current.push(plot_polygons_plot_number);
                plot_polygons_plot_numbers_field_trial_current.push(plot_polygons_field_trial_names_order_current);

                plot_polygons_plot_numbers_plot_names[plot_polygons_field_trial_names_order_current][plot_polygons_plot_number] = plot_polygons_plot_name;
                plot_polygons_plot_names_colors[plot_polygons_plot_name] = randomColor;
                plot_polygons_plot_names_plot_numbers[plot_polygons_plot_name] = plot_polygons_plot_number;
            }

            plot_polygons_plot_numbers_current = plot_polygons_plot_numbers_current.sort(function (a, b) {  return a - b;  });
            plot_polygons_plot_numbers = plot_polygons_plot_numbers.concat(plot_polygons_plot_numbers_current);
            plot_polygons_plot_numbers_field_trial_name = plot_polygons_plot_numbers_field_trial_name.concat(plot_polygons_plot_numbers_field_trial_current);
        }
        console.log(plot_polygons_plot_numbers);
        console.log(plot_polygons_plot_numbers_field_trial_name);
        console.log(plot_polygons_plot_numbers_plot_names);

        var plot_polygons_current_plot_number_index = 0;

        var plot_polygons_template_index = 0;
        var plot_polygons_template_current = plot_polygons_template_dimensions_svg[plot_polygons_template_index];
        var plot_polygons_template_current_num_cols = plot_polygons_template_current.num_cols;
        var plot_polygons_template_current_num_rows = plot_polygons_template_current.num_rows;
        var plot_polygons_template_current_total_plot_polygons = plot_polygons_template_current.total_plot_polygons;
        var plot_polygons_template_current_plot_polygon_index = 0;

        var plot_polygon_new_display = {};
        if (plot_polygons_first_plot_start == 'top_left') {
            var generated_polygon_key_first_plot_number = 0;
            if (plot_polygons_second_plot_follows == 'left' || plot_polygons_second_plot_follows == 'up') {
                alert('Second plot cannot follow left or up from first plot if the first plot starts at the top left, because that is physically impossible.');
                return;
            }
            if (plot_polygons_second_plot_follows == 'right') {
                if (plot_polygons_plot_orientation == 'zigzag') {
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    for (var j=generated_polygon_key_first_plot_number; j<plot_polygons_plot_numbers.length + drone_imagery_plot_polygons_removed_numbers.length; j++){
                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                            plot_polygons_template_current_plot_polygon_index = plot_polygons_template_current_plot_polygon_index + 1;
                        }
                        plot_polygon_current_polygon_index = plot_polygon_current_polygon_index + 1;

                        if (plot_polygons_template_current_plot_polygon_index == plot_polygons_template_current_total_plot_polygons) {
                            plot_polygons_template_index = plot_polygons_template_index + 1;
                            plot_polygons_template_current = plot_polygons_template_dimensions_svg[plot_polygons_template_index];
                            if (plot_polygons_template_current != undefined) {
                                plot_polygons_template_current_num_cols = plot_polygons_template_current.num_cols;
                                plot_polygons_template_current_num_rows = plot_polygons_template_current.num_rows;
                                plot_polygons_template_current_total_plot_polygons = plot_polygons_template_current.total_plot_polygons;
                                plot_polygons_template_current_plot_polygon_index = 0;
                            }
                        }
                    }
                }
                if (plot_polygons_plot_orientation == 'serpentine') {
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    var plot_polygon_column_count = 0;
                    var plot_polygon_zigzig_polygon_index = generated_polygon_key_first_plot_number;
                    var going_right = 1;
                    var plot_polygon_previous_template_plot_count = 0;
                    for (var j=generated_polygon_key_first_plot_number; j<plot_polygons_plot_numbers.length + drone_imagery_plot_polygons_removed_numbers.length; j++){

                        if (going_right == 1) {
                            plot_polygon_current_polygon_index = plot_polygon_zigzig_polygon_index;
                        }
                        if (going_right == 0) {
                            plot_polygon_current_polygon_index = plot_polygon_previous_template_plot_count + plot_polygons_template_current_num_cols - plot_polygon_column_count - 1;
                        }

                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] =  drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                            plot_polygons_template_current_plot_polygon_index = plot_polygons_template_current_plot_polygon_index + 1;
                        }

                        plot_polygon_zigzig_polygon_index = plot_polygon_zigzig_polygon_index + 1;
                        plot_polygon_column_count = plot_polygon_column_count + 1;

                        if (plot_polygon_column_count == plot_polygons_template_current_num_cols) {
                            plot_polygon_column_count = 0;
                            if (going_right == 1) {
                                going_right = 0;
                            } else {
                                going_right = 1;
                            }
                            plot_polygon_previous_template_plot_count = plot_polygon_previous_template_plot_count + plot_polygons_template_current_num_cols;
                        }

                        if (plot_polygons_template_current_plot_polygon_index == plot_polygons_template_current_total_plot_polygons) {
                            plot_polygons_template_index = plot_polygons_template_index + 1;
                            plot_polygons_template_current = plot_polygons_template_dimensions_svg[plot_polygons_template_index];
                            if (plot_polygons_template_current != undefined) {
                                plot_polygons_template_current_num_cols = plot_polygons_template_current.num_cols;
                                plot_polygons_template_current_num_rows = plot_polygons_template_current.num_rows;
                                plot_polygons_template_current_total_plot_polygons = plot_polygons_template_current.total_plot_polygons;
                                plot_polygons_template_current_plot_polygon_index = 0;
                            }
                        }
                    }
                }
            }
            if (plot_polygons_second_plot_follows == 'down') {
                alert('Down not implemented if first plot starts in top left. Please contact us or try rotating your image differently before assigning plot polygons (e.g. rotate image 90 degrees clock-wise, then first plot starts in top right and you can go left for plot assignment).');
                return;
            }
        }
        if (plot_polygons_first_plot_start == 'top_right') {
            var generated_polygon_key_first_plot_number = plot_polygons_template_current_num_cols - 1;
            if (plot_polygons_second_plot_follows == 'right' || plot_polygons_second_plot_follows == 'up') {
                alert('Second plot cannot follow right or up from first plot if the first plot starts at the top right, because that is physically impossible.');
                return;
            }
            if (plot_polygons_second_plot_follows == 'left') {
                if (plot_polygons_plot_orientation == 'zigzag') {
                    console.log(generated_polygon_key_first_plot_number);
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    var plot_polygon_column_count = 0;
                    var plot_polygon_previous_template_plot_count = 0;
                    for (var j=generated_polygon_key_first_plot_number; j<generated_polygon_key_first_plot_number + plot_polygons_plot_numbers.length + drone_imagery_plot_polygons_removed_numbers.length; j++){

                        plot_polygon_current_polygon_index = plot_polygon_previous_template_plot_count + plot_polygons_template_current_num_cols - plot_polygon_column_count - 1;

                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] =  drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] =  drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                            plot_polygons_template_current_plot_polygon_index = plot_polygons_template_current_plot_polygon_index + 1;
                        }

                        plot_polygon_column_count = plot_polygon_column_count + 1;

                        if (plot_polygon_column_count == plot_polygons_template_current_num_cols) {
                            plot_polygon_column_count = 0;
                            plot_polygon_previous_template_plot_count = plot_polygon_previous_template_plot_count + plot_polygons_template_current_num_cols;
                        }

                        if (plot_polygons_template_current_plot_polygon_index == plot_polygons_template_current_total_plot_polygons) {
                            plot_polygons_template_index = plot_polygons_template_index + 1;
                            plot_polygons_template_current = plot_polygons_template_dimensions_svg[plot_polygons_template_index];
                            if (plot_polygons_template_current != undefined) {
                                plot_polygons_template_current_num_cols = plot_polygons_template_current.num_cols;
                                plot_polygons_template_current_num_rows = plot_polygons_template_current.num_rows;
                                plot_polygons_template_current_total_plot_polygons = plot_polygons_template_current.total_plot_polygons;
                                plot_polygons_template_current_plot_polygon_index = 0;
                            }
                        }
                    }
                }
                if (plot_polygons_plot_orientation == 'serpentine') {
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    var plot_polygon_column_count = 0;
                    var plot_polygon_zigzig_polygon_index = generated_polygon_key_first_plot_number;
                    var going_left = 1;
                    var plot_polygon_previous_template_plot_count = 0;
                    for (var j=generated_polygon_key_first_plot_number; j<generated_polygon_key_first_plot_number + plot_polygons_plot_numbers.length + drone_imagery_plot_polygons_removed_numbers.length; j++){

                        if (going_left == 0) {
                            plot_polygon_current_polygon_index = plot_polygon_previous_template_plot_count + plot_polygon_column_count;
                        }
                        if (going_left == 1) {
                            plot_polygon_current_polygon_index = plot_polygon_previous_template_plot_count + plot_polygons_template_current_num_cols - plot_polygon_column_count - 1;
                        }

                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                            plot_polygons_template_current_plot_polygon_index = plot_polygons_template_current_plot_polygon_index + 1;
                        }

                        plot_polygon_zigzig_polygon_index = plot_polygon_zigzig_polygon_index + 1;
                        plot_polygon_column_count = plot_polygon_column_count + 1;

                        if (plot_polygon_column_count == plot_polygons_template_current_num_cols) {
                            plot_polygon_column_count = 0;
                            if (going_left == 1) {
                                going_left = 0;
                            } else {
                                going_left = 1;
                            }
                            plot_polygon_previous_template_plot_count = plot_polygon_previous_template_plot_count + plot_polygons_template_current_num_cols;
                        }

                        if (plot_polygons_template_current_plot_polygon_index == plot_polygons_template_current_total_plot_polygons) {
                            plot_polygons_template_index = plot_polygons_template_index + 1;
                            plot_polygons_template_current = plot_polygons_template_dimensions_svg[plot_polygons_template_index];
                            if (plot_polygons_template_current != undefined) {
                                plot_polygons_template_current_num_cols = plot_polygons_template_current.num_cols;
                                plot_polygons_template_current_num_rows = plot_polygons_template_current.num_rows;
                                plot_polygons_template_current_total_plot_polygons = plot_polygons_template_current.total_plot_polygons;
                                plot_polygons_template_current_plot_polygon_index = 0;
                            }
                        }
                    }
                }
            }
            if (plot_polygons_second_plot_follows == 'down') {
                alert('Down not implemented if your first plot starts in top right. Please contact us or try rotating your image differently before assigning plot polygons (e.g. rotate image 90 degrees counter-clockwise, then first plot starts in top left corner and plot assignment can follow going right).');
                return;
            }
        }
        if (plot_polygons_first_plot_start == 'bottom_left') {
            var generated_polygon_key_first_plot_number = plot_polygons_number_generated - (plot_polygons_num_border_rows_bottom * plot_polygons_num_cols_generated) - plot_polygons_num_border_rows_right;
            if (plot_polygons_second_plot_follows == 'left' || plot_polygons_second_plot_follows == 'down') {
                alert('Second plot cannot follow left or down from the first plot if the first plot starts at the bottom left, because that is physically impossible.');
                return;
            }
            if (plot_polygons_second_plot_follows == 'right') {
                if (plot_polygons_plot_orientation == 'serpentine') {
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    var plot_polygon_column_count = 0;
                    var going_right = 1;
                    var plot_polygon_row_count = 0;
                    for (var j=0; j<plot_polygons_plot_numbers.length; j++){

                        if (going_right == 0) {
                            plot_polygon_current_polygon_index = plot_polygons_number_generated - (plot_polygons_num_border_rows_bottom * plot_polygons_num_cols_generated) - (plot_polygon_row_count * plot_polygons_num_cols_generated) - plot_polygons_num_border_rows_right - plot_polygon_column_count - 1;
                        }
                        if (going_right == 1) {
                            plot_polygon_current_polygon_index = plot_polygons_number_generated - (plot_polygons_num_border_rows_bottom * plot_polygons_num_cols_generated) - (plot_polygon_row_count * plot_polygons_num_cols_generated) - plot_polygons_num_cols_generated + plot_polygons_num_border_rows_left + plot_polygon_column_count;
                        }

                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                        }

                        plot_polygon_column_count = plot_polygon_column_count + 1;

                        if (plot_polygon_column_count == (plot_polygons_num_cols_generated - plot_polygons_num_border_rows_left - plot_polygons_num_border_rows_right)) {
                            plot_polygon_column_count = 0;
                            plot_polygon_row_count = plot_polygon_row_count + 1;
                            if (going_right == 1) {
                                going_right = 0;
                            } else {
                                going_right = 1;
                            }
                        }
                    }
                }
                if (plot_polygons_plot_orientation == 'zigzag') {
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    var plot_polygon_column_count = 0;
                    var plot_polygon_row_count = 0;
                    for (var j=0; j<plot_polygons_plot_numbers.length; j++){

                        plot_polygon_current_polygon_index = plot_polygons_number_generated - (plot_polygons_num_border_rows_bottom * plot_polygons_num_cols_generated) - (plot_polygon_row_count * plot_polygons_num_cols_generated) - plot_polygons_num_cols_generated + plot_polygons_num_border_rows_left + plot_polygon_column_count;

                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                        }

                        plot_polygon_column_count = plot_polygon_column_count + 1;

                        if (plot_polygon_column_count == (plot_polygons_num_cols_generated - plot_polygons_num_border_rows_left - plot_polygons_num_border_rows_right)) {
                            plot_polygon_column_count = 0;
                            plot_polygon_row_count = plot_polygon_row_count + 1;
                        }
                    }
                }
            }
            if (plot_polygons_second_plot_follows == 'up') {
                alert('Up not implemented if your first plot starts in bottom left. Please contact us or try rotating your image differently before assigning plot polygons (e.g. rotate image clockwise 90 degrees, then first plot starts in top-left corner and plot assignment can follow going right).');
                return;
            }
        }
        if (plot_polygons_first_plot_start == 'bottom_right') {
            var generated_polygon_key_first_plot_number = plot_polygons_number_generated - (plot_polygons_num_border_rows_bottom * plot_polygons_num_cols_generated) - plot_polygons_num_border_rows_right - 1;
            if (plot_polygons_second_plot_follows == 'right' || plot_polygons_second_plot_follows == 'down') {
                alert('Second plot cannot follow right or down from the first plot if the first plot starts at the bottom right, because that is physically impossible.');
                return;
            }
            if (plot_polygons_second_plot_follows == 'left') {
                if (plot_polygons_plot_orientation == 'zigzag') {
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    var plot_polygon_column_count = 0;
                    for (var j=0; j<plot_polygons_plot_numbers.length; j++){

                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                        }

                        plot_polygon_current_polygon_index = plot_polygon_current_polygon_index - 1;
                        plot_polygon_column_count = plot_polygon_column_count + 1;

                        if (plot_polygon_column_count == (plot_polygons_num_cols_generated - plot_polygons_num_border_rows_left - plot_polygons_num_border_rows_right)) {
                            plot_polygon_current_polygon_index = plot_polygon_current_polygon_index - plot_polygons_num_border_rows_left - plot_polygons_num_border_rows_right;
                            plot_polygon_column_count = 0;
                        }
                    }
                }
                if (plot_polygons_plot_orientation == 'serpentine') {
                    var plot_polygon_current_polygon_index = generated_polygon_key_first_plot_number;
                    var plot_polygon_column_count = 0;
                    var plot_polygon_zigzig_polygon_index = generated_polygon_key_first_plot_number;
                    var going_left = 1;
                    var plot_polygon_row_count = 0;
                    for (var j=0; j<plot_polygons_plot_numbers.length; j++){

                        if (going_left == 1) {
                            plot_polygon_current_polygon_index = plot_polygon_zigzig_polygon_index;
                        }
                        if (going_left == 0) {
                            plot_polygon_current_polygon_index = plot_polygons_number_generated - (plot_polygons_num_border_rows_bottom * plot_polygons_num_cols_generated) - (plot_polygon_row_count * plot_polygons_num_cols_generated) - plot_polygons_num_cols_generated + plot_polygons_num_border_rows_left + plot_polygon_column_count;
                        }

                        if (drone_imagery_plot_polygons_removed_numbers.includes(plot_polygon_current_polygon_index.toString())) {
                            console.log("Skipping "+plot_polygon_current_polygon_index);
                            plot_polygon_new_display[plot_polygon_current_polygon_index] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                        } else {
                            var field_trial_name_current = plot_polygons_plot_numbers_field_trial_name[plot_polygons_current_plot_number_index];
                            var plot_number_current = plot_polygons_plot_numbers[plot_polygons_current_plot_number_index];
                            var plot_name_current = plot_polygons_plot_numbers_plot_names[field_trial_name_current][plot_number_current];

                            plot_polygon_new_display[plot_name_current] = drone_imagery_plot_polygons_display[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons[plot_name_current] = drone_imagery_plot_generated_polygons[plot_polygon_current_polygon_index];
                            drone_imagery_plot_polygons_plot_names[field_trial_name_current][plot_polygon_current_polygon_index] = plot_name_current;

                            plot_polygons_current_plot_number_index = plot_polygons_current_plot_number_index + 1;
                        }

                        plot_polygon_zigzig_polygon_index = plot_polygon_zigzig_polygon_index - 1;
                        plot_polygon_column_count = plot_polygon_column_count + 1;

                        if (plot_polygon_column_count == (plot_polygons_num_cols_generated - plot_polygons_num_border_rows_left - plot_polygons_num_border_rows_right)) {
                            plot_polygon_zigzig_polygon_index = plot_polygon_zigzig_polygon_index - plot_polygons_num_border_rows_left - plot_polygons_num_border_rows_right;
                            plot_polygon_column_count = 0;
                            plot_polygon_row_count = plot_polygon_row_count + 1;
                            if (going_left == 1) {
                                going_left = 0;
                            } else {
                                going_left = 1;
                            }
                        }
                    }
                }
            }
            if (plot_polygons_second_plot_follows == 'up') {
                alert('Up not implemented if your first plot starts in bottom right. Please contact us or try rotating your image differently before assigning plot polygons (e.g. rotate image 90 degrees clockwise, then first plot starts in bottom left corner and plot assignment can follow going right).');
                return;
            }
        }

        console.log(drone_imagery_plot_polygons);
        for (var plot_polygons_field_trial_name_iterator=0; plot_polygons_field_trial_name_iterator<plot_polygons_field_trial_names_order.length; plot_polygons_field_trial_name_iterator++) {
            var plot_polygons_field_trial_names_order_current = plot_polygons_field_trial_names_order[plot_polygons_field_trial_name_iterator];
            var field_trial_layout_response_current = field_trial_layout_responses[plot_polygons_field_trial_names_order_current];
            droneImageryDrawLayoutTable(field_trial_layout_response_current, drone_imagery_plot_polygons, trial_layout_div+'_'+plot_polygons_field_trial_name_iterator, trial_layout_table+'_'+plot_polygons_field_trial_name_iterator);
        }

        drone_imagery_plot_polygons_display = plot_polygon_new_display;
        draw_polygons_svg_plots_labeled('drone_imagery_standard_process_plot_polygons_original_stitched_div_svg', undefined, undefined, 1);
    }

    function droneImageryRectangleLayoutTable(generated_polygons, plot_polygons_layout_assignment_info, plot_polygons_generate_assignment_button, plot_polygon_assignment_submit_button) {

        var html = '<div class="panel panel-default"><div class="panel-body"><ul><li><p>Field trial plot numbers and generated numbers will be paired up in the following orders:</p><ul><li>Field Trial Plot Numbers: Field trials are ordered based on your input below and then plot numbers within each field trial follow in increasing order (e.g. 1 to 100, or 101 to 536)</li><li>Generated Polygon Numbers: Templates are considered in order of template number (e.g. 1 to 10) and then the order of the polygons follows inputs below for the location of the first plot number, the direction of the second plot number, and the orientation (serpentine or zigzag). The orientation will persist across templates.</li></ul><hr></li><li><p>If you want to skip a generated polygon, use the "Clear One Polygon" button and it will be skipped.</p><button id="drone_imagery_standard_process_plot_polygons_clear_one" class="btn btn-sm btn-warning">Clear One Polygon</button></li><hr><li><p>If the first plot number is showing at the bottom of the image, you may need to rotate the image in the previous step so that the first plot is in the top left or right of the image.</p></li><li><p>Please use Option 2 or 3 if Option 1 is not able to handle your experiments.</p></li></ul></div></div>';
        html = html + '<div class="panel panel-default"><div class="panel-body"><div class="form form-horizontal">';

        html = html + '<div class="form-group form-group-sm"><label class="col-sm-3 control-label">Order of Field Trials: </label><div class="col-sm-9"><input class="form-control" id="drone_imagery_plot_polygons_field_trial_names_order" type="text" value="'+manage_drone_imagery_standard_process_field_trial_name;
        if (manage_drone_imagery_standard_process_field_trial_names_in_same_orthophoto.length>0) {
            html = html + ',' + manage_drone_imagery_standard_process_field_trial_names_in_same_orthophoto.join();
        }
        html = html + '" /></div></div>';

        html = html + '<div class="row"><div class="col-sm-6"><div class="form-group form-group-sm"><label class="col-sm-6 control-label">Location of First Plot Number in First Template (e.g. plot number 1): </label><div class="col-sm-6"><select class="form-control" id="drone_imagery_plot_polygons_first_plot_start" name="drone_imagery_plot_polygons_first_plot_start"><option value="top_left">Top Left</option><option value="top_right">Top Right</option><option value="bottom_left" disabled>Bottom Left</option><option value="bottom_right" disabled>Bottom Right</option></select></div></div></div><div class="col-sm-6"><div class="form-group form-group-sm"><label class="col-sm-6 control-label">Second Plot Follows First Plot Going: </label><div class="col-sm-6"><select class="form-control" id="drone_imagery_plot_polygons_second_plot_follows" name="drone_imagery_plot_polygons_second_plot_follows"><option value="right">Right</option><option value="up">Up</option><option value="down">Down</option><option value="left">Left</option></select></div></div></div></div>';
        html = html + '<div class="row"><div class="col-sm-6"><div class="form-group form-group-sm"><label class="col-sm-6 control-label">Plot Number Orientation: </label><div class="col-sm-6"><select class="form-control" id="drone_imagery_plot_polygons_plot_orientation" name="drone_imagery_plot_polygons_plot_orientation"><option value="serpentine">Serpentine</option><option value="zigzag">Zigzag (Not Serpentine)</option></select></div></div></div></div>';
        html = html + '<button class="btn btn-primary" id="'+plot_polygons_generate_assignment_button+'">Generate Assignments (Does Not Save)</button>&nbsp;&nbsp;&nbsp;<button class="btn btn-primary" name="'+plot_polygon_assignment_submit_button+'">Finish and Save Polygons To Plots</button></div>';
        html = html + '</div></div></div>';
        jQuery('#'+plot_polygons_layout_assignment_info).html(html);

        jQuery('input[name=drone_imagery_plot_polygons_autocomplete]').autocomplete({
            source: drone_imagery_plot_polygons_available_stock_names
        });
    }

    function droneImageryDrawLayoutTable(response, plot_polygons, layout_div_id, layout_table_div_id) {
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

    //
    //Remove Background Histogram
    //

    var removeBackgroundHistogramImg;
    var removeBackgroundDisplayImg;
    var removeBackgroundThresholdPeak1;
    var removeBackgroundThresholdPeak1pixels;
    var removeBackgroundThresholdPeak2;
    var removeBackgroundThresholdPeak2pixels;
    var removeBackgroundThresholdValue;
    var remove_background_denoised_stitched_image_id;
    var remove_background_current_image_id;
    var remove_background_current_image_type;
    var remove_background_drone_run_band_project_id;
    var drone_imagery_remove_background_lower_percentage = 0;
    var drone_imagery_remove_background_upper_percentage = 0;

    jQuery(document).on('click', 'button[name=project_drone_imagery_remove_background]', function(){
        showManageDroneImagerySection('manage_drone_imagery_remove_background_div');

        remove_background_denoised_stitched_image_id = jQuery(this).data('denoised_stitched_image_id');
        remove_background_drone_run_band_project_id = jQuery(this).data('drone_run_band_project_id');
        remove_background_current_image_id = jQuery(this).data('remove_background_current_image_id');
        remove_background_current_image_type = jQuery(this).data('remove_background_current_image_type');

        showRemoveBackgroundHistogramStart(remove_background_current_image_id, 'drone_imagery_remove_background_original', 'drone_imagery_remove_background_histogram_div', 'manage_drone_imagery_remove_background_load_div');
    });

    function showRemoveBackgroundHistogramStart(remove_background_current_image_id, canvas_div_id, histogram_canvas_div_id, load_div_id) {
        jQuery.ajax({
            url : '/api/drone_imagery/get_image?image_id='+remove_background_current_image_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                var canvas = document.getElementById(canvas_div_id);
                removeBackgroundDisplayImg = canvas;
                ctx = canvas.getContext('2d');
                var image = new Image();
                image.onload = function () {
                    canvas.width = this.naturalWidth;
                    canvas.height = this.naturalHeight;
                    ctx.drawImage(this, 0, 0);

                    var src = cv.imread(canvas_div_id);
                    cv.cvtColor(src, src, cv.COLOR_RGBA2GRAY, 0);
                    var srcVec = new cv.MatVector();
                    srcVec.push_back(src);
                    var accumulate = false;
                    var channels = [0];
                    var histSize = [256];
                    var ranges = [0, 255];
                    var hist = new cv.Mat();
                    var mask = new cv.Mat();
                    var color = new cv.Scalar(255, 255, 255);
                    var scale = 3;
                    var hist_height = src.rows/2;

                    cv.calcHist(srcVec, channels, mask, hist, histSize, ranges, accumulate);
                    var result = cv.minMaxLoc(hist, mask);
                    var max = result.maxVal;
                    var dst = new cv.Mat.zeros(hist_height, histSize[0] * scale, cv.CV_8UC3);
                    // draw histogram
                    for (let i = 0; i < histSize[0]; i++) {
                        var binVal = hist.data32F[i] * hist_height / max;
                        var point1 = new cv.Point(i * scale, hist_height - 1);
                        var point2 = new cv.Point((i + 1) * scale - 1, hist_height - binVal);
                        cv.rectangle(dst, point1, point2, color, cv.FILLED);
                    }
                    cv.imshow(histogram_canvas_div_id, dst);
                    src.delete(); dst.delete(); srcVec.delete(); mask.delete(); hist.delete();

                    removeBackgroundHistogramImg = document.getElementById(histogram_canvas_div_id);
                    removeBackgroundHistogramImg.onmousemove = GetCoordinatesRemoveBackgrounHistogram;
                    removeBackgroundHistogramImg.onmousedown = GetCoordinatesRemoveBackgrounHistogramDrawLine;

                    jQuery('#'+load_div_id).hide();

                };
                image.src = response.image_url;

            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving image!')
            }
        });
    }

    jQuery('#drone_imagery_remove_background_find_minimum').click(function(){
        if (!removeBackgroundThresholdPeak1 || !removeBackgroundThresholdPeak2) {
            alert('Please click on the two right-most peaks in the histogram first!');
        } else {
            showRemoveBackgroundHistogramMinimum(remove_background_current_image_id, 'drone_imagery_remove_background_original', 'drone_imagery_remove_background_histogram_div');
        }
    });

    function showRemoveBackgroundHistogramMinimum(remove_background_current_image_id, canvas_div_id, histogram_canvas_div_id) {
        jQuery.ajax({
            url : '/api/drone_imagery/get_image?image_id='+remove_background_current_image_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                var canvas = document.getElementById(canvas_div_id);
                ctx = canvas.getContext('2d');
                var image = new Image();
                image.onload = function () {
                    canvas.width = this.naturalWidth;
                    canvas.height = this.naturalHeight;
                    ctx.drawImage(this, 0, 0);

                    var src = cv.imread(canvas_div_id);
                    cv.cvtColor(src, src, cv.COLOR_RGBA2GRAY, 0);
                    var srcVec = new cv.MatVector();
                    srcVec.push_back(src);
                    var accumulate = false;
                    var channels = [0];
                    var histSize = [256];
                    var ranges = [0, 255];
                    var hist = new cv.Mat();
                    var mask = new cv.Mat();
                    var color = new cv.Scalar(255, 255, 255);
                    var scale = 3;
                    var hist_height = src.rows/2;

                    cv.calcHist(srcVec, channels, mask, hist, histSize, ranges, accumulate);
                    var result = cv.minMaxLoc(hist, mask);
                    var max = result.maxVal;
                    var dst = new cv.Mat.zeros(hist_height, histSize[0] * scale, cv.CV_8UC3);
                    // draw histogram
                    var minimum_x_val = 0;
                    var minimum_x_val_pix = 0;
                    var minimum_y_val = 1000000000000000000000000000;

                    if (removeBackgroundThresholdPeak1pixels > removeBackgroundThresholdPeak2pixels) {
                        var removeBackgroundThresholdPeak1pixels_original = removeBackgroundThresholdPeak1pixels;
                        removeBackgroundThresholdPeak1pixels = removeBackgroundThresholdPeak2pixels;
                        removeBackgroundThresholdPeak2pixels = removeBackgroundThresholdPeak1pixels_original;
                    }

                    for (let i = 0; i < histSize[0]; i++) {
                        var binVal = hist.data32F[i] * hist_height / max;

                        var x_start = i * scale;
                        if (x_start >= removeBackgroundThresholdPeak1pixels && x_start <= removeBackgroundThresholdPeak2pixels){
                            //console.log('x: '+i.toString()+' y: '+binVal.toString());
                            if (binVal < minimum_y_val) {
                                minimum_y_val = binVal;
                                minimum_x_val = i;
                                minimum_x_val_pix = x_start;
                            }
                        }

                        var point1 = new cv.Point(x_start, hist_height - 1);
                        var point2 = new cv.Point((i + 1) * scale - 1, hist_height - binVal);
                        cv.rectangle(dst, point1, point2, color, cv.FILLED);
                    }
                    cv.imshow('drone_imagery_remove_background_histogram_div', dst);
                    src.delete(); dst.delete(); srcVec.delete(); mask.delete(); hist.delete();

                    removeBackgroundHistogramImg = document.getElementById(histogram_canvas_div_id);
                    removeBackgroundHistogramImg.onmousemove = GetCoordinatesRemoveBackgrounHistogram;
                    removeBackgroundHistogramImg.onmousedown = GetCoordinatesRemoveBackgrounHistogramDrawLine;

                    jQuery('div[name="drone_imagery_remove_background_threshold"]').html('<h5>Selected Threshold Value: '+ minimum_x_val );

                    removeBackgroundHistogramImgDrawLine(removeBackgroundHistogramImg, removeBackgroundThresholdPeak1pixels, removeBackgroundHistogramImg.height, '#ff0000');
                    removeBackgroundHistogramImgDrawLine(removeBackgroundHistogramImg, removeBackgroundThresholdPeak2pixels, removeBackgroundHistogramImg.height, '#ff0000');
                    removeBackgroundHistogramImgDrawLine(removeBackgroundHistogramImg, minimum_x_val_pix, removeBackgroundHistogramImg.height, '#0000ff');

                    removeBackgroundThresholdValue = minimum_x_val;

                    removeBackgroundHistogramImgReDraw();
                };
                image.src = response.image_url;
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error retrieving image!')
            }
        });
    }

    jQuery('#drone_imagery_remove_background_start_over').click(function(){
        removeBackgroundThresholdPeak1 = undefined;
        removeBackgroundThresholdPeak2 = undefined;
        removeBackgroundThresholdPeak1pixels = undefined;
        removeBackgroundThresholdPeak2pixels = undefined;

        showRemoveBackgroundHistogramStart(remove_background_current_image_id, 'drone_imagery_remove_background_original', 'drone_imagery_remove_background_histogram_div', 'manage_drone_imagery_remove_background_load_div');
    });

    function removeBackgroundHistogramImgDrawLine(removeBackgroundHistogramImg, position, image_height, color) {
        var ctx = removeBackgroundHistogramImg.getContext("2d");
        ctx.beginPath();
        ctx.moveTo(position,0);
        ctx.lineTo(position, image_height);
        ctx.strokeStyle = color;
        ctx.stroke();
    }

    function removeBackgroundHistogramImgReDraw() {
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/remove_background_display',
            dataType: "json",
            data: {
                'image_id': remove_background_current_image_id,
                'drone_run_band_project_id': remove_background_drone_run_band_project_id,
                'lower_threshold': removeBackgroundThresholdValue,
                'upper_threshold': '255',
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                }

                var canvas = removeBackgroundDisplayImg;
                ctx = canvas.getContext('2d');
                var image = new Image();
                image.onload = function () {
                    canvas.width = this.naturalWidth;
                    canvas.height = this.naturalHeight;
                    ctx.drawImage(this, 0, 0);
                };
                image.src = response.removed_background_image_url;
            },
            error: function(response){
                alert('Error saving removed background display image!')
            }
        });
    }

    function GetCoordinatesRemoveBackgrounHistogram(e) {
        var PosX = 0;
        var PosY = 0;
        var ImgPos;
        ImgPos = FindPosition(removeBackgroundHistogramImg);
        if (!e) var e = window.event;
        if (e.pageX || e.pageY) {
            PosX = e.pageX;
            PosY = e.pageY;
        }
        else if (e.clientX || e.clientY) {
            PosX = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
            PosY = e.clientY + document.body.scrollTop + document.documentElement.scrollTop;
        }
        PosX = PosX - ImgPos[0];
        PosY = PosY - ImgPos[1];

        jQuery('div[name="drone_imagery_remove_background_threshold_current"]').html('<h5>Current Mouse Value: '+ (((PosX+1)/3)-1) );
    }

    function GetCoordinatesRemoveBackgrounHistogramDrawLine(e) {
        var PosX = 0;
        var PosY = 0;
        var image_width = removeBackgroundHistogramImg.width;
        var image_height = removeBackgroundHistogramImg.height;

        var ImgPos;
        ImgPos = FindPosition(removeBackgroundHistogramImg);
        if (!e) var e = window.event;
        if (e.pageX || e.pageY) {
            PosX = e.pageX;
            PosY = e.pageY;
        }
        else if (e.clientX || e.clientY) {
            PosX = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
            PosY = e.clientY + document.body.scrollTop + document.documentElement.scrollTop;
        }
        PosX = PosX - ImgPos[0];
        PosY = PosY - ImgPos[1];

        if (!removeBackgroundThresholdPeak1 || !removeBackgroundThresholdPeak2) {
            removeBackgroundHistogramImgDrawLine(removeBackgroundHistogramImg, PosX, image_height, '#ff0000');

            var threshold_value = Math.round( (((PosX+1)/3)-1) );
            if (removeBackgroundThresholdPeak1) {
                removeBackgroundThresholdPeak2 = threshold_value;
                removeBackgroundThresholdPeak2pixels = PosX;
            } else {
                removeBackgroundThresholdPeak1 = threshold_value;
                removeBackgroundThresholdPeak1pixels = PosX;
            }
        }
    }

    jQuery('#drone_imagery_remove_background_submit').click(function(){
        manage_drone_imagery_remove_background_threshold_save(remove_background_current_image_id, remove_background_current_image_type, remove_background_drone_run_band_project_id, removeBackgroundThresholdValue, '255');
    });

    jQuery('#drone_imagery_remove_background_defined_submit').click(function(){
        var remove_background_drone_run_band_lower_threshold = jQuery('#drone_imagery_remove_background_lower_threshold').val();
        var remove_background_drone_run_band_upper_threshold = jQuery('#drone_imagery_remove_background_upper_threshold').val();
        manage_drone_imagery_remove_background_threshold_save(remove_background_current_image_id, remove_background_current_image_type, remove_background_drone_run_band_project_id, remove_background_drone_run_band_lower_threshold, remove_background_drone_run_band_upper_threshold);
    });

    function calculateThresholdPercentageValues(canvas_div_id, drone_imagery_remove_background_lower_percentage, drone_imagery_remove_background_upper_percentage) {
        var src = cv.imread(canvas_div_id);
        cv.cvtColor(src, src, cv.COLOR_RGBA2GRAY, 0);
        var srcVec = new cv.MatVector();
        srcVec.push_back(src);
        var total_pixels = src.cols * src.rows;
        var accumulate = false;
        var channels = [0];
        var histSize = [256];
        var ranges = [0, 255];
        var hist = new cv.Mat();
        var mask = new cv.Mat();

        cv.calcHist(srcVec, channels, mask, hist, histSize, ranges, accumulate);
        var summing = 0;
        var drone_imagery_remove_background_lower_percentage_threshold;
        var drone_imagery_remove_background_upper_percentage_threshold;
        for (let i = 0; i < histSize[0]; i++) {
            var binVal = hist.data32F[i];
            summing = summing + binVal;
            var percentage = summing / total_pixels;
            if (percentage >= drone_imagery_remove_background_lower_percentage) {
                drone_imagery_remove_background_lower_percentage_threshold = i;
                break;
            }
        }
        summing = 0;
        for (let i = 0; i < histSize[0]; i++) {
            var binVal = hist.data32F[i];
            summing = summing + binVal;
            var percentage = summing / total_pixels;
            if (percentage >= 1-drone_imagery_remove_background_upper_percentage) {
                drone_imagery_remove_background_upper_percentage_threshold = i;
                break;
            }
        }
        return [drone_imagery_remove_background_lower_percentage_threshold*100, drone_imagery_remove_background_upper_percentage_threshold*100];
    }

    jQuery('#drone_imagery_remove_background_defined_percentage_submit').click(function(){
        drone_imagery_remove_background_lower_percentage = Number(jQuery('#drone_imagery_remove_background_lower_threshold_percentage').val())/100;
        drone_imagery_remove_background_upper_percentage = Number(jQuery('#drone_imagery_remove_background_upper_threshold_percentage').val())/100;

        var threshold_value_return = calculateThresholdPercentageValues('drone_imagery_remove_background_original', drone_imagery_remove_background_lower_percentage, drone_imagery_remove_background_upper_percentage);

        manage_drone_imagery_remove_background_threshold_save(remove_background_current_image_id, remove_background_current_image_type, remove_background_drone_run_band_project_id, threshold_value_return[0], threshold_value_return[1]);
    });

    function manage_drone_imagery_remove_background_threshold_save(image_id, image_type, drone_run_band_project_id, lower_threshold, upper_threshold){
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/remove_background_save',
            dataType: "json",
            data: {
                'image_id': image_id,
                'image_type': image_type,
                'drone_run_band_project_id': drone_run_band_project_id,
                'lower_threshold': lower_threshold,
                'upper_threshold': upper_threshold
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                }

                jQuery("#working_modal").modal("hide");
                location.reload();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error saving removed background image!')
            }
        });
    }

    //
    //Calculate Phenotypes JS
    //

    var manage_drone_imagery_calculate_phenotypes_drone_run_id;
    var manage_drone_imagery_calculate_phenotypes_drone_run_band_id;
    var manage_drone_imagery_calculate_phenotypes_drone_run_band_type;
    var manage_drone_imagery_calculate_phenotypes_plot_polygons_type;
    var manage_drone_image_calculate_phenotypes_zonal_time_cvterm_id = '';

    jQuery(document).on('click', 'button[name=project_drone_imagery_get_phenotypes]', function() {
        showManageDroneImagerySection('manage_drone_imagery_calculate_phenotypes_div');

        manage_drone_imagery_calculate_phenotypes_drone_run_id = jQuery(this).data('drone_run_project_id');
        manage_drone_imagery_calculate_phenotypes_drone_run_band_id = jQuery(this).data('drone_run_band_project_id');
        manage_drone_imagery_calculate_phenotypes_drone_run_band_type = jQuery(this).data('drone_run_band_project_type');
        manage_drone_imagery_calculate_phenotypes_plot_polygons_type = jQuery(this).data('plot_polygons_type');
    });

    jQuery('#drone_imagery_calculate_phenotypes_sift').click(function(){

        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/calculate_phenotypes?method=sift',
            dataType: "json",
            data: {
                'drone_run_band_project_id': manage_drone_imagery_calculate_phenotypes_drone_run_band_id,
                'drone_run_band_project_type': manage_drone_imagery_calculate_phenotypes_drone_run_band_type,
                'plot_polygons_type': manage_drone_imagery_calculate_phenotypes_plot_polygons_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                    return;
                }

                var html = '<table class="table table-bordered table-hover"><thead><tr><th>Observation Unit</th><th>SIFT Features Image</th></tr></thead><tbody>';
                for (var i=0; i<response.results.length; i++) {
                    html = html + '<tr><td><a target="_blank" href="/stock/' + response.results[i].stock_id + '/view" >' + response.results[i].stock_uniquename + '</a></td><td>' + response.results[i].image + '</td></tr>';
                }
                jQuery('#manage_drone_imagery_calculate_phenotypes_show_sift').html(html);

                jQuery("#working_modal").modal("hide");
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error calculating sift features!')
            }
        });

    });

    jQuery('#drone_imagery_calculate_phenotypes_orb').click(function(){

        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/calculate_phenotypes?method=orb',
            dataType: "json",
            data: {
                'drone_run_band_project_id': manage_drone_imagery_calculate_phenotypes_drone_run_band_id,
                'drone_run_band_project_type': manage_drone_imagery_calculate_phenotypes_drone_run_band_type,
                'plot_polygons_type': manage_drone_imagery_calculate_phenotypes_plot_polygons_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                    return;
                }

                var html = '<table class="table table-bordered table-hover"><thead><tr><th>Observation Unit</th><th>ORB Features Image</th></tr></thead><tbody>';
                for (var i=0; i<response.results.length; i++) {
                    html = html + '<tr><td><a target="_blank" href="/stock/' + response.results[i].stock_id + '/view" >' + response.results[i].stock_uniquename + '</a></td><td>' + response.results[i].image + '</td></tr>';
                }
                jQuery('#manage_drone_imagery_calculate_phenotypes_show_orb').html(html);

                jQuery("#working_modal").modal("hide");
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error calculating ORB features!')
            }
        });

    });

    jQuery('#drone_imagery_calculate_phenotypes_surf').click(function(){

        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/calculate_phenotypes?method=surf',
            dataType: "json",
            data: {
                'drone_run_band_project_id': manage_drone_imagery_calculate_phenotypes_drone_run_band_id,
                'drone_run_band_project_type': manage_drone_imagery_calculate_phenotypes_drone_run_band_type,
                'plot_polygons_type': manage_drone_imagery_calculate_phenotypes_plot_polygons_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                if(response.error) {
                    alert(response.error);
                    return;
                }

                var html = '<table class="table table-bordered table-hover"><thead><tr><th>Observation Unit</th><th>SURF Features Image</th></tr></thead><tbody>';
                for (var i=0; i<response.results.length; i++) {
                    html = html + '<tr><td><a target="_blank" href="/stock/' + response.results[i].stock_id + '/view" >' + response.results[i].stock_uniquename + '</a></td><td>' + response.results[i].image + '</td></tr>';
                }
                jQuery('#manage_drone_imagery_calculate_phenotypes_show_surf').html(html);

                jQuery("#working_modal").modal("hide");
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error calculating surf features!')
            }
        });

    });

    jQuery('#drone_imagery_calculate_phenotypes_zonal_stats').click(function(){

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/get_weeks_after_planting_date?drone_run_project_id='+manage_drone_imagery_calculate_phenotypes_drone_run_id,
            dataType: "json",
            beforeSend: function (){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                jQuery('#working_modal').modal('hide');
                console.log(response);
                if (response.error) {
                    alert(response.error);
                }

                var html = "<center><b>Field Trial Planting Date</b>: "+response.planting_date+"<br/><b>Imaging Event Date</b>: "+response.drone_run_date+"<br/><b>Number of Weeks</b>: "+response.rounded_time_difference_weeks+"<br/><b>Number of Weeks Ontology Term</b>: "+response.time_ontology_week_term+"<br/><b>Number of Days</b>:"+response.time_difference_days+"<br/><b>Number of Days Ontology Term</b>: "+response.time_ontology_day_term+"<br/><br/></center>";
                jQuery('#drone_imagery_calculate_phenotypes_zonal_stats_week_term_div').html(html);
                manage_drone_image_calculate_phenotypes_zonal_time_cvterm_id = response.time_ontology_day_cvterm_id;
            },
            error: function(response){
                alert('Error getting time terms!');
                jQuery('#working_modal').modal('hide');
            }
        });

        jQuery('#drone_imagery_calc_phenotypes_zonal_channel_dialog').modal('show');
    });

    jQuery('#drone_imagery_calculate_phenotypes_zonal_stats_channel_select').click(function(){
        if (manage_drone_image_calculate_phenotypes_zonal_time_cvterm_id == '') {
            alert('Time of phenotype not set for calculate zonal stats. This should not happen so please contact us!');
            return false;
        }

        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/calculate_phenotypes?method=zonal',
            dataType: "json",
            data: {
                'drone_run_band_project_id': manage_drone_imagery_calculate_phenotypes_drone_run_band_id,
                'drone_run_band_project_type': manage_drone_imagery_calculate_phenotypes_drone_run_band_type,
                'time_cvterm_id': manage_drone_image_calculate_phenotypes_zonal_time_cvterm_id,
                'plot_polygons_type': manage_drone_imagery_calculate_phenotypes_plot_polygons_type,
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if(response.error) {
                    alert(response.error);
                    return false;
                }

                var html = '<table class="table table-bordered table-hover" id="manage_drone_imagery_zonal_stats_table"><thead><tr><th>Observation Unit</th><th>Image</th>';
                for (var i=0; i<response.result_header.length; i++) {
                    html = html + '<th>'+response.result_header[i]+'</th>';
                }
                html = html + '</tr></thead><tbody>';
                for (var i=0; i<response.results.length; i++) {
                    html = html + '<tr><td><a target="_blank" href="/stock/' + response.results[i].stock_id + '/view" >' + response.results[i].stock_uniquename + '</a></td><td>' + response.results[i].image + '</td>';
                    for (var j=0; j<response.results[i].result.length; j++){
                        html = html + '<td>'+response.results[i].result[j]+'</td>';
                    }
                    html = html + '</tr>';
                }
                jQuery('#manage_drone_imagery_calculate_phenotypes_show_zonal_stats').html(html);
                jQuery('#manage_drone_imagery_zonal_stats_table').DataTable();

                jQuery('#drone_imagery_calc_phenotypes_zonal_channel_dialog').modal('hide');
                return false;
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error calculating zonal stats!')
            }
        });
    });

    //
    //RGB/3band Image Vegetative Index
    //

    var manage_drone_imagery_vi_rgb_drone_run_band_project_id;
    var manage_drone_imagery_vi_rgb_denoised_stitched_image_id;
    var manage_drone_imagery_vi_drone_run_band_type;
    var manage_drone_imagery_vi_selected_index;
    var manage_drone_imagery_vi_selected_image_type;

    jQuery(document).on('click', 'button[name="project_drone_imagery_rgb_vegetative"]', function(){
        manage_drone_imagery_vi_rgb_drone_run_band_project_id = jQuery(this).data('drone_run_band_project_id');
        manage_drone_imagery_vi_rgb_denoised_stitched_image_id = jQuery(this).data('denoised_stitched_image_id');
        manage_drone_imagery_vi_drone_run_band_type = jQuery(this).data('drone_run_band_project_type');

        showManageDroneImagerySection('manage_drone_imagery_vegetative_index_div');

        jQuery('#manage_drone_imagery_vegetative_index_tgi_rgb_div').show();
        jQuery('#manage_drone_imagery_vegetative_index_tgi_bgr_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_vari_rgb_div').show();
        jQuery('#manage_drone_imagery_vegetative_index_vari_bgr_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_ndvi_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_ndre_div').hide();
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_3_band_bgr_vegetative"]', function(){
        manage_drone_imagery_vi_rgb_drone_run_band_project_id = jQuery(this).data('drone_run_band_project_id');
        manage_drone_imagery_vi_rgb_denoised_stitched_image_id = jQuery(this).data('denoised_stitched_image_id');
        manage_drone_imagery_vi_drone_run_band_type = jQuery(this).data('drone_run_band_project_type');

        showManageDroneImagerySection('manage_drone_imagery_vegetative_index_div');

        jQuery('#manage_drone_imagery_vegetative_index_tgi_rgb_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_tgi_bgr_div').show();
        jQuery('#manage_drone_imagery_vegetative_index_vari_rgb_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_vari_bgr_div').show();
        jQuery('#manage_drone_imagery_vegetative_index_ndvi_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_ndre_div').hide();
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_3_band_nrn_vegetative"]', function(){
        manage_drone_imagery_vi_rgb_drone_run_band_project_id = jQuery(this).data('drone_run_band_project_id');
        manage_drone_imagery_vi_rgb_denoised_stitched_image_id = jQuery(this).data('denoised_stitched_image_id');
        manage_drone_imagery_vi_drone_run_band_type = jQuery(this).data('drone_run_band_project_type');

        showManageDroneImagerySection('manage_drone_imagery_vegetative_index_div');

        jQuery('#manage_drone_imagery_vegetative_index_tgi_rgb_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_tgi_bgr_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_vari_rgb_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_vari_bgr_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_ndvi_div').show();
        jQuery('#manage_drone_imagery_vegetative_index_ndre_div').hide();
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_3_band_nren_vegetative"]', function(){
        manage_drone_imagery_vi_rgb_drone_run_band_project_id = jQuery(this).data('drone_run_band_project_id');
        manage_drone_imagery_vi_rgb_denoised_stitched_image_id = jQuery(this).data('denoised_stitched_image_id');
        manage_drone_imagery_vi_drone_run_band_type = jQuery(this).data('drone_run_band_project_type');

        showManageDroneImagerySection('manage_drone_imagery_vegetative_index_div');

        jQuery('#manage_drone_imagery_vegetative_index_tgi_rgb_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_tgi_bgr_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_vari_rgb_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_vari_bgr_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_ndvi_div').hide();
        jQuery('#manage_drone_imagery_vegetative_index_ndre_div').show();
    });

    jQuery('#drone_imagery_vegetative_index_TGI_bgr').click(function(){
        manage_drone_imagery_vi_selected_index = 'TGI';
        manage_drone_imagery_vi_selected_image_type = 'BGR';
        getVegetativeIndex('calculate_vegetative_index', manage_drone_imagery_vi_rgb_denoised_stitched_image_id, manage_drone_imagery_vi_rgb_drone_run_band_project_id, manage_drone_imagery_vi_drone_run_band_type, manage_drone_imagery_vi_selected_index, 1, manage_drone_imagery_vi_selected_image_type);
    });

    jQuery('#drone_imagery_vegetative_index_TGI_rgb').click(function(){
        manage_drone_imagery_vi_selected_index = 'TGI';
        manage_drone_imagery_vi_selected_image_type = 'BGR';
        getVegetativeIndex('calculate_vegetative_index', manage_drone_imagery_vi_rgb_denoised_stitched_image_id, manage_drone_imagery_vi_rgb_drone_run_band_project_id, manage_drone_imagery_vi_drone_run_band_type, manage_drone_imagery_vi_selected_index, 1, manage_drone_imagery_vi_selected_image_type);
    });

    jQuery('#drone_imagery_vegetative_index_VARI_bgr').click(function(){
        manage_drone_imagery_vi_selected_index = 'VARI';
        manage_drone_imagery_vi_selected_image_type = 'BGR';
        getVegetativeIndex('calculate_vegetative_index', manage_drone_imagery_vi_rgb_denoised_stitched_image_id, manage_drone_imagery_vi_rgb_drone_run_band_project_id, manage_drone_imagery_vi_drone_run_band_type, manage_drone_imagery_vi_selected_index, 1, manage_drone_imagery_vi_selected_image_type);
    });

    jQuery('#drone_imagery_vegetative_index_VARI_rgb').click(function(){
        manage_drone_imagery_vi_selected_index = 'VARI';
        manage_drone_imagery_vi_selected_image_type = 'BGR';
        getVegetativeIndex('calculate_vegetative_index', manage_drone_imagery_vi_rgb_denoised_stitched_image_id, manage_drone_imagery_vi_rgb_drone_run_band_project_id, manage_drone_imagery_vi_drone_run_band_type, manage_drone_imagery_vi_selected_index, 1, manage_drone_imagery_vi_selected_image_type);
    });

    jQuery('#drone_imagery_vegetative_index_NDVI').click(function(){
        manage_drone_imagery_vi_selected_index = 'NDVI';
        manage_drone_imagery_vi_selected_image_type = 'NRN';
        getVegetativeIndex('calculate_vegetative_index', manage_drone_imagery_vi_rgb_denoised_stitched_image_id, manage_drone_imagery_vi_rgb_drone_run_band_project_id, manage_drone_imagery_vi_drone_run_band_type, manage_drone_imagery_vi_selected_index, 1, manage_drone_imagery_vi_selected_image_type);
    });

    jQuery('#drone_imagery_vegetative_index_NDRE').click(function(){
        manage_drone_imagery_vi_selected_index = 'NDRE';
        manage_drone_imagery_vi_selected_image_type = 'NReN';
        getVegetativeIndex('calculate_vegetative_index', manage_drone_imagery_vi_rgb_denoised_stitched_image_id, manage_drone_imagery_vi_rgb_drone_run_band_project_id, manage_drone_imagery_vi_drone_run_band_type, manage_drone_imagery_vi_selected_index, 1, manage_drone_imagery_vi_selected_image_type);
    });

    jQuery('#drone_imagery_rgb_vegetative_index_submit').click(function(){
        getVegetativeIndex('calculate_vegetative_index', manage_drone_imagery_vi_rgb_denoised_stitched_image_id, manage_drone_imagery_vi_rgb_drone_run_band_project_id, manage_drone_imagery_vi_drone_run_band_type, manage_drone_imagery_vi_selected_index, 0, manage_drone_imagery_vi_selected_image_type);
    });

    function getVegetativeIndex(url_part, image_id, drone_run_band_project_id, drone_run_band_project_type, index, view_only, manage_drone_imagery_vi_selected_image_type) {
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/'+url_part,
            dataType: "json",
            data: {
                'image_id': image_id,
                'drone_run_band_project_id': drone_run_band_project_id,
                'vegetative_index': index,
                'drone_run_band_project_type': drone_run_band_project_type,
                'view_only': view_only,
                'image_type': manage_drone_imagery_vi_selected_image_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if(response.error) {
                    alert(response.error);
                }

                if (view_only == 1) {
                    var canvas = document.getElementById('drone_imagery_vegetative_index_original_stitched_div');
                    ctx = canvas.getContext('2d');
                    var image = new Image();
                    image.onload = function () {
                        canvas.width = this.naturalWidth;
                        canvas.height = this.naturalHeight;
                        ctx.drawImage(this, 0, 0);
                    };
                    image.src = response.index_image_url;
                } else {
                    location.reload();
                }
            },
            error: function(response){
                alert('Error getting vegetative index!')
            }
        });
    }

    //
    // Apply Masks From Background Removed Vegetative Index to Denoised Image
    //

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_tgi_removed_background_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('background_removed_tgi_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_thresholded_tgi_mask_original');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_vari_removed_background_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('background_removed_vari_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_thresholded_vari_mask_original');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_ndvi_removed_background_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('background_removed_ndvi_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_thresholded_ndvi_mask_original');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_ndre_removed_background_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('background_removed_ndre_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_thresholded_ndre_mask_original');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_tgi_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('tgi_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_tgi_mask_original');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_vari_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('vari_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_vari_mask_original');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_ndvi_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('ndvi_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_ndvi_mask_original');
    });

    jQuery(document).on('click', 'button[name="project_drone_imagery_apply_ndre_mask_to_denoised_image"]', function(){
        drone_imagery_mask_remove_background(jQuery(this).data('denoised_stitched_image_id'), jQuery(this).data('ndre_stitched_image_id'), jQuery(this).data('drone_run_band_project_id'), 'denoised_background_removed_ndre_mask_original');
    });

    function drone_imagery_mask_remove_background(image_id, mask_image_id, drone_run_band_project_id, mask_type) {
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/mask_remove_background',
            dataType: "json",
            data: {
                'image_id': image_id,
                'mask_image_id': mask_image_id,
                'drone_run_band_project_id': drone_run_band_project_id,
                'mask_type': mask_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if(response.error) {
                    alert(response.error);
                }

                location.reload();
            },
            error: function(response){
                alert('Error removing background using mask of vegetative index!' + mask_type);
            }
        });
    }

    //
    // Run and save Fourier Transform HPF30
    //

    var manage_drone_imagery_ft_hpf30_drone_run_band_project_id = '';
    var manage_drone_imagery_ft_hpf30_image_id = '';
    var manage_drone_imagery_ft_hpf30_drone_run_band_type = '';
    var manage_drone_imagery_ft_hpf30_selected_image_type = '';

    jQuery(document).on('click', 'button[name="project_drone_imagery_fourier_transform_hpf30"]', function(){
        manage_drone_imagery_ft_hpf30_drone_run_band_project_id = jQuery(this).data('drone_run_band_project_id');
        manage_drone_imagery_ft_hpf30_image_id = jQuery(this).data('image_id');
        manage_drone_imagery_ft_hpf30_drone_run_band_type = jQuery(this).data('drone_run_band_project_type');
        manage_drone_imagery_ft_hpf30_selected_image_type = jQuery(this).data('selected_image_type');
        getFourierTransform(30, manage_drone_imagery_ft_hpf30_image_id, manage_drone_imagery_ft_hpf30_drone_run_band_project_id, manage_drone_imagery_ft_hpf30_drone_run_band_type, manage_drone_imagery_ft_hpf30_selected_image_type, 'frequency');
    });

    function getFourierTransform(high_pass_filter, image_id, drone_run_band_project_id, drone_run_band_project_type, selected_image_type, high_pass_filter_type) {
        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/calculate_fourier_transform',
            dataType: "json",
            data: {
                'image_id': image_id,
                'drone_run_band_project_id': drone_run_band_project_id,
                'drone_run_band_project_type': drone_run_band_project_type,
                'high_pass_filter': high_pass_filter,
                'high_pass_filter_type': high_pass_filter_type,
                'image_type': selected_image_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if(response.error) {
                    alert(response.error);
                }

                location.reload();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error getting fourier transform!')
            }
        });
    }

    //
    // Merge bands into single image
    //

    var drone_imagery_merge_channels_drone_run_project_id;
    var drone_imagery_merge_channels_drone_run_project_name;
    jQuery(document).on('click', 'button[name="project_drone_imagery_merge_channels"]', function() {
        drone_imagery_merge_channels_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        drone_imagery_merge_channels_drone_run_project_name = jQuery(this).data('drone_run_project_name');

        jQuery('#drone_imagery_merge_channels_dialog').modal('show');

        get_select_box('drone_imagery_drone_run_band','drone_imagery_merge_bands_band1_select', {'id':'drone_run_merge_band_select_1', 'name':'drone_run_merge_band_select_1', 'empty':1, 'drone_run_project_id':drone_imagery_merge_channels_drone_run_project_id });
        get_select_box('drone_imagery_drone_run_band','drone_imagery_merge_bands_band2_select', {'id':'drone_run_merge_band_select_2', 'name':'drone_run_merge_band_select_2', 'empty':1, 'drone_run_project_id':drone_imagery_merge_channels_drone_run_project_id });
        get_select_box('drone_imagery_drone_run_band','drone_imagery_merge_bands_band3_select', {'id':'drone_run_merge_band_select_3', 'name':'drone_run_merge_band_select_3', 'empty':1, 'drone_run_project_id':drone_imagery_merge_channels_drone_run_project_id });
    });

    jQuery('#drone_imagery_merge_bands_submit').click(function(){
        var band_1_drone_run_band_project_id = jQuery('#drone_run_merge_band_select_1').val();
        var band_2_drone_run_band_project_id = jQuery('#drone_run_merge_band_select_2').val();
        var band_3_drone_run_band_project_id = jQuery('#drone_run_merge_band_select_3').val();
        var merged_image_type = jQuery('#drone_run_merge_image_type').val();
        if (merged_image_type == '') {
            alert('Please select a merged image type first!');
            return false;
        }

        jQuery.ajax({
            type: 'POST',
            url: '/api/drone_imagery/merge_bands',
            dataType: "json",
            data: {
                'band_1_drone_run_band_project_id': band_1_drone_run_band_project_id,
                'band_2_drone_run_band_project_id': band_2_drone_run_band_project_id,
                'band_3_drone_run_band_project_id': band_3_drone_run_band_project_id,
                'drone_run_project_id': drone_imagery_merge_channels_drone_run_project_id,
                'drone_run_project_name': drone_imagery_merge_channels_drone_run_project_name,
                'merged_image_type' : merged_image_type
            },
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if(response.error) {
                    alert(response.error);
                }

                location.reload();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error merging bands!')
            }
        });
    });

    //
    // Compare Aerial Field Images
    //

    var drone_imagery_compare_images_comparison_type = '';
    var drone_imagery_compare_images_field_trial_ids = [];
    var drone_imagery_compare_images_field_trial_id_string = '';
    var drone_imagery_compare_images_drone_run_ids = [];
    var drone_imagery_compare_images_drone_run_band_ids = [];
    var drone_imagery_compare_images_image_types = [];

    jQuery('#drone_imagery_compare_field_images_link').click(function(){
        jQuery('#drone_imagery_compare_images_dialog').modal('show');

        drone_imagery_compare_images_comparison_type =   '';
        drone_imagery_compare_images_field_trial_ids = [];
        drone_imagery_compare_images_field_trial_id_string = '';
        drone_imagery_compare_images_drone_run_ids = [];
        drone_imagery_compare_images_image_types = [];
    });

    jQuery('#drone_imagery_compare_images_comparison_select_step').click(function(){
        get_select_box('trials', 'drone_imagery_compare_images_trial_select_div', { 'name' : 'drone_imagery_compare_images_field_trial_id', 'id' : 'drone_imagery_compare_images_field_trial_id', 'empty':1, 'multiple':1 });

        Workflow.complete("#drone_imagery_compare_images_comparison_select_step");
        Workflow.focus('#drone_imagery_compare_images_workflow', 1);
        return false;
    });

    jQuery('#drone_imagery_compare_images_field_trial_select_step').click(function(){
        drone_imagery_compare_images_field_trial_ids = [];
        drone_imagery_compare_images_field_trial_id_string = '';
        drone_imagery_compare_images_field_trial_ids = jQuery('#drone_imagery_compare_images_field_trial_id').val();
        drone_imagery_compare_images_field_trial_id_string = drone_imagery_compare_images_field_trial_ids.join(",");
        if (drone_imagery_compare_images_field_trial_id_string == '') {
            alert('Please select a field trial first!');
        } else {
            jQuery('#drone_image_compare_images_drone_runs_table').DataTable({
                destroy : true,
                ajax : '/api/drone_imagery/drone_runs?select_checkbox_name=drone_imagery_compare_images_drone_run_select&field_trial_ids='+drone_imagery_compare_images_field_trial_id_string
            });

            Workflow.complete("#drone_imagery_compare_images_field_trial_select_step");
            Workflow.focus('#drone_imagery_compare_images_workflow', 2);
        }
        return false;
    });

    jQuery('#drone_imagery_compare_images_drone_runs_select_step').click(function(){
        drone_imagery_compare_images_drone_run_ids = [];
        jQuery('input[name="drone_imagery_compare_images_drone_run_select"]:checked').each(function() {
            drone_imagery_compare_images_drone_run_ids.push(jQuery(this).val());
        });
        if (drone_imagery_compare_images_drone_run_ids.length < 1){
            alert('Please select at least one imaging event!');
        } else if (drone_imagery_compare_images_drone_run_ids.length > 2){
            alert('Please select a maximum of two imaging events, given that we can only compare two images at a time here.');
        } else {
            jQuery('#drone_image_compare_images_drone_run_bands_table').DataTable({
                destroy : true,
                ajax : '/api/drone_imagery/drone_run_bands?select_checkbox_name=drone_run_compare_images_band_select&drone_run_project_ids='+JSON.stringify(drone_imagery_compare_images_drone_run_ids)
            });

            Workflow.complete("#drone_imagery_compare_images_drone_runs_select_step");
            Workflow.focus('#drone_imagery_compare_images_workflow', 3);
        }
        return false;
    });

    jQuery('#drone_imagery_compare_images_drone_run_bands_select_step').click(function(){
        drone_imagery_compare_images_drone_run_band_ids = [];
        jQuery('input[name="drone_run_compare_images_band_select"]:checked').each(function() {
            drone_imagery_compare_images_drone_run_band_ids.push(jQuery(this).val());
        });
        if (drone_imagery_compare_images_drone_run_band_ids.length < 1){
            alert('Please select at least one imaging event band!');
        } else if (drone_imagery_compare_images_drone_run_band_ids.length > 2){
            alert('Please select a maximum of two imaging event bands, given that we can only compare two images at a time here.');
        } else {
            jQuery('#drone_imagery_compare_images_images_type_table').DataTable({
                destroy : true,
                paging : false,
                ajax : '/api/drone_imagery/plot_polygon_types?select_checkbox_name=drone_imagery_compare_images_plot_polygon_type_select&field_trial_ids='+drone_imagery_compare_images_field_trial_id_string+'&drone_run_ids='+JSON.stringify(drone_imagery_compare_images_drone_run_ids)+'&field_trial_images_only=1+&drone_run_band_ids='+JSON.stringify(drone_imagery_compare_images_drone_run_band_ids)
            });

            Workflow.complete("#drone_imagery_compare_images_drone_run_bands_select_step");
            Workflow.focus('#drone_imagery_compare_images_workflow', 4);
        }
        return false;
    });

    jQuery('#drone_imagery_compare_images_images_select_step').click(function(){
        drone_imagery_compare_images_image_types = [];
        jQuery('input[name="drone_imagery_compare_images_plot_polygon_type_select"]:checked').each(function() {
            drone_imagery_compare_images_image_types.push(jQuery(this).val());
        });
        if (drone_imagery_compare_images_image_types.length < 1){
            alert('Please select at least one image type!');
        } else if (drone_imagery_compare_images_image_types.length > 2){
            alert('Please select a maximum of two image types, given that we can only compare two images at a time here.');
        } else {
            jQuery.ajax({
                url : '/api/drone_imagery/compare_images?drone_run_ids='+JSON.stringify(drone_imagery_compare_images_drone_run_ids)+'&drone_run_band_ids='+JSON.stringify(drone_imagery_compare_images_drone_run_band_ids)+'&image_type_ids='+JSON.stringify(drone_imagery_compare_images_image_types)+'&comparison_type='+jQuery('#drone_imagery_compare_images_comparison_select').val(),
                beforeSend: function() {
                    jQuery("#working_modal").modal("show");
                },
                success: function(response){
                    console.log(response);
                    jQuery("#working_modal").modal("hide");

                    var html = '<a target=_blank href="'+response.result+'">File</a>';
                    jQuery('#drone_imagery_compare_images_result_div').html(html);

                    Workflow.complete("#drone_imagery_compare_images_images_select_step");
                    Workflow.focus('#drone_imagery_compare_images_workflow', 5);
                },
                error: function(response){
                    jQuery("#working_modal").modal("hide");
                    alert('Error comparing images!')
                }
            });
        }
        return false;
    });

    //
    // Change date imaging event
    //

    var manage_drone_imagery_change_date_drone_run_project_id;
    var manage_drone_imagery_change_date_drone_run_field_trial_id;
    var manage_drone_imagery_change_date_drone_run_can_proceed = 0;
    var manage_drone_imagery_change_date_drone_run_date = 0;
    jQuery(document).on('click', 'button[name="project_drone_imagery_change_date_drone_run"]', function(){
        manage_drone_imagery_change_date_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        manage_drone_imagery_change_date_drone_run_field_trial_id = jQuery(this).data('field_trial_id');

        jQuery.ajax({
            url : '/api/drone_imagery/check_field_trial_ids?field_trial_ids='+manage_drone_imagery_change_date_drone_run_field_trial_id,
            success: function(response){
                console.log(response);
                if (response.html) {
                    jQuery('#change_date_drone_image_field_trial_info').html(response.html);
                    jQuery('#drone_imagery_change_date_drone_run_dialog').modal('show');
                }
                if (response.can_proceed == 1) {
                    manage_drone_imagery_change_date_drone_run_can_proceed = 1;
                }
                else {
                    manage_drone_imagery_change_date_drone_run_can_proceed = 0;
                }
            },
            error: function(response){
                alert('Error checking field trial details to change imaging event date!');
            }
        });

        var drone_run_change_date_element = jQuery("#drone_run_change_date");
        set_daterangepicker_default (drone_run_change_date_element);
        jQuery('input[title="drone_run_change_date"]').daterangepicker(
            {
                "singleDatePicker": true,
                "showDropdowns": true,
                "autoUpdateInput": false,
                "timePicker": true,
                "timePicker24Hour": true,
            },
            function(start){
                drone_run_change_date_element.val(start.format('YYYY/MM/DD HH:mm:ss'));
            }
        );

    });

    jQuery('#drone_imagery_change_date_drone_run_confirm').click(function() {
        if (manage_drone_imagery_change_date_drone_run_can_proceed == 1) {
            manage_drone_imagery_change_date_drone_run_date = jQuery('#drone_run_change_date').val();

            if (manage_drone_imagery_change_date_drone_run_date != '') {
                jQuery.ajax({
                    type: 'GET',
                    url: '/api/drone_imagery/change_date_drone_run?drone_run_project_id='+manage_drone_imagery_change_date_drone_run_project_id+'&field_trial_id='+manage_drone_imagery_change_date_drone_run_field_trial_id+'&date='+manage_drone_imagery_change_date_drone_run_date,
                    beforeSend: function() {
                        jQuery("#working_modal").modal("show");
                    },
                    success: function(response){
                        console.log(response);
                        jQuery("#working_modal").modal("hide");

                        if(response.error) {
                            alert(response.error);
                        }
                        if(response.success) {
                            alert('Imaging event date changed successfully!');
                        }
                        location.reload();
                    },
                    error: function(response){
                        jQuery("#working_modal").modal("hide");
                        alert('Error changing date of imaging event!')
                    }
                });
            }
            else {
                alert('Please select a new date first!');
                return false;
            }
        }
        else {
            alert('Cannot proceed with changing imaging event name! Something wrong with planting date!');
            return false;
        }
    });

    //
    // Delete imaging event
    //

    var manage_drone_imagery_delete_drone_run_project_id;
    jQuery(document).on('click', 'button[name="project_drone_imagery_delete_drone_run"]', function(){
        manage_drone_imagery_delete_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        jQuery('#drone_imagery_delete_drone_run_dialog').modal('show');
    });

    jQuery('#drone_imagery_delete_drone_run_confirm').click(function(){
        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/delete_drone_run?drone_run_project_id='+manage_drone_imagery_delete_drone_run_project_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if(response.error) {
                    alert(response.error);
                }
                if(response.success) {
                    alert('Imaging event deleted successfully!');
                }
                location.reload();
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error deleting imaging event!')
            }
        });
    });

    //
    // Quality Control Plot Images
    //

    var manage_drone_imagery_quality_control_field_trial_id;
    var manage_drone_imagery_quality_control_drone_run_id;

    jQuery(document).on('click', 'button[name="project_drone_imagery_quality_control_check"]',function() {
        showManageDroneImagerySection('manage_drone_imagery_quality_control_div');

        alert('Clicking any of these checkboxes will obsolete the image and cannot be readily reversed!');

        manage_drone_imagery_quality_control_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_quality_control_drone_run_id = jQuery(this).data('drone_run_project_id');

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/quality_control_get_images?drone_run_project_id='+manage_drone_imagery_quality_control_drone_run_id,
            beforeSend: function() {
                jQuery("#working_modal").modal("show");
            },
            success: function(response){
                console.log(response);
                jQuery("#working_modal").modal("hide");

                if (response.error) {
                    alert(response.error);
                }
                var html = '<table class="table table-hover table-bordered"><thead><tr><th>Plot Name</th><td>Images (Select to obsolete)</td></tr></thead><tbody>';
                for(var i=0; i<response.result.length; i++) {
                    html = html + '<tr><td>'+response.result[i][0]+'</td><td>'+response.result[i][1]+'</td></tr>';
                }
                html = html + '</tbody></table>';
                jQuery('#drone_imagery_quality_control_div').html(html);
            },
            error: function(response){
                jQuery("#working_modal").modal("hide");
                alert('Error getting images for quality check!');
            }
        });

    });

    jQuery(document).on('change', 'input[name="manage_drone_imagery_quality_control_image_select"]', function(){
        var image_id = jQuery(this).val();
        var checked = this.checked;

        jQuery.ajax({
            type: 'GET',
            url: '/api/drone_imagery/obsolete_image_change?image_id='+image_id,
            success: function(response){
                console.log(response);
            },
            error: function(response){
                alert('Error obsoleting image!');
            }
        });
    });

    //
    // Associated Field Trials
    //

    var manage_drone_imagery_multiple_field_trial_drone_run_project_id;
    var manage_drone_imagery_multiple_field_trial_field_trial_id;
    var manage_drone_imagery_multiple_field_trial_field_trial_name;
    var manage_drone_imagery_multiple_field_trial_add_field_trial_ids = [];
    var manage_drone_imagery_multiple_field_trial_add_field_trial_ids_string;

    jQuery(document).on('click', 'button[name="project_drone_imagery_multiple_field_trial_check"]', function(){
        manage_drone_imagery_multiple_field_trial_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        manage_drone_imagery_multiple_field_trial_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_multiple_field_trial_field_trial_name = jQuery(this).data('field_trial_name');

        jQuery.ajax({
            url: '/api/drone_imagery/check_associated_field_trials?drone_run_project_id='+manage_drone_imagery_multiple_field_trial_drone_run_project_id,
            beforeSend: function(){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                console.log(response);
                jQuery('#working_modal').modal('hide');

                if (response.error) {
                    alert(response.error);
                }
                else {
                    var html = '<div class="form-horizontal">';

                    html = html + '<div class="form-group"><label class="col-sm-5 control-label">Associated Field Trials: </label><div class="col-sm-7">';

                    html = html + '<ul><li>'+manage_drone_imagery_multiple_field_trial_field_trial_name+'</li>';

                    for (var i=0; i<response.associated_field_trial_ids.length; i++) {
                        html = html + '<li>'+response.associated_field_trial_names[i]+'</li>'
                    }

                    html = html + '</ul>';

                    html = html + '</div></div><hr>';

                    html = html + '<div class="form-group"><label class="col-sm-5 control-label">Associate Another Field Trial(s): </label><div class="col-sm-7">';
                    html = html + '<div id="drone_imagery_associated_field_trials_dropdown"></div>'
                    html = html + '</div></div>';

                    html = html + '</div>';
                    jQuery('#drone_imagery_associated_field_trials_div').html(html);

                    get_select_box('trials', 'drone_imagery_associated_field_trials_dropdown', { 'name' : 'drone_imagery_associated_field_trials_field_trial_id', 'id' : 'drone_imagery_associated_field_trials_field_trial_id', 'empty':1, 'multiple':1 });

                    jQuery('#drone_imagery_associated_field_trials_dialog').modal('show');
                }
            },
            error: function(response){
                jQuery('#working_modal').modal('hide');
                alert('Error getting associated field trials!');
            }
        });
    });

    jQuery(document).on('change', '#drone_imagery_associated_field_trials_field_trial_id', function() {
        manage_drone_imagery_multiple_field_trial_add_field_trial_ids = jQuery(this).val();
        manage_drone_imagery_multiple_field_trial_add_field_trial_ids_string = manage_drone_imagery_multiple_field_trial_add_field_trial_ids.join();
    });

    jQuery('#drone_imagery_associated_field_trials_select_submit').click(function() {
        if (manage_drone_imagery_multiple_field_trial_add_field_trial_ids.length < 1) {
            alert('First select another field trial to associate to the imaging event.');
            return false;
        }
        if (manage_drone_imagery_multiple_field_trial_add_field_trial_ids[0] == '') {
            alert('First select another field trial to associate to the imaging event.');
            return false;
        }

        jQuery.ajax({
            url: '/api/drone_imagery/save_associated_field_trials?field_trial_id='+manage_drone_imagery_multiple_field_trial_field_trial_id+'&drone_run_project_id='+manage_drone_imagery_multiple_field_trial_drone_run_project_id+'&other_field_trial_ids='+manage_drone_imagery_multiple_field_trial_add_field_trial_ids_string,
            beforeSend: function(){
                jQuery('#working_modal').modal('show');
            },
            success: function(response){
                console.log(response);
                jQuery('#working_modal').modal('hide');

                if (response.error) {
                    alert(response.error);
                }
                else {
                    location.reload();
                }
            },
            error: function(response){
                jQuery('#working_modal').modal('hide');
                alert('Error associating other field trials to imaging event!');
            }
        });
    });

    function showManageDroneImagerySection(section_div_id) {
        console.log(section_div_id);
        if (section_div_id == 'manage_drone_imagery_top_div'){
            jQuery('#manage_drone_imagery_top_div').show();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_plot_polygons_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').show();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_calculate_phenotypes_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').show();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_remove_background_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').show();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_vegetative_index_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').show();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_standard_process_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').show();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_standard_process_raw_images_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').show();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_standard_process_raw_images_interactive_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').show();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_quality_control_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').show();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'project_drone_imagery_ground_control_points_div'){
           jQuery('#manage_drone_imagery_top_div').hide();
           jQuery('#manage_drone_imagery_plot_polygons_div').hide();
           jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
           jQuery('#manage_drone_imagery_remove_background_div').hide();
           jQuery('#manage_drone_imagery_vegetative_index_div').hide();
           jQuery('#manage_drone_imagery_standard_process_div').hide();
           jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
           jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
           jQuery('#project_drone_imagery_ground_control_points_div').show();
           jQuery('#manage_drone_imagery_quality_control_div').hide();
           jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
           jQuery('#manage_drone_imagery_loading_div').hide();
        } else if (section_div_id == 'manage_drone_imagery_field_trial_time_series_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').show();
            jQuery('#manage_drone_imagery_loading_div').hide();
        }
        else if (section_div_id == 'manage_drone_imagery_loading_div'){
            jQuery('#manage_drone_imagery_top_div').hide();
            jQuery('#manage_drone_imagery_plot_polygons_div').hide();
            jQuery('#manage_drone_imagery_calculate_phenotypes_div').hide();
            jQuery('#manage_drone_imagery_remove_background_div').hide();
            jQuery('#manage_drone_imagery_vegetative_index_div').hide();
            jQuery('#manage_drone_imagery_standard_process_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_div').hide();
            jQuery('#manage_drone_imagery_standard_process_raw_images_interactive_div').hide();
            jQuery('#project_drone_imagery_ground_control_points_div').hide();
            jQuery('#manage_drone_imagery_quality_control_div').hide();
            jQuery('#manage_drone_imagery_field_trial_time_series_div').hide();
            jQuery('#manage_drone_imagery_loading_div').show();
        }
        window.scrollTo(0,0);
    }

});

function obsolete_additional_file_aerial_images(trial_id, file_id) {
    var yes = confirm('Are you sure you want to obsolete this file? This operation cannot be undone.');
    if (yes) {
        jQuery.ajax({
            url: '/ajax/breeders/trial/'+trial_id+'/obsolete_uploaded_additional_file/'+file_id,
            success: function(r) {
                if (r.error) { alert(r.error); }
                else {
                    jQuery('#upload_drone_imagery_additional_raw_images_table').DataTable().clear().draw();
                    alert("The file has been obsoleted.");
                }
            },
            error: function(r) {  alert("An error occurred!") }
        });
    }
}
