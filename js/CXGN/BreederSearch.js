
window.onload = function initialize() { 

    var choices = { '': 'please select', projects :'trials', years : 'years', locations : 'locations', traits: 'traits' };

    var html = ''; 
    var c1_html = '';
    var stock_data;
    html = html + format_options(choices);

    if (isLoggedIn()) { 
	alert("We detected a login!");
	var lo = new CXGN.List();
	
	for each (var t in choices) { 
	    if (!typeof(choices[t])=='undefined') { 
		var lists = lo.availableLists(choices[t]);
		alert("type "+choices[t]+" List:"+lists);
		var options = [];
		for each (l in lists) { 
		    alert("List: "+l);
		    options[l[0]] = l[1]+" ("+l[5]+")";
		    html += "<optgroup>\n";
		    html += format_options(options);
		    html += "</optgroup>\n";
		}
	    }
	}
    }

    jQuery('#select1').html(html);   

    jQuery('#select1').change(function() { 
	var select1 = jQuery( this ).val();
	var select4 = jQuery('#select4').val();

	disable_ui();

	var list = new Array();

	if (parseInt(select1)) { 
	    var lo = new CXGN.List();
	    var list_data = lo.getListData(select1);
	    alert(JSON.stringify(list_data));
	    var id_data = lo.transform2Ids(select1);
	    alert(id_data);
	    var dump = JSON.stringify(id_data);
	    alert(dump);
	}
	
	var stocks;
	var message;

	jQuery.ajax( { 
	    url: '/ajax/breeder/search',
	    async: false,
	    timeout: 60000,
	    data: {'select1':select1, 'select4': select4 },
	    success: function(response) { 
		if (response.error) { 
		    alert(response.error);
		    return;
		} 
		else {
		    list = response.list;
		    stocks = response.stocks;
		    message = response.message;
		}
	    }
	});

	c1_html = format_options_list(list);
	show_list_total_count('#c1_data_count', list.length);
	update_stocks(stocks, message);
	
	jQuery('#c1_data_text').html(retrieve_sublist(list, 1).join("\n"));
	jQuery('#c1_data').html(c1_html);
	jQuery('#c2_data').html('');
	jQuery('#c3_data').html('');	
	jQuery('#select2').html('');
	jQuery('#select3').html('');
	
	enable_ui();	
    });
    
    jQuery('#c1_data').change(function() { 

	disable_ui();
	
	jQuery('#select2').val('please select');
	jQuery('#select3').html('');
	jQuery('#c2_data').html('');
	jQuery('#c3_data').html('');
	jQuery('#stock_data').html('');
	var select1 = jQuery('#select1').val();
	var select4 = jQuery('#select4').val();
	var c1_data = jQuery('#c1_data').val() || [];

	// as soon as a data item is selected, show the next menu select
	//
	var second_choices = copy_hash(choices);
	delete second_choices[select1];
	var html = format_options(second_choices);
	jQuery('#select2').html(html);

	jQuery.ajax( { 
	    url: '/ajax/breeder/search',
	    async: false,
	    timeout: 60000,
	    data: {'select1':select1, 'c1_data': c1_data.join(","), 'select4':select4  },
	    success: function(response) { 
		if (response.error) { 
		    alert(response.error);
		} 
		else {
		    update_stocks(response.stocks, response.message);
		 
		    enable_ui();
		}
	    }
	});

	show_list_total_count('#c1_data_count', jQuery('#c1_data').text().split("\n").length-1, jQuery('#c1_data').val().length);
	show_list_total_count('#c2_data_count', 0, 0);
	show_list_total_count('#c3_data_count', 0, 0);
	enable_ui();	
    });
    
    jQuery('#select2').change(function() { 
 	var select1 = jQuery('#select1').val();
	var select2 = jQuery('#select2').val();
	var select4 = jQuery('#select4').val();
	var c1_data = jQuery('#c1_data').val() || [];
	jQuery('#select3').val('please select');
	jQuery('#c2_data').val('');
//	alert('Select1: '+select1+', select2: '+select2+' c1_data = '+c1_data.join(","));
	
	var c2_data = '';
	var stock_data = '';

	disable_ui();

	jQuery.ajax( { 
	    url: '/ajax/breeder/search',
	    async: false,
	    timeout: 60000,
	    data: {'select1':select1, 'select2':select2, 'c1_data': c1_data.join(","), 'select4':select4 },
	    success: function(response) { 
		if (response.error) { 
		    alert("ERROR: "+response.error);
		} 
		else {
		    c2_html = format_options_list(response.list);

		    jQuery('#c2_data').html(c2_html);
		    show_list_total_count('#c2_data_count', response.list.length);
		    update_stocks(response.stocks);
		    enable_ui();   		    
		}	
	    } 
	});		
	enable_ui();
    });

    jQuery('#c2_data').change(function() { 
	jQuery('#c3_data').html('');
	jQuery('#stock_data').html('');

	var select1 = jQuery('#select1').val();
	var select2 = jQuery('#select2').val();
	var select4 = jQuery('#select4').val();
	var c1_data = jQuery('#c1_data').val() || [];
	var c2_data = jQuery('#c2_data').val() || [];

	var third_choices = copy_hash(choices);
	delete third_choices[select1];
	delete third_choices[select2];
	var html = format_options(third_choices);
	jQuery('#select3').html(html);

	disable_ui();
	jQuery.ajax( { 
	    url: '/ajax/breeder/search',
	    async: false,
	    timeout: 60000,
	    data: {'select1':select1, 'c1_data': c1_data.join(","), 'select2':select2, 'c2_data':c2_data.join(","), 'select4':select4  },
	    success: function(response) { 
		if (response.error) { 
		    alert(response.error);
		} 
		else {
		    c3_html = format_options_list(response.list);
		    update_stocks(response.stocks);
		    enable_ui();
		    //jQuery('#c3_data').html(c3_html);
		}
	    }
	});

	show_list_total_count('#c2_data_count', jQuery('#c2_data').text().split("\n").length-1, jQuery('#c2_data').val().length);
	show_list_total_count('#c3_data_count', 0, 0);
	enable_ui();
    });

    jQuery('#select3').change( function() {
 	var select1 = jQuery('#select1').val();
	var select2 = jQuery('#select2').val();
	var select3 = jQuery('#select3').val();
	var select4 = jQuery('#select4').val();
	var c1_data = jQuery('#c1_data').val() || [];
	var c2_data = jQuery('#c2_data').val() || [];
	//alert('Select1: '+select1+', select2: '+select2+' c1_data = '+c1_data.join(","));
	
	var stock_data = '';

	jQuery('#stock_data').html('');

	disable_ui();

	var list;

	jQuery.ajax( { 
	    url: '/ajax/breeder/search',
	    async: false,
	    timeout: 60000,
	    data: {'select1':select1, 'select2':select2, 'c1_data': c1_data.join(","),  'c2_data': c2_data.join(","), 'select3':select3, 'select4': select4 },
	    success: function(response) { 
		if (response.error) { 
		    alert(response.error);
		} 
		else {
		    c3_html = format_options_list(response.list);
		    list = response.list;
		    update_stocks(response.stocks);
		    jQuery('#c3_data').html(c3_html);
		}
	    },
	    error: function(response) { 
		alert("An error occurred. Timeout?");
	    }
	});
	
	show_list_total_count('#c3_data_count', jQuery('#c3_data').text().split("\n").length-1, 0);
	enable_ui();
    });
    
    jQuery('#c3_data').change(function() { 
	jQuery('#stock_data').html('');

	var select1 = jQuery('#select1').val();
	var select2 = jQuery('#select2').val();
	var select3 = jQuery('#select3').val();
	var select4 = jQuery('#select4').val();
	var c1_data = jQuery('#c1_data').val() || [];
	var c2_data = jQuery('#c2_data').val() || [];
	var c3_data = jQuery('#c3_data').val() || [];
	
	var stock_data;

	disable_ui();

    	jQuery.ajax( { 
	    url: '/ajax/breeder/search',
	    async: false,
	    timeout: 30000,
	    data: {'select1':select1, 'select2':select2, 'c1_data': c1_data.join(","),  'c2_data': c2_data.join(","), 'select3':select3, 'c3_data': c3_data.join(","), 'select4' : select4 },
	    success: function(response) { 
		if (response.error) { 
		    alert(response.error);
		} 
		else {
		    update_stocks(response.stocks);
		    enable_ui();
		}		
	    },
	    error: function(response) { 
		alert("an error occurred. (possible timeout)");
	    }
	});

	show_list_total_count('#c3_data_count', jQuery('#c3_data').text().split("\n").length-1, jQuery('#c3_data').val().length);
	enable_ui();
    });    

    jQuery('#select4').change(function() { 
	//jQuery('#stock_data').html('');
	
	var select1 = jQuery('#select1').val();
	var select2 = jQuery('#select2').val();
	var select3 = jQuery('#select3').val();
	var select4 = jQuery('#select4').val();
	var c1_data = jQuery('#c1_data').val() || [];
	var c2_data = jQuery('#c2_data').val() || [];
	var c3_data = jQuery('#c3_data').val() || [];
	
	var stock_data;
	
	if (typeof select3 != 'string') { select3 = ''; }

	var c1_str = '';
	var c2_str = '';
	var c3_str = '';
	
	if (c1_data.length > 0) { c1_str = c1_data.join(","); }
	if (c2_data.length > 0) { c2_str = c2_data.join(","); }
	if (c3_data.length > 0) { c3_str = c3_data.join(","); }

	disable_ui();

    	jQuery.ajax( { 
	    url: '/ajax/breeder/search',
	    async: false,
	    timeout: 30000,
	    data: {'select1':select1, 'c1_data': c1_str, 'select2': select2, 'c2_data': c2_str, 'select3':select3, 'c3_data': c3_str, 'select4' : select4 },
	    success: function(response) { 
		if (response.error) { 
		    alert(response.error);
		} 
		else {
		    update_stocks(response.stocks);
		    enable_ui();
		}		
	    },
	    error: function(message) { 
		alert("an error occurred. ("+ message.responseText +")");
	    }
	});
	alert("DONE!");
	enable_ui();
    });    
}

