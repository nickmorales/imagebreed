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
        showManageDroneRoverSection('manage_drone_imagery_standard_process_div');

        manage_drone_imagery_standard_process_private_company_id = jQuery(this).data('private_company_id');
        manage_drone_imagery_standard_process_private_company_is_private = jQuery(this).data('private_company_is_private');
        manage_drone_imagery_standard_process_drone_run_project_id = jQuery(this).data('drone_run_project_id');
        manage_drone_imagery_standard_process_field_trial_id = jQuery(this).data('field_trial_id');
        manage_drone_imagery_standard_process_field_trial_name = jQuery(this).data('field_trial_name');
        project_drone_imagery_ground_control_points_drone_run_project_id = manage_drone_imagery_standard_process_drone_run_project_id;
        project_drone_imagery_ground_control_points_drone_run_project_name = jQuery(this).data('drone_run_project_name');
    });

    function showManageDroneRoverSection(section_div_id) {
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
        }
        window.scrollTo(0,0);
    }

});
