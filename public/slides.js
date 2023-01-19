/** WebSocket Slide System
 *
 * Apply this to an HTML file and call slides.init(websocket_uri, show_user_interface) 
 *
 * This operates on
 *  <div class="slides">
 *    <div class="slide">...</div>
 *    <div class="slide">...</div>
 *    <div class="slide">...</div>
 *  </div>
 *
 * The margin and padding and scale are altered for each slide to make the content fit
 * the aspect ratio of the viewport.
 *
 * Each slide can have a multi-stage animation caused by showing or hiding elements.
 * Each element can be included in one or more frames of animation by giving it data
 * of "data-step", which is either the frame it becomes visible, or a comma/dash
 * notation specifying a list of frames.  An element with class "auto-step" will have
 * its immediate child DOM elements given sequential data-step values.
 *
 * Each step can also have a "data-extern" indicating an external event that should 
 * "go into effect" when that element is shown.  The external event ends when the
 * element is hidden or when the server says it ends.
 */
window.slides= {
	config: {},
	//ws_uri: null, // URI for making websocket connection
	//mode: null,   // 'presenter', 'main', or 'obs'

	slide_elems: [],
	step_elems: [],
	cur_slide: null,
	cur_extern: null,
	
	init: function(config) {
		var self= this
		if (!config)
			config= self.config
		if (!config.websocket_url)
			config.websocket_url= 'slidelink.io'
		if (!config.mode)
			config.mode= 'obs'
		if (!('code_highlight' in config) && window.hljs)
			config.code_highlight= function(el){ window.hljs.highlightElement(el) }
		self.config= config
		self._fixup_page()
		self._build_ui()
		this.cur_slide= 1;
		for (var i= 1; i < this.slide_elems.length; i++)
			$(this.slide_elems[i]).hide();
		self.reconnect()
	},
	// Perform alterations to the HTML structure of the page to allow
	// less-strict hand-edited content to be automatically upgraded.
	_fixup_page: function() {
		var self= this;
		if (!self.root) {
			if (self.config.root) self.root= self.config.root;
			else if ($('div.slides').length) self.root= $($('div.slides')[0]);
			else {
				// TODO: upgrade body to div.slides
				throw "Can't find div.slides element in document";
			}
		}
		self.root.find('code').each(function() { self._fixup_code_block(this) })
		this.slide_elems= self.root.find('.slide');
		this.slide_elems.each(function() { self._resize_slide(this) })
	},
	// Remove leading whitespace, and convert tabs to spaces, and remove
	// the largest common indent of all lines.
	_fixup_code_block: function(code_el) {
		var text= $(code_el).text();
		text= text.replace(/\t/g, '   '); // tabs to spaces
		text= text.replace(/^\s*\n/g, ''); // remove leading blank line
		text= text.replace(/\n\s*$/g, ''); // remove blank trailing line
		// find the shortest match of whitespace at the start of any line
		var lead_ws_re= new RegExp('^( *)','mg');
		var indent= null;
		while ((matches= lead_ws_re.exec(text)) !== null)
			if (indent === null || matches[1].length < indent) {
				indent= matches[1].length;
				if (indent == 0) break;
			}
		if (indent > 0)
			text= text.replace(new RegExp('^'+(' '.repeat(indent)), 'mg'), '');
		$(code_el).text(text);
		// Apply syntax highlighting if available
		if (this.config.code_highlight)
			this.config.code_highlight(code_el);
	},
	_resize_slide: function(el) {
		var viewport_w= $(window).width();
		var viewport_h= $(window).height();
		var el_w= $(el).innerWidth();
		var el_h= $(el).innerHeight();
		var xscale= viewport_w / el_w;
		var yscale= viewport_h / el_h;
		// Example:
		// 50x10 inside 100x60, xscale=2, yscale=6, pad h with 40, 20 top 20 bottom 
		if (xscale < yscale) {
			var ypad= parseInt((viewport_h - xscale * el_h)/2)+'px';
			var transform= 'scale('+xscale+','+xscale+')';
			$(el).css('margin', ypad+' 0').css('transform', transform);
		} else {
			var ypad= parseInt((viewport_h - el_h)/2)+'px';
			var transform= 'scale('+yscale+','+yscale+')';
			$(el).css('margin', ypad+' 0').css('transform', transform);
		}
	},
	_build_ui: function() {
		var self= this;
		if (!self._button_dispatch)
			self._button_dispatch= function(ev) {
				try {
					self[this.dataset.method].apply(self, ev);
				} catch (e) {
					console.log('Calling slides.'+this.dataset.method+': '+e);
				}
			};
		self.root.prepend(this._public_ui_html);
		self.root.find('button').each(function(){ this.onclick= self._button_dispatch });
		self.root.find('.status-actions button').hide();
	},
	_public_ui_html: (
		'<div class="slides-sidebar">'+
		'  <div class="slides-corner">'+
		'    <button class="slides-sidebar-btn" type="button" data-method="togglemenu" title="Menu">'+
		'      <div class="bar bar1"></div><div class="bar bar2"></div><div class="bar bar3"></div>'+
		'    </button>'+
		'    <div class="slides-notify"></div>'+
		'  </div>'+
		'  <div class="ui"><div class="ui-inner">'+
		'    <h5>Status</h5>'+
		'    <div class="status"></div>'+
		'    <div class="status-actions">'+
		'      <button class="reconnect-btn" type="button" data-method="reconnect">Reconnect</button>'+
		'      <button class="follow-btn" type="button" data-method="follow">Follow</button>'+
		'      <button class="wander-btn" type="button" data-method="stopfollow">Stop Following</button>'+
		'    </div>'+
		'  </div></div>'+
		'</div>'
	),
	togglemenu: function() {
		this.root.find('.slides-sidebar').toggleClass('open');
		var root_top= this.root.offset().top;
		if (this.root.find('.slides-sidebar').hasClass('open')) {
			// show all slides
			this.root.find('.slide').show();
			// and scroll to the one we were just on
			if (this.cur_slide) {
				console.log('leaving cur_slide='+this.cur_slide);
				var slide= this.slide_elems[this.cur_slide-1];
				document.documentElement.scrollTop= $(slide).offset().top;
			}
		} else {
			// hide all but the current slide
			for (var i= 0; i < this.slide_elems.length; i++) {
				console.log(''+i+' top='+$(this.slide_elems[i]).offset().top+' root_top='+root_top+' scroll='+document.documentElement.scrollTop);
				if ($(this.slide_elems[i]).offset().top >= document.documentElement.scrollTop) {
					this.cur_slide= i+1;
					break;
				}
			}
			console.log('entering cur_slide='+this.cur_slide);
			var slide= this.slide_elems[(this.cur_slide || 1)-1];
			this.root.find('.slide').each(function(){ if (this != slide) $(this).hide() })
		}
	},
	_presenter_ui_html: (
		'<div class="slides-control">'+
		'  <div class="navbuttons">'+
		'    <button type="button" data-method="nav_prev">Prev</button>'+
		'    <button type="button" data-method="nav_step">Step</button>'+
		'    <button type="button" data-method="nav_next">Next</button>'+
		'  </div>'+
		'  <div class="presenternotes">'+
		'    <pre></pre>'+
		'  </div>'+
		'</div>'
	),
	reconnect: function() {
		var self= this;
		var url= this.config.websocket_url;
		if (!url.startsWith('ws')) {
			var loc= window.location;
			// Not an absolute URL.
			// First, resolve the path if it was relative.
			if (!url.startsWith('/'))
				url= loc.pathname + (loc.pathname.endsWith('/')? '' : '/') + url;
			url= (loc.protocol == 'https:'? 'wss://' : 'ws://') + window.location.host + url;
		}
		var key= '';
		if (this.config.mode != 'obs')
			key= window.prompt('Key');
		// Connect WebSocket to local event server
		this.ws= new WebSocket(url+'?mode='+this.config.mode+'&key='+encodeURIComponent(key));
		this.ws.onmessage= function(event) { self._handle_ws_event(JSON.parse(event.data)) }
		this.ws.onopen= function(event) { self._handle_connect(event) }
		this.ws.onclose= function(event) { self._handle_disconnect(event) }
		this._set_conn_note('<p>Connecting...</p>')
	},
	_set_conn_note: function(content, duration) {
		var self= this;
		if (this._conn_note) {
			var prev= this._conn_note
			delete this._conn_note
			prev.fadeOut(500, function(){ prev.remove() })
		}
		var next= $(content);
		this.root.find('.slides-notify').append(next);
		this._conn_note= next;
		if (duration)
			window.setTimeout(function(){
				if (self._conn_note == next) this._conn_note= null
				next.fadeOut(500, function(){ next.remove() });
			}, duration);
	},
	_handle_connect: function(event) {
		this.root.find('.reconnect-btn').hide()
		this._set_conn_note('<p>Connected</p>', 1500)
	},
	_handle_disconnect: function(event) {
		this.root.find('.reconnect-btn').show()
		this._set_conn_note('<p>Lost connection</p>')
	},
	_handle_ws_event: function(event) {
		
	},
	// Return true if the input event is destined for a DOM node that takes input
	_event_is_for_input: function(e) {
		return (e.target.tagName == "INPUT"
			|| e.target.tagName == "BUTTON"
			|| e.target.tagName == "TEXTAREA"
			) || (e.originalEvent && this._event_is_for_input(e.originalEvent));
	},
	handle_key: function(e) {
		// Ignore keys for input elements within the slides
		if (this._event_is_for_input(e))
			return true;
		else if (e.keyCode == 39) // ArrowRight
			this.change_slide(1);
		else if (e.keyCode == 37) // ArrowLeft
			this.change_slide(-1);
		else if (e.keyCode == 40 || e.keyCode == 32) // ArrowDown, Space
			this.step(1);
		else if (e.keyCode == 38) // ArrowUp
			this.step(-1);
		else
			return true;
		return false;
	},
	handle_click: function(e) {
		self= this;
		// Ignore clicks for input elements within the slides
		if (this._event_is_for_input(e)) return true;

		var slide_num= $(e.currentTarget).data('slide_num');
		if (slide_num) {
			if (slide_num != self.cur_slide) {
				self.show_slide(slide_num, 0)
					&& self.relay_slide_position();
			}
			else {
				self.show_slide(null, null);
			}
			return false;
		}
	},
	/*
	init: function() {
		var self= this;
		if (!this.mode) {
			// 'presenter' mode drives the slide show, and shows notes
			// 'main' mode shows slides in their official published form while also allowing control
			// 'obs' mode is a read-only observer mode intended for the audience
			this.mode= window.location.pathname.match(/^\/presenter/)? 'presenter'
				: window.location.pathname.match(/^\/main/)? 'main'
				: 'obs';
		}
		if (this.mode == 'main')
			$('body').addClass('high-contrast');
		
		// make a list of DOM nodes for all immediate children of <ol class="slides">
		self.slide_elems= $('ol.slides > li');
		// give each of them a sequence number for quick reference
		self.slide_elems.each(function(idx, e) { self._init_slide(this, idx+1) });
		// register key and click handlers
		$(document).on('keydown', function(e) { return self.handle_key(e.originalEvent); });
		self.slide_elems.on('click', function(e) { self.handle_click(e) });
		// Inject "reconnect" button and register click handler
		$('body').prepend(
			'<div id="websocket-reconnect">'+
			'	<button>Reconnect</button>'+
			'</div>'+
			'<div id="slideshow-join">'+
			'    Follow along at<br>'+
			'    <span class="slideshow-address"></span>'+
			'</div>'
		);
		$('#websocket-reconnect button').on('click', function(e) { self.reconnect(e) });
		$('#slideshow-join').hide();
		// If opened in "control UI mode", inject buttons of UI
		if (this.mode == 'presenter') {
			$('body').prepend(
				'<div id="navbuttons">'+
				'	<button id="nav_prev">Prev</button>'+
				'	<button id="nav_step">Step</button>'+
				'	<button id="nav_next">Next</button>'+
				'</div>'+
				'<div id="presenternotes">'+
				'	<pre></pre>'+
				'</div>'
			);
			$('#nav_prev').on('click', function() { self.change_slide(-1); });
			$('#nav_next').on('click', function() { self.change_slide(1); });
			$('#nav_step').on('click', function() { self.step(1); });
		}
		// Initialize slides in not-slideshow mode
		this.show_slide(null);
		// For each <CODE> tag, remove leading whitespace, and convert tabs to spaces
		$('code').each(function() {
			var text= $(this).text();
			text= text.replace(/\t/g, '   '); // tabs to spaces
			text= text.replace(/^\s*\n/g, ''); // remove leading blank line
			text= text.replace(/\n\s*$/g, ''); // remove blank trailing line
			// find the shortest match of whitespace at the start of any line
			var lead_ws_re= new RegExp('^( *)','mg');
			var indent= null;
			while ((matches= lead_ws_re.exec(text)) !== null)
				if (indent === null || matches[1].length < indent) {
					indent= matches[1].length;
					if (indent == 0) break;
				}
			if (indent > 0)
				text= text.replace(new RegExp('^'+(' '.repeat(indent)), 'mg'), '');
			$(this).text(text);
		});
		// 'presenter' and 'main' need to enter a password, but observers should just auto-connect
		if (this.mode == 'obs') {
			this.reconnect();
			self.show_slide(2, 0);
		}
		if (this.mode == 'presenter') {
			$('.chat-connect input').val('Mike');
			window.chat.connect("nerdvana");
		}
		if (this.mode == 'main') {
			$('.chat-connect input').val('Main');
			window.chat.connect("Main");
		}
	},
	_init_slide: function(slide_dom_node, slide_num) {
		$(slide_dom_node).addClass('slide').data('slide_num', slide_num);
		// Look for .auto-step, and apply step numbers
		var step_num= 1;
		$(slide_dom_node).find('.auto-step').each(function(idx, e) {
			// If it has a step number, and only one, then start the count of its children from that
			var start_step= $(e).data('step');
			if (start_step && start_step.match(/^[0-9]+$/))
				step_num= parseInt(start_step);
			$(e).children().each(function(){ $(this).data('step', [[step_num++]]) });
		});
		// do a deep search to find any element with 'data-step' and give it the class of
		// 'slide-step' for easier selecting later.
		$(slide_dom_node).find('*').each(function(){
			if ($(this).data('step'))
				$(this).addClass('slide-step');
		});
		// Parse each "data-step" specification and replace with an array of ranges
		// Also calculate the step count
		var max_step= 0;
		$(slide_dom_node).find('.slide-step').each(function() {
			var show_list= $(this).data('step');
			if (!Array.isArray(show_list)) {
				show_list= (""+show_list).split(',');
				for (var i= 0; i < show_list.length; i++) {
					show_list[i]= show_list[i].split(/-/);
					show_list[i][0]= parseInt(show_list[i][0]);
					// If a step  has both a start frame and an end frame, then it is "temporary".
					if (show_list[i].length > 1) {
						show_list[i][1]= parseInt(show_list[i][1]);
						$(this).addClass('temporary-step');
					}
				}
				$(this).data('step', show_list);
			}
			var last= show_list[show_list.length-1];
			if (max_step < last[last.length-1])
				max_step= last[last.length-1];
		});
		$(slide_dom_node).data('max_step', max_step);
	},
	handle_extern_event: function(e) {
		//console.log('recv', e);
		// If extern visual has closed, advance to the next slide or step
		if (e['extern_ended'] && e.extern_ended == this.cur_extern)
			this.step_anim(1);
		// If given a slide position, and we are in slide-view mode, go to this one
		if ('slide_num' in e && this.cur_slide)
			this.show_slide(e['slide_num'] || 0, e['step_num'] || 0);
		if ('slide_host' in e) {
			$('.slideshow-address').text(e.slide_host);
			$('#slideshow-join').show();
		}
	},
	emit_extern_event: function(obj) {
		//console.log('send',obj);
		if (this.ws)
			this.ws.send( JSON.stringify(obj) );
		else
			console.log("Can't send: ", obj);
	},
	change_slide: function(ofs) {
		var next_idx= (this.cur_slide? this.cur_slide : 0) + ofs;
		if (next_idx < 0) next_idx += this.slide_elems.length + 1;
		if (next_idx > this.slide_elems.length) next_idx -= this.slide_elems.length + 1;
		this.show_slide(next_idx, ofs > 0? 1 : -1)
			&& self.relay_slide_position();
	},
	step: function(ofs) {
		if (!this.cur_slide) {
			this.show_slide(1,0);
		}
		else {
			var next_slide= this.cur_slide;
			var next_step= this.cur_step + ofs;
			while (next_step < 0) {
				if (! --next_slide) {
					if (next_step == -1) { next_step= 0; break; }
					else { next_slide= this.slide_elems.length-1; next_step += 2; }
				}
				next_step += $(this.slide_elems[next_slide-1]).data('max_step')+1;
			}
			while (next_step > $(this.slide_elems[next_slide-1]).data('max_step')) {
				next_step -= $(this.slide_elems[next_slide-1]).data('max_step')+1;
				if (++next_slide > this.slide_elems.length) {
					if (next_step == 0) { next_slide= 0; break; }
					else { next_slide= 1; }
				}
			}
			this.show_slide(next_slide, next_step);
		}
		this.relay_slide_position();
	},
	client_rect: function(elem) {
		var r= elem.getBoundingClientRect();
		//console.log(elem, r);
		return { top: r.top, left: r.left, right: r.right, bottom: r.bottom };
	},
	show_slide: function(slide_num, step_num) {
		//console.log('show_slide(',slide_num,',',step_num,')');
		var self= this;
		if (!slide_num) {
			// return to scrolling-page mode
			$(document.documentElement).css('overflow','auto');
			// Show all steps for each slide
			this.slide_elems.find('.slide-step')
				.css('visibility','visible')
				.css('position','relative')
				.css('opacity',1);
			// Show all slides
			this.slide_elems.show()
				.css('height','auto')
				.css('transform','none')
				.css('border','1px solid grey');
			if (this.cur_slide) {
				var slide= this.slide_elems[this.cur_slide-1];
				document.documentElement.scrollTop= $(slide).offset().top;
				this.cur_slide= null;
			}
		}
		else {
			var elem= this.slide_elems[ slide_num > 0 ? slide_num-1 : this.slide_elems.length + slide_num ];
			var changed= false;
			if (!this.cur_slide || this.cur_slide != slide_num) {
				// Make sure page is in single-slide mode
				$(document.documentElement).css('overflow','hidden');
				$(elem).show(); // show element, to be able to get its dimensions
				var el_w= $(elem).innerWidth();
				var el_h= $(elem).innerHeight();
				// Hide all slides
				this.slide_elems.hide();
				// Then show this one slide, scaled to the smaller dimension of the viewport
				var viewport_w= $(window).width();
				var viewport_h= $(window).height();
				var xscale= viewport_w / el_w;
				var yscale= viewport_h / el_h;
				var scale= Math.min(xscale, yscale);
				var transform= 'translate(0,'+(-el_h/2+viewport_h/2)+'px) scale('+scale+','+scale+')';
				console.log('transform',transform);
				$(elem).show()
					.css('border','none')
					.css('transform',transform);
				// mark this one as the current slide
				this.cur_slide= slide_num;
				this.cur_step= null;
				changed= true;
			}
			var max_step= $(elem).data('max_step');
			if (step_num < 0) step_num= max_step + 1 + step_num;
			if (step_num < 0) step_num= 0;
			if (changed || step_num != this.cur_step) {
				$(elem).find('.slide-step').each(function() {
					// If a step is not visible, behavior depends on whether we are the presenter
					// and whether the element is temporary.  Non-temporary elements need to remain
					// in the document flow so that the layout of the rest doesn't jump around.
					// But temporary have to be removed from the layout so that they don't occupy
					// space.  Meanwhile the presenter gets to see all hidden elements.
					if (self._is_shown_on_step(this, step_num))
						$(this).css('visibility','visible').css('position','relative').css('opacity',1);
					else {
						if (self.mode == 'presenter')
							$(this).css('visibility','visible').css('opacity', .3);
						else
							$(this).css('visibility','hidden');
						if ($(this).hasClass('temporary-step'))
							$(this).css('position','absolute');
					}
				});
				this.cur_step= step_num;
				changed= true;
			}
			var figure= $(elem).find('figure');
			this.cur_figure= figure.length? figure[0] : null;
			var prev_extern= this.cur_extern;
			this.cur_extern= figure.length? figure.data('extern') : null;
			this.cur_notes= $(elem).find('.notes').text();
			if (this.mode == 'presenter') {
				$('#presenternotes pre').text(this.cur_notes);
			}
			else if (changed && (prev_extern || this.cur_extern)) {
				this.emit_extern_event({
					extern: this.mode == 'main'? (this.cur_extern? this.cur_extern : '-') : null,
					elem_rect:
						this.cur_figure? this.client_rect(this.cur_figure)
						: this.slide_num? this.client_rect(this.slide_elems[this.slide_num-1])
						: null
				});
			}
		}
		return changed;
	},
	_is_shown_on_step: function(elem, step_num) {
		var show_on= $(elem).data('step');
		var shown= false;
		if (show_on)
			$.each(show_on, function(i, range) {
				if (step_num >= range[0] && (range.length==1 || step_num <= range[1]))
					shown= true;
			});
		return shown;
	},
	relay_slide_position: function() {
		if (this.cur_slide)
			this.emit_extern_event({
				slide_num: this.cur_slide,
				step_num: this.cur_step,
			});
	}
	*/
};