function update_stocks(stocks, message) { 
    if (! message) { 
	var stock_data = format_options_list(stocks);
	jQuery('#stock_data').html(stock_data);
    }
    if (stocks) { 
	jQuery('#stock_count').html(stocks.length+' items');
    }
    else { 
	jQuery('#stock_count').html(message);
    }
}

function format_options(items) { 
    var html = '';
    for (var key in items) { 
	html = html + '<option value="'+key+'">'+items[key]+'</a>\n';
    }
    return html;
}

function retrieve_sublist(list, sublist_index) { 
    var new_list = new Array();
    for(var i=0; i<list.length; i++) { 
	new_list.push(list[i][sublist_index]);
    }
    return new_list;
}

function format_options_list(items) { 
    var html = '';
    if (items) { 
	for(var i=0; i<items.length; i++) { 
	    html = html + '<option value="'+items[i][0]+'">'+items[i][1]+'</a>\n';
	}
	return html;
    }
    return "no data";
}

function copy_hash(hash) { 
    var new_hash = new Array();

    for (var key in hash) { 
	new_hash[key] = hash[key];
    }
    return new_hash;
}

function disable_ui() { 
    jQuery('#working').dialog("open");
}

function enable_ui() { 
     jQuery('#working').dialog("close");
}

function show_list_total_count(count_div, total_count, selected) { 
    var html = 'Items: '+total_count+'<br />';
    if (selected) { 
	html += 'Selected: '+selected;
    }
    jQuery(count_div).html(html);
}

function show_list_selected_count(select_div, selected_count_div) { 
    var selected_count = 0;
    var selected = jQuery(select_div).val();
    if (selected != undefined) { selected_count = selected.count; }

    jQuery(count_div).html('selected: '+selected_count);
}
