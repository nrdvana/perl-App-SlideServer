package App::SlideServer;
use v5.36;
use Mojo::Base 'Mojolicious';
use Mojo::WebSocket 'WS_PING';
use Mojo::File 'path';
use Mojo::DOM;
use Log::Any '$log';
use Text::Markdown::Hoedown;

#ABSTRACT: Mojo web server that serves slides and websocket
#VERSION:

# Files that ship with the distribution
has share_dir => sub {
	if (-f path(__FILE__)->sibling('..','..','share','public','slides.js')) {
		return path(__FILE__)->sibling('..','..','share')->realpath;
	} else {
		require File::ShareDir;
		return path(File::ShareDir::dist_dir('App-SlideServer'));
	}
};

# Files supplied by the user to override the distribution
has serve_dir => sub { path(shift->home) };

# Hashref of { ID => $context } for every connected websocket
has viewers => sub { +{} };

# Hashref of data to be pushed to all clients
has published_state => sub { +{} };

has presenter_key => sub {
	my $key= sprintf "%06d", rand 1000000;
	$log->info("Auto-generated presenter key: $key");
	return $key;
};

sub slides_source_file($self) {
	my ($src)= grep -f $_,
		$self->serve_dir->child('slides.md'),
		$self->serve_dir->child('public','slides.md'),
		$self->serve_dir->child('slides.html'),
		$self->serve_dir->child('public','slides.html');
	return $src;
}

sub startup($self) {
	$self->presenter_key;
	$self->static->paths([ $self->share_dir->child('public'), $self->serve_dir->child('public') ]);
	$self->routes->get('/' => sub($c){ $c->render(text => $c->app->render_slides) });
	$self->routes->websocket('/slidelink.io' => sub($c){ $c->app->init_websocket($c) });
}

sub render_slides($self) {
	my $srcfile= $self->slides_source_file
		or die "No source file; require slides.md or slides.html in serve_dir '".$self->serve_dir."'\n";
	my $content= $srcfile->slurp;
	$content= $self->markdown_to_html($content)
		if $srcfile =~ /[.]md$/;
	return $self->transform_slides_dom($content);
}

sub markdown_to_html($self, $md) {
	return markdown($md, extensions => (
		HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FENCED_CODE | HOEDOWN_EXT_AUTOLINK | HOEDOWN_EXT_STRIKETHROUGH
		| HOEDOWN_EXT_UNDERLINE | HOEDOWN_EXT_QUOTE | HOEDOWN_EXT_SUPERSCRIPT | HOEDOWN_EXT_NO_INTRA_EMPHASIS
		| HOEDOWN_EXT_DISABLE_INDENTED_CODE
		)
	);
}

# This function takes partial HTML (or full HTML) and upgrades it to full HTML
# with the needed css and js for the slides.
sub transform_slides_dom($self, $html) {
	my $custom= Mojo::DOM->new($html);
	my $result= Mojo::DOM->new($self->share_dir->child('public','slides.html')->slurp);
	# Remove the example slides
	$result->at('body')->replace('<body></body>');
	# If custom defines a <head>, merge its elements into the example
	# TODO: prevent redundant header elements
	$result->at('head')->append_content($custom->at('head')->child_nodes)
		if $custom->at('head');
	$result->at('body')->append_content('<div class="slides"></div>');
	my $slides= $result->at('div.slides');
	# Find each custom element that is an immediate child of body, and add it to
	# the current slide until the next <h1> <h2> or <div class="slide"> at which
	# point, move to the next slide.
	my $cur_slide;
	for (($custom->at('div.slides') || $custom->at('body') || $custom)->@*) {
		my $tag= lc($_->tag // '');
		# is it a whole pre-defined slide
		if ($tag eq 'div' && $_->{class} =~ /\bslide\b/) {
			$cur_slide= undef;
			$slides->append_content($_);
		}
		else {
			# start a new slide every time H1 or H2 seen
			$cur_slide= undef if $tag eq 'h1' || $tag eq 'h2';
			# Add "auto-step" to any <UL> tags
			$_->{class}= "auto-step" if ($tag eq 'ul' || $tag eq 'ol') && !$_->{class};
			$cur_slide //= do {
				$slides->append_content('<div class="slide"></div>');
				$slides->children('div.slide')->last;
			};
			$cur_slide->append_content($_);
		}
	}
	return "$result";
}

sub update_published_state($self, @new_attrs) {
	$self->published_state->%* = ( $self->published_state->%*, @new_attrs );
	$_->send({ json => { state => $self->published_state } })
		for values $self->viewers->%*;
}

sub init_websocket($self, $c) {
	my $id= $c->req->request_id;
	$self->viewers->{$id}= $c;
	my $mode= $c->req->param('mode');
	my $key= $c->req->param('key');
	my %roles= ( follow => 1 );
	if ($mode eq 'presenter') {
		if (($key||'') eq $self->presenter_key) {
			$roles{lead}= 1;
			$self->update_published_state(viewer_count => scalar keys $self->viewers->%*);
		}
	}
	$c->stash('roles', join ',', keys %roles);
	$log->infof("%s (%s) connected as %s", $id, $c->tx->remote_address, $c->stash('roles'));
	$c->send({ json => { roles => [ keys %roles ] } });
	
	$c->on(json => sub($c, $msg, @) { $c->app->on_websocket_message($c, $msg) });
	$c->on(finish => sub($c, @) { $c->app->on_websocket_disconnect($c) });
	$c->inactivity_timeout(3600);
	#my $keepalive= Mojo::IOLoop->recurring(60 => sub { $viewers{$id}->send([1, 0, 0, 0, WS_PING, '']); });
	#$c->stash(keepalive => $keepalive);
}
sub on_websocket_message($self, $c, $msg) {
	my $id= $c->req->request_id;
	$log->debugf("client %s %s msg=%s", $id, $c->tx->original_remote_address, $msg) if $log->is_debug;
	if ($c->stash('roles') =~ /\blead\b/) {
		if (defined $msg->{extern}) {
		}
		if (defined $msg->{slide_num}) {
			$self->update_published_state(slide_num => $msg->{slide_num}, step_num => $msg->{step_num});
		}
	}
}
sub on_websocket_disconnect($self, $c) {
	my $id= $c->req->request_id;
	#Mojo::IOLoop->remove($keepalive);
	delete $self->viewers->{$id};
	$self->update_published_state(viewer_count => scalar keys $self->viewers->%*);
}

1;
